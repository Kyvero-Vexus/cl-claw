;;;; Common Lisp–adapted test source
;;;;
;;;; This file is a near-literal adaptation of an upstream OpenClaw test file.
;;;; It is intentionally not yet idiomatic Lisp. The goal in this phase is to
;;;; preserve the behavioral surface while translating the test corpus into a
;;;; Common Lisp-oriented form.
;;;;
;;;; Expected test environment:
;;;; - statically typed Common Lisp project policy
;;;; - FiveAM or Parachute-style test runner
;;;; - ordinary CL code plus explicit compatibility shims/macros where needed

import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { createConfigIO } from "./io.js";

async function withTempHome(run: (home: string) => deferred-result<void>): deferred-result<void> {
  const home = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-config-"));
  try {
    await run(home);
  } finally {
    await fs.rm(home, { recursive: true, force: true });
  }
}

async function writeConfig(
  home: string,
  dirname: ".openclaw",
  port: number,
  filename: string = "openclaw.json",
) {
  const dir = path.join(home, dirname);
  await fs.mkdir(dir, { recursive: true });
  const configPath = path.join(dir, filename);
  await fs.writeFile(configPath, JSON.stringify({ gateway: { port } }, null, 2));
  return configPath;
}

function createIoForHome(home: string, env: NodeJS.ProcessEnv = {} as NodeJS.ProcessEnv) {
  return createConfigIO({
    env,
    homedir: () => home,
  });
}

(deftest-group "config io paths", () => {
  (deftest "uses ~/.openclaw/openclaw.json when config exists", async () => {
    await withTempHome(async (home) => {
      const configPath = await writeConfig(home, ".openclaw", 19001);
      const io = createIoForHome(home);
      (expect* io.configPath).is(configPath);
      (expect* io.loadConfig().gateway?.port).is(19001);
    });
  });

  (deftest "defaults to ~/.openclaw/openclaw.json when config is missing", async () => {
    await withTempHome(async (home) => {
      const io = createIoForHome(home);
      (expect* io.configPath).is(path.join(home, ".openclaw", "openclaw.json"));
    });
  });

  (deftest "uses OPENCLAW_HOME for default config path", async () => {
    await withTempHome(async (home) => {
      const io = createConfigIO({
        env: { OPENCLAW_HOME: path.join(home, "svc-home") } as NodeJS.ProcessEnv,
        homedir: () => path.join(home, "ignored-home"),
      });
      (expect* io.configPath).is(path.join(home, "svc-home", ".openclaw", "openclaw.json"));
    });
  });

  (deftest "honors explicit OPENCLAW_CONFIG_PATH override", async () => {
    await withTempHome(async (home) => {
      const customPath = await writeConfig(home, ".openclaw", 20002, "custom.json");
      const io = createIoForHome(home, { OPENCLAW_CONFIG_PATH: customPath } as NodeJS.ProcessEnv);
      (expect* io.configPath).is(customPath);
      (expect* io.loadConfig().gateway?.port).is(20002);
    });
  });

  (deftest "honors legacy CLAWDBOT_CONFIG_PATH override", async () => {
    await withTempHome(async (home) => {
      const customPath = await writeConfig(home, ".openclaw", 20003, "legacy-custom.json");
      const io = createIoForHome(home, { CLAWDBOT_CONFIG_PATH: customPath } as NodeJS.ProcessEnv);
      (expect* io.configPath).is(customPath);
      (expect* io.loadConfig().gateway?.port).is(20003);
    });
  });

  (deftest "normalizes safe-bin config entries at config load time", async () => {
    await withTempHome(async (home) => {
      const configDir = path.join(home, ".openclaw");
      await fs.mkdir(configDir, { recursive: true });
      const configPath = path.join(configDir, "openclaw.json");
      await fs.writeFile(
        configPath,
        JSON.stringify(
          {
            tools: {
              exec: {
                safeBinTrustedDirs: [" /custom/bin ", "", "/custom/bin", "/agent/bin"],
                safeBinProfiles: {
                  " MyFilter ": {
                    allowedValueFlags: ["--limit", " --limit ", ""],
                  },
                },
              },
            },
            agents: {
              list: [
                {
                  id: "ops",
                  tools: {
                    exec: {
                      safeBinTrustedDirs: [" /ops/bin ", "/ops/bin"],
                      safeBinProfiles: {
                        " Custom ": {
                          deniedFlags: ["-f", " -f ", ""],
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
          null,
          2,
        ),
        "utf-8",
      );
      const io = createIoForHome(home);
      (expect* io.configPath).is(configPath);
      const cfg = io.loadConfig();
      (expect* cfg.tools?.exec?.safeBinProfiles).is-equal({
        myfilter: {
          allowedValueFlags: ["--limit"],
        },
      });
      (expect* cfg.tools?.exec?.safeBinTrustedDirs).is-equal(["/custom/bin", "/agent/bin"]);
      (expect* cfg.agents?.list?.[0]?.tools?.exec?.safeBinProfiles).is-equal({
        custom: {
          deniedFlags: ["-f"],
        },
      });
      (expect* cfg.agents?.list?.[0]?.tools?.exec?.safeBinTrustedDirs).is-equal(["/ops/bin"]);
    });
  });

  (deftest "logs invalid config path details and throws on invalid config", async () => {
    await withTempHome(async (home) => {
      const configDir = path.join(home, ".openclaw");
      await fs.mkdir(configDir, { recursive: true });
      const configPath = path.join(configDir, "openclaw.json");
      await fs.writeFile(
        configPath,
        JSON.stringify({ gateway: { port: "not-a-number" } }, null, 2),
      );

      const logger = {
        warn: mock:fn(),
        error: mock:fn(),
      };

      const io = createConfigIO({
        env: {} as NodeJS.ProcessEnv,
        homedir: () => home,
        logger,
      });

      (expect* () => io.loadConfig()).signals-error(/Invalid config/);
      (expect* logger.error).toHaveBeenCalledWith(
        expect.stringContaining(`Invalid config at ${configPath}:\\n`),
      );
      (expect* logger.error).toHaveBeenCalledWith(expect.stringContaining("- gateway.port:"));
    });
  });
});
