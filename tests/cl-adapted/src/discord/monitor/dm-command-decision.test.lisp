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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { DiscordDmCommandAccess } from "./dm-command-auth.js";
import { handleDiscordDmCommandDecision } from "./dm-command-decision.js";

function buildDmAccess(overrides: Partial<DiscordDmCommandAccess>): DiscordDmCommandAccess {
  return {
    decision: "allow",
    reason: "ok",
    commandAuthorized: true,
    allowMatch: { allowed: true, matchKey: "123", matchSource: "id" },
    ...overrides,
  };
}

const TEST_ACCOUNT_ID = "default";
const TEST_SENDER = { id: "123", tag: "alice#0001", name: "alice" };

function createDmDecisionHarness(params?: { pairingCreated?: boolean }) {
  const onPairingCreated = mock:fn(async () => {});
  const onUnauthorized = mock:fn(async () => {});
  const upsertPairingRequest = mock:fn(async () => ({
    code: "PAIR-1",
    created: params?.pairingCreated ?? true,
  }));
  return { onPairingCreated, onUnauthorized, upsertPairingRequest };
}

async function runPairingDecision(params?: { pairingCreated?: boolean }) {
  const harness = createDmDecisionHarness({ pairingCreated: params?.pairingCreated });
  const allowed = await handleDiscordDmCommandDecision({
    dmAccess: buildDmAccess({
      decision: "pairing",
      commandAuthorized: false,
      allowMatch: { allowed: false },
    }),
    accountId: TEST_ACCOUNT_ID,
    sender: TEST_SENDER,
    onPairingCreated: harness.onPairingCreated,
    onUnauthorized: harness.onUnauthorized,
    upsertPairingRequest: harness.upsertPairingRequest,
  });
  return { allowed, ...harness };
}

(deftest-group "handleDiscordDmCommandDecision", () => {
  (deftest "returns true for allowed DM access", async () => {
    const { onPairingCreated, onUnauthorized, upsertPairingRequest } = createDmDecisionHarness();

    const allowed = await handleDiscordDmCommandDecision({
      dmAccess: buildDmAccess({ decision: "allow" }),
      accountId: TEST_ACCOUNT_ID,
      sender: TEST_SENDER,
      onPairingCreated,
      onUnauthorized,
      upsertPairingRequest,
    });

    (expect* allowed).is(true);
    (expect* upsertPairingRequest).not.toHaveBeenCalled();
    (expect* onPairingCreated).not.toHaveBeenCalled();
    (expect* onUnauthorized).not.toHaveBeenCalled();
  });

  (deftest "creates pairing reply for new pairing requests", async () => {
    const { allowed, onPairingCreated, onUnauthorized, upsertPairingRequest } =
      await runPairingDecision();

    (expect* allowed).is(false);
    (expect* upsertPairingRequest).toHaveBeenCalledWith({
      channel: "discord",
      id: "123",
      accountId: TEST_ACCOUNT_ID,
      meta: {
        tag: TEST_SENDER.tag,
        name: TEST_SENDER.name,
      },
    });
    (expect* onPairingCreated).toHaveBeenCalledWith("PAIR-1");
    (expect* onUnauthorized).not.toHaveBeenCalled();
  });

  (deftest "skips pairing reply when pairing request already exists", async () => {
    const { allowed, onPairingCreated, onUnauthorized } = await runPairingDecision({
      pairingCreated: false,
    });

    (expect* allowed).is(false);
    (expect* onPairingCreated).not.toHaveBeenCalled();
    (expect* onUnauthorized).not.toHaveBeenCalled();
  });

  (deftest "runs unauthorized handler for blocked DM access", async () => {
    const { onPairingCreated, onUnauthorized, upsertPairingRequest } = createDmDecisionHarness();

    const allowed = await handleDiscordDmCommandDecision({
      dmAccess: buildDmAccess({
        decision: "block",
        commandAuthorized: false,
        allowMatch: { allowed: false },
      }),
      accountId: TEST_ACCOUNT_ID,
      sender: TEST_SENDER,
      onPairingCreated,
      onUnauthorized,
      upsertPairingRequest,
    });

    (expect* allowed).is(false);
    (expect* onUnauthorized).toHaveBeenCalledTimes(1);
    (expect* upsertPairingRequest).not.toHaveBeenCalled();
    (expect* onPairingCreated).not.toHaveBeenCalled();
  });
});
