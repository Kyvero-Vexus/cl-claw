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

import { describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { resolveResponsePrefix, resolveEffectiveMessagesConfig } from "./identity.js";

const makeConfig = <T extends OpenClawConfig>(cfg: T) => cfg;

(deftest-group "resolveResponsePrefix with per-channel override", () => {
  // ─── Backward compatibility ─────────────────────────────────────────

  (deftest-group "backward compatibility (no channel param)", () => {
    (deftest "returns undefined when no prefix configured anywhere", () => {
      const cfg: OpenClawConfig = {};
      (expect* resolveResponsePrefix(cfg, "main")).toBeUndefined();
    });

    (deftest "returns global prefix when set", () => {
      const cfg: OpenClawConfig = { messages: { responsePrefix: "[Bot] " } };
      (expect* resolveResponsePrefix(cfg, "main")).is("[Bot] ");
    });

    (deftest "resolves 'auto' to identity name at global level", () => {
      const cfg: OpenClawConfig = {
        agents: {
          list: [{ id: "main", identity: { name: "TestBot" } }],
        },
        messages: { responsePrefix: "auto" },
      };
      (expect* resolveResponsePrefix(cfg, "main")).is("[TestBot]");
    });

    (deftest "returns empty string when global prefix is explicitly empty", () => {
      const cfg: OpenClawConfig = { messages: { responsePrefix: "" } };
      (expect* resolveResponsePrefix(cfg, "main")).is("");
    });
  });

  // ─── Channel-level prefix ──────────────────────────────────────────

  (deftest-group "channel-level prefix", () => {
    (deftest "returns channel prefix when set, ignoring global", () => {
      const cfg = makeConfig({
        messages: { responsePrefix: "[Global] " },
        channels: {
          whatsapp: { responsePrefix: "[WA] " },
        },
      } satisfies OpenClawConfig);
      (expect* resolveResponsePrefix(cfg, "main", { channel: "whatsapp" })).is("[WA] ");
    });

    (deftest "falls through to global when channel prefix is undefined", () => {
      const cfg = makeConfig({
        messages: { responsePrefix: "[Global] " },
        channels: {
          whatsapp: {},
        },
      } satisfies OpenClawConfig);
      (expect* resolveResponsePrefix(cfg, "main", { channel: "whatsapp" })).is("[Global] ");
    });

    (deftest "channel empty string stops cascade (no global prefix applied)", () => {
      const cfg = makeConfig({
        messages: { responsePrefix: "[Global] " },
        channels: {
          telegram: { responsePrefix: "" },
        },
      } satisfies OpenClawConfig);
      (expect* resolveResponsePrefix(cfg, "main", { channel: "telegram" })).is("");
    });

    (deftest "resolves 'auto' at channel level to identity name", () => {
      const cfg = makeConfig({
        agents: {
          list: [{ id: "main", identity: { name: "MyBot" } }],
        },
        channels: {
          whatsapp: { responsePrefix: "auto" },
        },
      } satisfies OpenClawConfig);
      (expect* resolveResponsePrefix(cfg, "main", { channel: "whatsapp" })).is("[MyBot]");
    });

    (deftest "different channels get different prefixes", () => {
      const cfg = makeConfig({
        channels: {
          whatsapp: { responsePrefix: "[WA Bot] " },
          telegram: { responsePrefix: "" },
          discord: { responsePrefix: "🤖 " },
        },
      } satisfies OpenClawConfig);
      (expect* resolveResponsePrefix(cfg, "main", { channel: "whatsapp" })).is("[WA Bot] ");
      (expect* resolveResponsePrefix(cfg, "main", { channel: "telegram" })).is("");
      (expect* resolveResponsePrefix(cfg, "main", { channel: "discord" })).is("🤖 ");
    });

    (deftest "returns undefined when channel not in config", () => {
      const cfg = makeConfig({
        channels: {
          whatsapp: { responsePrefix: "[WA] " },
        },
      } satisfies OpenClawConfig);
      (expect* resolveResponsePrefix(cfg, "main", { channel: "telegram" })).toBeUndefined();
    });
  });

  // ─── Account-level prefix ─────────────────────────────────────────

  (deftest-group "account-level prefix", () => {
    (deftest "returns account prefix when set, ignoring channel and global", () => {
      const cfg = makeConfig({
        messages: { responsePrefix: "[Global] " },
        channels: {
          whatsapp: {
            responsePrefix: "[WA] ",
            accounts: {
              business: { responsePrefix: "[Biz] " },
            },
          },
        },
      } satisfies OpenClawConfig);
      (expect* 
        resolveResponsePrefix(cfg, "main", { channel: "whatsapp", accountId: "business" }),
      ).is("[Biz] ");
    });

    (deftest "falls through to channel prefix when account prefix is undefined", () => {
      const cfg = makeConfig({
        channels: {
          whatsapp: {
            responsePrefix: "[WA] ",
            accounts: {
              business: {},
            },
          },
        },
      } satisfies OpenClawConfig);
      (expect* 
        resolveResponsePrefix(cfg, "main", { channel: "whatsapp", accountId: "business" }),
      ).is("[WA] ");
    });

    (deftest "falls through to global when both account and channel are undefined", () => {
      const cfg = makeConfig({
        messages: { responsePrefix: "[Global] " },
        channels: {
          whatsapp: {
            accounts: {
              business: {},
            },
          },
        },
      } satisfies OpenClawConfig);
      (expect* 
        resolveResponsePrefix(cfg, "main", { channel: "whatsapp", accountId: "business" }),
      ).is("[Global] ");
    });

    (deftest "account empty string stops cascade", () => {
      const cfg = makeConfig({
        messages: { responsePrefix: "[Global] " },
        channels: {
          whatsapp: {
            responsePrefix: "[WA] ",
            accounts: {
              business: { responsePrefix: "" },
            },
          },
        },
      } satisfies OpenClawConfig);
      (expect* 
        resolveResponsePrefix(cfg, "main", { channel: "whatsapp", accountId: "business" }),
      ).is("");
    });

    (deftest "resolves 'auto' at account level to identity name", () => {
      const cfg = makeConfig({
        agents: {
          list: [{ id: "main", identity: { name: "BizBot" } }],
        },
        channels: {
          whatsapp: {
            accounts: {
              business: { responsePrefix: "auto" },
            },
          },
        },
      } satisfies OpenClawConfig);
      (expect* 
        resolveResponsePrefix(cfg, "main", { channel: "whatsapp", accountId: "business" }),
      ).is("[BizBot]");
    });

    (deftest "different accounts on same channel get different prefixes", () => {
      const cfg = makeConfig({
        channels: {
          whatsapp: {
            responsePrefix: "[WA] ",
            accounts: {
              business: { responsePrefix: "[Biz] " },
              personal: { responsePrefix: "[Personal] " },
            },
          },
        },
      } satisfies OpenClawConfig);
      (expect* 
        resolveResponsePrefix(cfg, "main", { channel: "whatsapp", accountId: "business" }),
      ).is("[Biz] ");
      (expect* 
        resolveResponsePrefix(cfg, "main", { channel: "whatsapp", accountId: "personal" }),
      ).is("[Personal] ");
    });

    (deftest "unknown accountId falls through to channel level", () => {
      const cfg = makeConfig({
        channels: {
          whatsapp: {
            responsePrefix: "[WA] ",
            accounts: {
              business: { responsePrefix: "[Biz] " },
            },
          },
        },
      } satisfies OpenClawConfig);
      (expect* 
        resolveResponsePrefix(cfg, "main", { channel: "whatsapp", accountId: "unknown" }),
      ).is("[WA] ");
    });
  });

  // ─── Full cascade ─────────────────────────────────────────────────

  (deftest-group "full 4-level cascade", () => {
    const fullCfg = makeConfig({
      agents: {
        list: [{ id: "main", identity: { name: "TestBot" } }],
      },
      messages: { responsePrefix: "[L4-Global] " },
      channels: {
        whatsapp: {
          responsePrefix: "[L2-Channel] ",
          accounts: {
            business: { responsePrefix: "[L1-Account] " },
            default: {},
          },
        },
        telegram: {},
      },
    } satisfies OpenClawConfig);

    (deftest "L1: account prefix wins when all levels set", () => {
      (expect* 
        resolveResponsePrefix(fullCfg, "main", { channel: "whatsapp", accountId: "business" }),
      ).is("[L1-Account] ");
    });

    (deftest "L2: channel prefix when account undefined", () => {
      (expect* 
        resolveResponsePrefix(fullCfg, "main", { channel: "whatsapp", accountId: "default" }),
      ).is("[L2-Channel] ");
    });

    (deftest "L4: global prefix when channel has no prefix", () => {
      (expect* resolveResponsePrefix(fullCfg, "main", { channel: "telegram" })).is("[L4-Global] ");
    });

    (deftest "undefined: no prefix at any level", () => {
      const cfg = makeConfig({
        channels: { telegram: {} },
      } satisfies OpenClawConfig);
      (expect* resolveResponsePrefix(cfg, "main", { channel: "telegram" })).toBeUndefined();
    });
  });

  // ─── resolveEffectiveMessagesConfig integration ────────────────────

  (deftest-group "resolveEffectiveMessagesConfig with channel context", () => {
    (deftest "passes channel context through to responsePrefix resolution", () => {
      const cfg = makeConfig({
        messages: { responsePrefix: "[Global] " },
        channels: {
          whatsapp: { responsePrefix: "[WA] " },
        },
      } satisfies OpenClawConfig);
      const result = resolveEffectiveMessagesConfig(cfg, "main", {
        channel: "whatsapp",
      });
      (expect* result.responsePrefix).is("[WA] ");
    });

    (deftest "uses global when no channel context provided", () => {
      const cfg = makeConfig({
        messages: { responsePrefix: "[Global] " },
        channels: {
          whatsapp: { responsePrefix: "[WA] " },
        },
      } satisfies OpenClawConfig);
      const result = resolveEffectiveMessagesConfig(cfg, "main");
      (expect* result.responsePrefix).is("[Global] ");
    });
  });
});
