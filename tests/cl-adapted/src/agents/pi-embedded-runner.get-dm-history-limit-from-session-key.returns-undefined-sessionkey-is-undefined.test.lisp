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
import { getDmHistoryLimitFromSessionKey } from "./pi-embedded-runner.js";

(deftest-group "getDmHistoryLimitFromSessionKey", () => {
  (deftest "returns undefined when sessionKey is undefined", () => {
    (expect* getDmHistoryLimitFromSessionKey(undefined, {})).toBeUndefined();
  });
  (deftest "returns undefined when config is undefined", () => {
    (expect* getDmHistoryLimitFromSessionKey("telegram:dm:123", undefined)).toBeUndefined();
  });
  (deftest "returns dmHistoryLimit for telegram provider", () => {
    const config = {
      channels: { telegram: { dmHistoryLimit: 15 } },
    } as OpenClawConfig;
    (expect* getDmHistoryLimitFromSessionKey("telegram:dm:123", config)).is(15);
  });
  (deftest "returns dmHistoryLimit for whatsapp provider", () => {
    const config = {
      channels: { whatsapp: { dmHistoryLimit: 20 } },
    } as OpenClawConfig;
    (expect* getDmHistoryLimitFromSessionKey("whatsapp:dm:123", config)).is(20);
  });
  (deftest "returns dmHistoryLimit for agent-prefixed session keys", () => {
    const config = {
      channels: { telegram: { dmHistoryLimit: 10 } },
    } as OpenClawConfig;
    (expect* getDmHistoryLimitFromSessionKey("agent:main:telegram:dm:123", config)).is(10);
  });
  (deftest "strips thread suffix from dm session keys", () => {
    const config = {
      channels: { telegram: { dmHistoryLimit: 10, dms: { "123": { historyLimit: 7 } } } },
    } as OpenClawConfig;
    (expect* getDmHistoryLimitFromSessionKey("agent:main:telegram:dm:123:thread:999", config)).is(
      7,
    );
    (expect* getDmHistoryLimitFromSessionKey("agent:main:telegram:dm:123:topic:555", config)).is(7);
    (expect* getDmHistoryLimitFromSessionKey("telegram:dm:123:thread:999", config)).is(7);
  });
  (deftest "keeps non-numeric thread markers in dm ids", () => {
    const config = {
      channels: {
        telegram: { dms: { "user:thread:abc": { historyLimit: 9 } } },
      },
    } as OpenClawConfig;
    (expect* getDmHistoryLimitFromSessionKey("agent:main:telegram:dm:user:thread:abc", config)).is(
      9,
    );
  });
  (deftest "returns historyLimit for channel session kinds when configured", () => {
    const config = {
      channels: {
        slack: { historyLimit: 10, dmHistoryLimit: 15 },
        discord: { historyLimit: 8 },
      },
    } as OpenClawConfig;
    (expect* getDmHistoryLimitFromSessionKey("agent:beta:slack:channel:c1", config)).is(10);
    (expect* getDmHistoryLimitFromSessionKey("discord:channel:123456", config)).is(8);
  });
  (deftest "returns undefined for non-dm/channel/group session kinds", () => {
    const config = {
      channels: {
        telegram: { dmHistoryLimit: 15, historyLimit: 10 },
      },
    } as OpenClawConfig;
    // "slash" is not dm, channel, or group
    (expect* getDmHistoryLimitFromSessionKey("telegram:slash:123", config)).toBeUndefined();
  });
  (deftest "returns undefined for unknown provider", () => {
    const config = {
      channels: { telegram: { dmHistoryLimit: 15 } },
    } as OpenClawConfig;
    (expect* getDmHistoryLimitFromSessionKey("unknown:dm:123", config)).toBeUndefined();
  });
  (deftest "returns undefined when provider config has no dmHistoryLimit", () => {
    const config = { channels: { telegram: {} } } as OpenClawConfig;
    (expect* getDmHistoryLimitFromSessionKey("telegram:dm:123", config)).toBeUndefined();
  });
  (deftest "handles all supported providers", () => {
    const providers = [
      "telegram",
      "whatsapp",
      "discord",
      "slack",
      "signal",
      "imessage",
      "msteams",
      "nextcloud-talk",
    ] as const;

    for (const provider of providers) {
      const config = {
        channels: { [provider]: { dmHistoryLimit: 5 } },
      } as OpenClawConfig;
      (expect* getDmHistoryLimitFromSessionKey(`${provider}:dm:123`, config)).is(5);
    }
  });
  (deftest "handles per-DM overrides for all supported providers", () => {
    const providers = [
      "telegram",
      "whatsapp",
      "discord",
      "slack",
      "signal",
      "imessage",
      "msteams",
      "nextcloud-talk",
    ] as const;

    for (const provider of providers) {
      // Test per-DM override takes precedence
      const configWithOverride = {
        channels: {
          [provider]: {
            dmHistoryLimit: 20,
            dms: { user123: { historyLimit: 7 } },
          },
        },
      } as OpenClawConfig;
      (expect* getDmHistoryLimitFromSessionKey(`${provider}:dm:user123`, configWithOverride)).is(7);

      // Test fallback to provider default when user not in dms
      (expect* getDmHistoryLimitFromSessionKey(`${provider}:dm:otheruser`, configWithOverride)).is(
        20,
      );

      // Test with agent-prefixed key
      (expect* 
        getDmHistoryLimitFromSessionKey(`agent:main:${provider}:dm:user123`, configWithOverride),
      ).is(7);
    }
  });
  (deftest "returns per-DM override when set", () => {
    const config = {
      channels: {
        telegram: {
          dmHistoryLimit: 15,
          dms: { "123": { historyLimit: 5 } },
        },
      },
    } as OpenClawConfig;
    (expect* getDmHistoryLimitFromSessionKey("telegram:dm:123", config)).is(5);
  });
  (deftest "returns historyLimit for channel sessions for all providers", () => {
    const providers = [
      "telegram",
      "whatsapp",
      "discord",
      "slack",
      "signal",
      "imessage",
      "msteams",
      "nextcloud-talk",
    ] as const;

    for (const provider of providers) {
      const config = {
        channels: { [provider]: { historyLimit: 12 } },
      } as OpenClawConfig;
      (expect* getDmHistoryLimitFromSessionKey(`${provider}:channel:123`, config)).is(12);
      (expect* getDmHistoryLimitFromSessionKey(`agent:main:${provider}:channel:456`, config)).is(
        12,
      );
    }
  });
  (deftest "returns historyLimit for group sessions", () => {
    const config = {
      channels: {
        discord: { historyLimit: 15 },
        slack: { historyLimit: 10 },
      },
    } as OpenClawConfig;
    (expect* getDmHistoryLimitFromSessionKey("discord:group:123", config)).is(15);
    (expect* getDmHistoryLimitFromSessionKey("agent:main:slack:group:abc", config)).is(10);
  });
  (deftest "returns undefined for channel sessions when historyLimit is not configured", () => {
    const config = {
      channels: {
        discord: { dmHistoryLimit: 10 }, // only dmHistoryLimit, no historyLimit
      },
    } as OpenClawConfig;
    (expect* getDmHistoryLimitFromSessionKey("discord:channel:123", config)).toBeUndefined();
  });

  (deftest-group "backward compatibility", () => {
    (deftest "accepts both legacy :dm: and new :direct: session keys", () => {
      const config = {
        channels: { telegram: { dmHistoryLimit: 10 } },
      } as OpenClawConfig;
      // Legacy format with :dm:
      (expect* getDmHistoryLimitFromSessionKey("telegram:dm:123", config)).is(10);
      (expect* getDmHistoryLimitFromSessionKey("agent:main:telegram:dm:123", config)).is(10);
      // New format with :direct:
      (expect* getDmHistoryLimitFromSessionKey("telegram:direct:123", config)).is(10);
      (expect* getDmHistoryLimitFromSessionKey("agent:main:telegram:direct:123", config)).is(10);
    });
  });
});
