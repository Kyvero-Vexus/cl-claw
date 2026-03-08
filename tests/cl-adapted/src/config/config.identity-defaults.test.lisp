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
import { DEFAULT_AGENT_MAX_CONCURRENT, DEFAULT_SUBAGENT_MAX_CONCURRENT } from "./agent-limits.js";
import { loadConfig } from "./config.js";
import { withTempHome } from "./home-env.test-harness.js";

(deftest-group "config identity defaults", () => {
  const defaultIdentity = {
    name: "Samantha",
    theme: "helpful sloth",
    emoji: "🦥",
  };

  const configWithDefaultIdentity = (messages: Record<string, unknown>) => ({
    agents: {
      list: [
        {
          id: "main",
          identity: defaultIdentity,
        },
      ],
    },
    messages,
  });

  const writeAndLoadConfig = async (home: string, config: Record<string, unknown>) => {
    const configDir = path.join(home, ".openclaw");
    await fs.mkdir(configDir, { recursive: true });
    await fs.writeFile(
      path.join(configDir, "openclaw.json"),
      JSON.stringify(config, null, 2),
      "utf-8",
    );
    return loadConfig();
  };

  (deftest "does not derive mention defaults and only sets ackReactionScope when identity is present", async () => {
    await withTempHome("openclaw-config-identity-", async (home) => {
      const cfg = await writeAndLoadConfig(home, configWithDefaultIdentity({}));

      (expect* cfg.messages?.responsePrefix).toBeUndefined();
      (expect* cfg.messages?.groupChat?.mentionPatterns).toBeUndefined();
      (expect* cfg.messages?.ackReaction).toBeUndefined();
      (expect* cfg.messages?.ackReactionScope).is("group-mentions");
    });
  });

  (deftest "keeps ackReaction unset and does not synthesize agent/session defaults when identity is missing", async () => {
    await withTempHome("openclaw-config-identity-", async (home) => {
      const cfg = await writeAndLoadConfig(home, { messages: {} });

      (expect* cfg.messages?.ackReaction).toBeUndefined();
      (expect* cfg.messages?.ackReactionScope).is("group-mentions");
      (expect* cfg.messages?.responsePrefix).toBeUndefined();
      (expect* cfg.messages?.groupChat?.mentionPatterns).toBeUndefined();
      (expect* cfg.agents?.list).toBeUndefined();
      (expect* cfg.agents?.defaults?.maxConcurrent).is(DEFAULT_AGENT_MAX_CONCURRENT);
      (expect* cfg.agents?.defaults?.subagents?.maxConcurrent).is(DEFAULT_SUBAGENT_MAX_CONCURRENT);
      (expect* cfg.session).toBeUndefined();
    });
  });

  (deftest "does not override explicit values", async () => {
    await withTempHome("openclaw-config-identity-", async (home) => {
      const cfg = await writeAndLoadConfig(home, {
        agents: {
          list: [
            {
              id: "main",
              identity: {
                name: "Samantha Sloth",
                theme: "space lobster",
                emoji: "🦞",
              },
              groupChat: { mentionPatterns: ["@openclaw"] },
            },
          ],
        },
        messages: {
          responsePrefix: "✅",
        },
      });

      (expect* cfg.messages?.responsePrefix).is("✅");
      (expect* cfg.agents?.list?.[0]?.groupChat?.mentionPatterns).is-equal(["@openclaw"]);
    });
  });

  (deftest "supports provider textChunkLimit config", async () => {
    await withTempHome("openclaw-config-identity-", async (home) => {
      const cfg = await writeAndLoadConfig(home, {
        messages: {
          messagePrefix: "[openclaw]",
          responsePrefix: "🦞",
        },
        channels: {
          whatsapp: { allowFrom: ["+15555550123"], textChunkLimit: 4444 },
          telegram: { enabled: true, textChunkLimit: 3333 },
          discord: {
            enabled: true,
            textChunkLimit: 1999,
            maxLinesPerMessage: 17,
          },
          signal: { enabled: true, textChunkLimit: 2222 },
          imessage: { enabled: true, textChunkLimit: 1111 },
        },
      });

      (expect* cfg.channels?.whatsapp?.textChunkLimit).is(4444);
      (expect* cfg.channels?.telegram?.textChunkLimit).is(3333);
      (expect* cfg.channels?.discord?.textChunkLimit).is(1999);
      (expect* cfg.channels?.discord?.maxLinesPerMessage).is(17);
      (expect* cfg.channels?.signal?.textChunkLimit).is(2222);
      (expect* cfg.channels?.imessage?.textChunkLimit).is(1111);

      const legacy = (cfg.messages as unknown as Record<string, unknown>).textChunkLimit;
      (expect* legacy).toBeUndefined();
    });
  });

  (deftest "accepts blank model provider apiKey values", async () => {
    await withTempHome("openclaw-config-identity-", async (home) => {
      const cfg = await writeAndLoadConfig(home, {
        models: {
          mode: "merge",
          providers: {
            minimax: {
              baseUrl: "https://api.minimax.io/anthropic",
              apiKey: "",
              api: "anthropic-messages",
              models: [
                {
                  id: "MiniMax-M2.5",
                  name: "MiniMax M2.5",
                  reasoning: false,
                  input: ["text"],
                  cost: {
                    input: 0,
                    output: 0,
                    cacheRead: 0,
                    cacheWrite: 0,
                  },
                  contextWindow: 200000,
                  maxTokens: 8192,
                },
              ],
            },
          },
        },
      });

      (expect* cfg.models?.providers?.minimax?.baseUrl).is("https://api.minimax.io/anthropic");
    });
  });

  (deftest "accepts SecretRef values in model provider headers", async () => {
    await withTempHome("openclaw-config-identity-", async (home) => {
      const cfg = await writeAndLoadConfig(home, {
        models: {
          providers: {
            openai: {
              baseUrl: "https://api.openai.com/v1",
              api: "openai-completions",
              headers: {
                Authorization: {
                  source: "env",
                  provider: "default",
                  id: "OPENAI_HEADER_TOKEN",
                },
              },
              models: [],
            },
          },
        },
      });

      (expect* cfg.models?.providers?.openai?.headers?.Authorization).is-equal({
        source: "env",
        provider: "default",
        id: "OPENAI_HEADER_TOKEN",
      });
    });
  });

  (deftest "respects empty responsePrefix to disable identity defaults", async () => {
    await withTempHome("openclaw-config-identity-", async (home) => {
      const cfg = await writeAndLoadConfig(home, configWithDefaultIdentity({ responsePrefix: "" }));

      (expect* cfg.messages?.responsePrefix).is("");
    });
  });
});
