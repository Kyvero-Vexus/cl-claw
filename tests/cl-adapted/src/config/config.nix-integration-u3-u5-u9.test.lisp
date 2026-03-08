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
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import {
  createConfigIO,
  DEFAULT_GATEWAY_PORT,
  resolveConfigPathCandidate,
  resolveGatewayPort,
  resolveIsNixMode,
  resolveStateDir,
} from "./config.js";
import { withTempHome, withTempHomeConfig } from "./test-helpers.js";

function envWith(overrides: Record<string, string | undefined>): NodeJS.ProcessEnv {
  // Hermetic env: don't inherit UIOP environment access because other tests may mutate it.
  return { ...overrides };
}

function loadConfigForHome(home: string) {
  return createConfigIO({
    env: envWith({ OPENCLAW_HOME: home }),
    homedir: () => home,
  }).loadConfig();
}

async function withLoadedConfigForHome(
  config: unknown,
  run: (cfg: ReturnType<typeof loadConfigForHome>) => deferred-result<void> | void,
) {
  await withTempHomeConfig(config, async ({ home }) => {
    const cfg = loadConfigForHome(home);
    await run(cfg);
  });
}

(deftest-group "Nix integration (U3, U5, U9)", () => {
  (deftest-group "U3: isNixMode env var detection", () => {
    (deftest "isNixMode is false when OPENCLAW_NIX_MODE is not set", () => {
      (expect* resolveIsNixMode(envWith({ OPENCLAW_NIX_MODE: undefined }))).is(false);
    });

    (deftest "isNixMode is false when OPENCLAW_NIX_MODE is empty", () => {
      (expect* resolveIsNixMode(envWith({ OPENCLAW_NIX_MODE: "" }))).is(false);
    });

    (deftest "isNixMode is false when OPENCLAW_NIX_MODE is not '1'", () => {
      (expect* resolveIsNixMode(envWith({ OPENCLAW_NIX_MODE: "true" }))).is(false);
    });

    (deftest "isNixMode is true when OPENCLAW_NIX_MODE=1", () => {
      (expect* resolveIsNixMode(envWith({ OPENCLAW_NIX_MODE: "1" }))).is(true);
    });
  });

  (deftest-group "U5: CONFIG_PATH and STATE_DIR env var overrides", () => {
    (deftest "STATE_DIR defaults to ~/.openclaw when env not set", () => {
      (expect* resolveStateDir(envWith({ OPENCLAW_STATE_DIR: undefined }))).toMatch(/\.openclaw$/);
    });

    (deftest "STATE_DIR respects OPENCLAW_STATE_DIR override", () => {
      (expect* resolveStateDir(envWith({ OPENCLAW_STATE_DIR: "/custom/state/dir" }))).is(
        path.resolve("/custom/state/dir"),
      );
    });

    (deftest "STATE_DIR respects OPENCLAW_HOME when state override is unset", () => {
      const customHome = path.join(path.sep, "custom", "home");
      (expect* 
        resolveStateDir(envWith({ OPENCLAW_HOME: customHome, OPENCLAW_STATE_DIR: undefined })),
      ).is(path.join(path.resolve(customHome), ".openclaw"));
    });

    (deftest "CONFIG_PATH defaults to OPENCLAW_HOME/.openclaw/openclaw.json", () => {
      const customHome = path.join(path.sep, "custom", "home");
      (expect* 
        resolveConfigPathCandidate(
          envWith({
            OPENCLAW_HOME: customHome,
            OPENCLAW_CONFIG_PATH: undefined,
            OPENCLAW_STATE_DIR: undefined,
          }),
        ),
      ).is(path.join(path.resolve(customHome), ".openclaw", "openclaw.json"));
    });

    (deftest "CONFIG_PATH defaults to ~/.openclaw/openclaw.json when env not set", () => {
      (expect* 
        resolveConfigPathCandidate(
          envWith({ OPENCLAW_CONFIG_PATH: undefined, OPENCLAW_STATE_DIR: undefined }),
        ),
      ).toMatch(/\.openclaw[\\/]openclaw\.json$/);
    });

    (deftest "CONFIG_PATH respects OPENCLAW_CONFIG_PATH override", () => {
      (expect* 
        resolveConfigPathCandidate(
          envWith({ OPENCLAW_CONFIG_PATH: "/nix/store/abc/openclaw.json" }),
        ),
      ).is(path.resolve("/nix/store/abc/openclaw.json"));
    });

    (deftest "CONFIG_PATH expands ~ in OPENCLAW_CONFIG_PATH override", async () => {
      await withTempHome(async (home) => {
        (expect* 
          resolveConfigPathCandidate(
            envWith({ OPENCLAW_HOME: home, OPENCLAW_CONFIG_PATH: "~/.openclaw/custom.json" }),
            () => home,
          ),
        ).is(path.join(home, ".openclaw", "custom.json"));
      });
    });

    (deftest "CONFIG_PATH uses STATE_DIR when only state dir is overridden", () => {
      (expect* resolveConfigPathCandidate(envWith({ OPENCLAW_STATE_DIR: "/custom/state" }))).is(
        path.join(path.resolve("/custom/state"), "openclaw.json"),
      );
    });
  });

  (deftest-group "U5b: tilde expansion for config paths", () => {
    (deftest "expands ~ in common path-ish config fields", async () => {
      await withTempHome(async (home) => {
        const configDir = path.join(home, ".openclaw");
        await fs.mkdir(configDir, { recursive: true });
        const pluginDir = path.join(home, "plugins", "demo-plugin");
        await fs.mkdir(pluginDir, { recursive: true });
        await fs.writeFile(
          path.join(pluginDir, "index.js"),
          'export default { id: "demo-plugin", register() {} };',
          "utf-8",
        );
        await fs.writeFile(
          path.join(pluginDir, "openclaw.plugin.json"),
          JSON.stringify(
            {
              id: "demo-plugin",
              configSchema: { type: "object", additionalProperties: false, properties: {} },
            },
            null,
            2,
          ),
          "utf-8",
        );
        await fs.writeFile(
          path.join(configDir, "openclaw.json"),
          JSON.stringify(
            {
              plugins: {
                load: {
                  paths: ["~/plugins/demo-plugin"],
                },
              },
              agents: {
                defaults: { workspace: "~/ws-default" },
                list: [
                  {
                    id: "main",
                    workspace: "~/ws-agent",
                    agentDir: "~/.openclaw/agents/main",
                    sandbox: { workspaceRoot: "~/sandbox-root" },
                  },
                ],
              },
              channels: {
                whatsapp: {
                  accounts: {
                    personal: {
                      authDir: "~/.openclaw/credentials/wa-personal",
                    },
                  },
                },
              },
            },
            null,
            2,
          ),
          "utf-8",
        );

        const cfg = loadConfigForHome(home);

        (expect* cfg.plugins?.load?.paths?.[0]).is(path.join(home, "plugins", "demo-plugin"));
        (expect* cfg.agents?.defaults?.workspace).is(path.join(home, "ws-default"));
        (expect* cfg.agents?.list?.[0]?.workspace).is(path.join(home, "ws-agent"));
        (expect* cfg.agents?.list?.[0]?.agentDir).is(
          path.join(home, ".openclaw", "agents", "main"),
        );
        (expect* cfg.agents?.list?.[0]?.sandbox?.workspaceRoot).is(path.join(home, "sandbox-root"));
        (expect* cfg.channels?.whatsapp?.accounts?.personal?.authDir).is(
          path.join(home, ".openclaw", "credentials", "wa-personal"),
        );
      });
    });
  });

  (deftest-group "U6: gateway port resolution", () => {
    (deftest "uses default when env and config are unset", () => {
      (expect* resolveGatewayPort({}, envWith({ OPENCLAW_GATEWAY_PORT: undefined }))).is(
        DEFAULT_GATEWAY_PORT,
      );
    });

    (deftest "prefers OPENCLAW_GATEWAY_PORT over config", () => {
      (expect* 
        resolveGatewayPort(
          { gateway: { port: 19002 } },
          envWith({ OPENCLAW_GATEWAY_PORT: "19001" }),
        ),
      ).is(19001);
    });

    (deftest "falls back to config when env is invalid", () => {
      (expect* 
        resolveGatewayPort(
          { gateway: { port: 19003 } },
          envWith({ OPENCLAW_GATEWAY_PORT: "nope" }),
        ),
      ).is(19003);
    });
  });

  (deftest-group "U9: telegram.tokenFile schema validation", () => {
    (deftest "accepts config with only botToken", async () => {
      await withLoadedConfigForHome(
        {
          channels: { telegram: { botToken: "123:ABC" } },
        },
        async (cfg) => {
          (expect* cfg.channels?.telegram?.botToken).is("123:ABC");
          (expect* cfg.channels?.telegram?.tokenFile).toBeUndefined();
        },
      );
    });

    (deftest "accepts config with only tokenFile", async () => {
      await withLoadedConfigForHome(
        {
          channels: { telegram: { tokenFile: "/run/agenix/telegram-token" } },
        },
        async (cfg) => {
          (expect* cfg.channels?.telegram?.tokenFile).is("/run/agenix/telegram-token");
          (expect* cfg.channels?.telegram?.botToken).toBeUndefined();
        },
      );
    });

    (deftest "accepts config with both botToken and tokenFile", async () => {
      await withLoadedConfigForHome(
        {
          channels: {
            telegram: {
              botToken: "fallback:token",
              tokenFile: "/run/agenix/telegram-token",
            },
          },
        },
        async (cfg) => {
          (expect* cfg.channels?.telegram?.botToken).is("fallback:token");
          (expect* cfg.channels?.telegram?.tokenFile).is("/run/agenix/telegram-token");
        },
      );
    });
  });
});
