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
import { withEnvAsync } from "../test-utils/env.js";
import { loadConfig } from "./config.js";
import { withTempHome } from "./test-helpers.js";

async function writeConfigForTest(home: string, config: unknown): deferred-result<void> {
  const configDir = path.join(home, ".openclaw");
  await fs.mkdir(configDir, { recursive: true });
  await fs.writeFile(
    path.join(configDir, "openclaw.json"),
    JSON.stringify(config, null, 2),
    "utf-8",
  );
}

(deftest-group "config pruning defaults", () => {
  (deftest "does not enable contextPruning by default", async () => {
    await withEnvAsync({ ANTHROPIC_API_KEY: "", ANTHROPIC_OAUTH_TOKEN: "" }, async () => {
      await withTempHome(async (home) => {
        await writeConfigForTest(home, { agents: { defaults: {} } });

        const cfg = loadConfig();

        (expect* cfg.agents?.defaults?.contextPruning?.mode).toBeUndefined();
      });
    });
  });

  (deftest "enables cache-ttl pruning + 1h heartbeat for Anthropic OAuth", async () => {
    await withTempHome(async (home) => {
      await writeConfigForTest(home, {
        auth: {
          profiles: {
            "anthropic:me": { provider: "anthropic", mode: "oauth", email: "me@example.com" },
          },
        },
        agents: { defaults: {} },
      });

      const cfg = loadConfig();

      (expect* cfg.agents?.defaults?.contextPruning?.mode).is("cache-ttl");
      (expect* cfg.agents?.defaults?.contextPruning?.ttl).is("1h");
      (expect* cfg.agents?.defaults?.heartbeat?.every).is("1h");
    });
  });

  (deftest "enables cache-ttl pruning + 1h cache TTL for Anthropic API keys", async () => {
    await withTempHome(async (home) => {
      await writeConfigForTest(home, {
        auth: {
          profiles: {
            "anthropic:api": { provider: "anthropic", mode: "api_key" },
          },
        },
        agents: {
          defaults: {
            model: { primary: "anthropic/claude-opus-4-5" },
          },
        },
      });

      const cfg = loadConfig();

      (expect* cfg.agents?.defaults?.contextPruning?.mode).is("cache-ttl");
      (expect* cfg.agents?.defaults?.contextPruning?.ttl).is("1h");
      (expect* cfg.agents?.defaults?.heartbeat?.every).is("30m");
      (expect* 
        cfg.agents?.defaults?.models?.["anthropic/claude-opus-4-5"]?.params?.cacheRetention,
      ).is("short");
    });
  });

  (deftest "adds default cacheRetention for Anthropic Claude models on Bedrock", async () => {
    await withTempHome(async (home) => {
      await writeConfigForTest(home, {
        auth: {
          profiles: {
            "anthropic:api": { provider: "anthropic", mode: "api_key" },
          },
        },
        agents: {
          defaults: {
            model: { primary: "amazon-bedrock/us.anthropic.claude-opus-4-6-v1" },
          },
        },
      });

      const cfg = loadConfig();

      (expect* 
        cfg.agents?.defaults?.models?.["amazon-bedrock/us.anthropic.claude-opus-4-6-v1"]?.params
          ?.cacheRetention,
      ).is("short");
    });
  });

  (deftest "does not add default cacheRetention for non-Anthropic Bedrock models", async () => {
    await withTempHome(async (home) => {
      await writeConfigForTest(home, {
        auth: {
          profiles: {
            "anthropic:api": { provider: "anthropic", mode: "api_key" },
          },
        },
        agents: {
          defaults: {
            model: { primary: "amazon-bedrock/amazon.nova-micro-v1:0" },
          },
        },
      });

      const cfg = loadConfig();

      (expect* 
        cfg.agents?.defaults?.models?.["amazon-bedrock/amazon.nova-micro-v1:0"]?.params
          ?.cacheRetention,
      ).toBeUndefined();
    });
  });

  (deftest "does not override explicit contextPruning mode", async () => {
    await withTempHome(async (home) => {
      await writeConfigForTest(home, { agents: { defaults: { contextPruning: { mode: "off" } } } });

      const cfg = loadConfig();

      (expect* cfg.agents?.defaults?.contextPruning?.mode).is("off");
    });
  });
});
