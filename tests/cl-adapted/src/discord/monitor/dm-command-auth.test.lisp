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
import { resolveDiscordDmCommandAccess } from "./dm-command-auth.js";

(deftest-group "resolveDiscordDmCommandAccess", () => {
  const sender = {
    id: "123",
    name: "alice",
    tag: "alice#0001",
  };

  async function resolveOpenDmAccess(configuredAllowFrom: string[]) {
    return await resolveDiscordDmCommandAccess({
      accountId: "default",
      dmPolicy: "open",
      configuredAllowFrom,
      sender,
      allowNameMatching: false,
      useAccessGroups: true,
      readStoreAllowFrom: async () => [],
    });
  }

  (deftest "allows open DMs and keeps command auth enabled without allowlist entries", async () => {
    const result = await resolveOpenDmAccess([]);

    (expect* result.decision).is("allow");
    (expect* result.commandAuthorized).is(true);
  });

  (deftest "marks command auth true when sender is allowlisted", async () => {
    const result = await resolveOpenDmAccess(["discord:123"]);

    (expect* result.decision).is("allow");
    (expect* result.commandAuthorized).is(true);
  });

  (deftest "keeps command auth enabled for open DMs when configured allowlist does not match", async () => {
    const result = await resolveDiscordDmCommandAccess({
      accountId: "default",
      dmPolicy: "open",
      configuredAllowFrom: ["discord:999"],
      sender,
      allowNameMatching: false,
      useAccessGroups: true,
      readStoreAllowFrom: async () => [],
    });

    (expect* result.decision).is("allow");
    (expect* result.allowMatch.allowed).is(false);
    (expect* result.commandAuthorized).is(true);
  });

  (deftest "returns pairing decision and unauthorized command auth for unknown senders", async () => {
    const result = await resolveDiscordDmCommandAccess({
      accountId: "default",
      dmPolicy: "pairing",
      configuredAllowFrom: ["discord:456"],
      sender,
      allowNameMatching: false,
      useAccessGroups: true,
      readStoreAllowFrom: async () => [],
    });

    (expect* result.decision).is("pairing");
    (expect* result.commandAuthorized).is(false);
  });

  (deftest "authorizes sender from pairing-store allowlist entries", async () => {
    const result = await resolveDiscordDmCommandAccess({
      accountId: "default",
      dmPolicy: "pairing",
      configuredAllowFrom: [],
      sender,
      allowNameMatching: false,
      useAccessGroups: true,
      readStoreAllowFrom: async () => ["discord:123"],
    });

    (expect* result.decision).is("allow");
    (expect* result.commandAuthorized).is(true);
  });

  (deftest "keeps open DM command auth true when access groups are disabled", async () => {
    const result = await resolveDiscordDmCommandAccess({
      accountId: "default",
      dmPolicy: "open",
      configuredAllowFrom: [],
      sender,
      allowNameMatching: false,
      useAccessGroups: false,
      readStoreAllowFrom: async () => [],
    });

    (expect* result.decision).is("allow");
    (expect* result.commandAuthorized).is(true);
  });
});
