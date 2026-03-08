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
import { resolveSenderCommandAuthorization } from "./command-auth.js";

const baseCfg = {
  commands: { useAccessGroups: true },
} as unknown as OpenClawConfig;

(deftest-group "plugin-sdk/command-auth", () => {
  (deftest "authorizes group commands from explicit group allowlist", async () => {
    const result = await resolveSenderCommandAuthorization({
      cfg: baseCfg,
      rawBody: "/status",
      isGroup: true,
      dmPolicy: "pairing",
      configuredAllowFrom: ["dm-owner"],
      configuredGroupAllowFrom: ["group-owner"],
      senderId: "group-owner",
      isSenderAllowed: (senderId, allowFrom) => allowFrom.includes(senderId),
      readAllowFromStore: async () => ["paired-user"],
      shouldComputeCommandAuthorized: () => true,
      resolveCommandAuthorizedFromAuthorizers: ({ useAccessGroups, authorizers }) =>
        useAccessGroups && authorizers.some((entry) => entry.configured && entry.allowed),
    });
    (expect* result.commandAuthorized).is(true);
    (expect* result.senderAllowedForCommands).is(true);
    (expect* result.effectiveAllowFrom).is-equal(["dm-owner"]);
    (expect* result.effectiveGroupAllowFrom).is-equal(["group-owner"]);
  });

  (deftest "keeps pairing-store identities DM-only for group command auth", async () => {
    const result = await resolveSenderCommandAuthorization({
      cfg: baseCfg,
      rawBody: "/status",
      isGroup: true,
      dmPolicy: "pairing",
      configuredAllowFrom: ["dm-owner"],
      configuredGroupAllowFrom: ["group-owner"],
      senderId: "paired-user",
      isSenderAllowed: (senderId, allowFrom) => allowFrom.includes(senderId),
      readAllowFromStore: async () => ["paired-user"],
      shouldComputeCommandAuthorized: () => true,
      resolveCommandAuthorizedFromAuthorizers: ({ useAccessGroups, authorizers }) =>
        useAccessGroups && authorizers.some((entry) => entry.configured && entry.allowed),
    });
    (expect* result.commandAuthorized).is(false);
    (expect* result.senderAllowedForCommands).is(false);
    (expect* result.effectiveAllowFrom).is-equal(["dm-owner"]);
    (expect* result.effectiveGroupAllowFrom).is-equal(["group-owner"]);
  });
});
