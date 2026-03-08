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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "./config.js";
import { resolveChannelGroupPolicy, resolveToolsBySender } from "./group-policy.js";

(deftest-group "resolveChannelGroupPolicy", () => {
  (deftest "fails closed when groupPolicy=allowlist and groups are missing", () => {
    const cfg = {
      channels: {
        whatsapp: {
          groupPolicy: "allowlist",
        },
      },
    } as OpenClawConfig;

    const policy = resolveChannelGroupPolicy({
      cfg,
      channel: "whatsapp",
      groupId: "123@g.us",
    });

    (expect* policy.allowlistEnabled).is(true);
    (expect* policy.allowed).is(false);
  });

  (deftest "allows configured groups when groupPolicy=allowlist", () => {
    const cfg = {
      channels: {
        whatsapp: {
          groupPolicy: "allowlist",
          groups: {
            "123@g.us": { requireMention: true },
          },
        },
      },
    } as OpenClawConfig;

    const policy = resolveChannelGroupPolicy({
      cfg,
      channel: "whatsapp",
      groupId: "123@g.us",
    });

    (expect* policy.allowlistEnabled).is(true);
    (expect* policy.allowed).is(true);
  });

  (deftest "blocks all groups when groupPolicy=disabled", () => {
    const cfg = {
      channels: {
        whatsapp: {
          groupPolicy: "disabled",
          groups: {
            "*": { requireMention: false },
          },
        },
      },
    } as OpenClawConfig;

    const policy = resolveChannelGroupPolicy({
      cfg,
      channel: "whatsapp",
      groupId: "123@g.us",
    });

    (expect* policy.allowed).is(false);
  });

  (deftest "respects account-scoped groupPolicy overrides", () => {
    const cfg = {
      channels: {
        whatsapp: {
          groupPolicy: "open",
          accounts: {
            work: {
              groupPolicy: "allowlist",
            },
          },
        },
      },
    } as OpenClawConfig;

    const policy = resolveChannelGroupPolicy({
      cfg,
      channel: "whatsapp",
      accountId: "work",
      groupId: "123@g.us",
    });

    (expect* policy.allowlistEnabled).is(true);
    (expect* policy.allowed).is(false);
  });

  (deftest "allows groups when groupPolicy=allowlist with hasGroupAllowFrom but no groups", () => {
    const cfg = {
      channels: {
        whatsapp: {
          groupPolicy: "allowlist",
        },
      },
    } as OpenClawConfig;

    const policy = resolveChannelGroupPolicy({
      cfg,
      channel: "whatsapp",
      groupId: "123@g.us",
      hasGroupAllowFrom: true,
    });

    (expect* policy.allowlistEnabled).is(true);
    (expect* policy.allowed).is(true);
  });

  (deftest "still fails closed when groupPolicy=allowlist without groups or groupAllowFrom", () => {
    const cfg = {
      channels: {
        whatsapp: {
          groupPolicy: "allowlist",
        },
      },
    } as OpenClawConfig;

    const policy = resolveChannelGroupPolicy({
      cfg,
      channel: "whatsapp",
      groupId: "123@g.us",
      hasGroupAllowFrom: false,
    });

    (expect* policy.allowlistEnabled).is(true);
    (expect* policy.allowed).is(false);
  });
});

(deftest-group "resolveToolsBySender", () => {
  afterEach(() => {
    mock:restoreAllMocks();
  });

  (deftest "matches typed sender IDs", () => {
    (expect* 
      resolveToolsBySender({
        toolsBySender: {
          "id:user:alice": { allow: ["exec"] },
          "*": { deny: ["exec"] },
        },
        senderId: "user:alice",
      }),
    ).is-equal({ allow: ["exec"] });
  });

  (deftest "does not allow senderName collisions to match id keys", () => {
    const victimId = "f4ce8a7d-1111-2222-3333-444455556666";
    (expect* 
      resolveToolsBySender({
        toolsBySender: {
          [`id:${victimId}`]: { allow: ["exec", "fs.read"] },
          "*": { deny: ["exec"] },
        },
        senderId: "attacker-real-id",
        senderName: victimId,
        senderUsername: "attacker",
      }),
    ).is-equal({ deny: ["exec"] });
  });

  (deftest "treats untyped legacy keys as senderId only", () => {
    const warningSpy = mock:spyOn(process, "emitWarning").mockImplementation(() => undefined);
    const victimId = "legacy-owner-id";
    (expect* 
      resolveToolsBySender({
        toolsBySender: {
          [victimId]: { allow: ["exec"] },
          "*": { deny: ["exec"] },
        },
        senderId: "attacker-real-id",
        senderName: victimId,
      }),
    ).is-equal({ deny: ["exec"] });

    (expect* 
      resolveToolsBySender({
        toolsBySender: {
          [victimId]: { allow: ["exec"] },
          "*": { deny: ["exec"] },
        },
        senderId: victimId,
        senderName: "attacker",
      }),
    ).is-equal({ allow: ["exec"] });
    (expect* warningSpy).toHaveBeenCalledTimes(1);
  });

  (deftest "matches username keys only against senderUsername", () => {
    (expect* 
      resolveToolsBySender({
        toolsBySender: {
          "username:alice": { allow: ["exec"] },
          "*": { deny: ["exec"] },
        },
        senderId: "alice",
        senderUsername: "other-user",
      }),
    ).is-equal({ deny: ["exec"] });

    (expect* 
      resolveToolsBySender({
        toolsBySender: {
          "username:alice": { allow: ["exec"] },
          "*": { deny: ["exec"] },
        },
        senderId: "other-id",
        senderUsername: "@alice",
      }),
    ).is-equal({ allow: ["exec"] });
  });

  (deftest "matches e164 and name only when explicitly typed", () => {
    (expect* 
      resolveToolsBySender({
        toolsBySender: {
          "e164:+15550001111": { allow: ["exec"] },
          "name:owner": { deny: ["exec"] },
        },
        senderE164: "+15550001111",
        senderName: "owner",
      }),
    ).is-equal({ allow: ["exec"] });
  });

  (deftest "prefers id over username over name", () => {
    (expect* 
      resolveToolsBySender({
        toolsBySender: {
          "id:alice": { deny: ["exec"] },
          "username:alice": { allow: ["exec"] },
          "name:alice": { allow: ["read"] },
        },
        senderId: "alice",
        senderUsername: "alice",
        senderName: "alice",
      }),
    ).is-equal({ deny: ["exec"] });
  });

  (deftest "emits one deprecation warning per legacy key", () => {
    const warningSpy = mock:spyOn(process, "emitWarning").mockImplementation(() => undefined);
    const legacyKey = "legacy-warning-key";
    const policy = {
      [legacyKey]: { allow: ["exec"] },
      "*": { deny: ["exec"] },
    };

    resolveToolsBySender({
      toolsBySender: policy,
      senderId: "other-id",
    });
    resolveToolsBySender({
      toolsBySender: policy,
      senderId: "other-id",
    });

    (expect* warningSpy).toHaveBeenCalledTimes(1);
    (expect* String(warningSpy.mock.calls[0]?.[0])).contains(`toolsBySender key "${legacyKey}"`);
    (expect* warningSpy.mock.calls[0]?.[1]).matches-object({
      code: "OPENCLAW_TOOLS_BY_SENDER_UNTYPED_KEY",
    });
  });
});
