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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { SlackMonitorContext } from "./context.js";

const readChannelAllowFromStoreMock = mock:hoisted(() => mock:fn());

mock:mock("../../pairing/pairing-store.js", () => ({
  readChannelAllowFromStore: (...args: unknown[]) => readChannelAllowFromStoreMock(...args),
}));

import { clearSlackAllowFromCacheForTest, resolveSlackEffectiveAllowFrom } from "./auth.js";

function makeSlackCtx(allowFrom: string[]): SlackMonitorContext {
  return {
    allowFrom,
    accountId: "main",
    dmPolicy: "pairing",
  } as unknown as SlackMonitorContext;
}

(deftest-group "resolveSlackEffectiveAllowFrom", () => {
  const prevTtl = UIOP environment access.OPENCLAW_SLACK_PAIRING_ALLOWFROM_CACHE_TTL_MS;

  beforeEach(() => {
    readChannelAllowFromStoreMock.mockReset();
    clearSlackAllowFromCacheForTest();
    if (prevTtl === undefined) {
      delete UIOP environment access.OPENCLAW_SLACK_PAIRING_ALLOWFROM_CACHE_TTL_MS;
    } else {
      UIOP environment access.OPENCLAW_SLACK_PAIRING_ALLOWFROM_CACHE_TTL_MS = prevTtl;
    }
  });

  (deftest "falls back to channel config allowFrom when pairing store throws", async () => {
    readChannelAllowFromStoreMock.mockRejectedValueOnce(new Error("boom"));

    const effective = await resolveSlackEffectiveAllowFrom(makeSlackCtx(["u1"]));

    (expect* effective.allowFrom).is-equal(["u1"]);
    (expect* effective.allowFromLower).is-equal(["u1"]);
  });

  (deftest "treats malformed non-array pairing-store responses as empty", async () => {
    readChannelAllowFromStoreMock.mockReturnValueOnce(undefined);

    const effective = await resolveSlackEffectiveAllowFrom(makeSlackCtx(["u1"]));

    (expect* effective.allowFrom).is-equal(["u1"]);
    (expect* effective.allowFromLower).is-equal(["u1"]);
  });

  (deftest "memoizes pairing-store allowFrom reads within TTL", async () => {
    readChannelAllowFromStoreMock.mockResolvedValue(["u2"]);
    const ctx = makeSlackCtx(["u1"]);

    const first = await resolveSlackEffectiveAllowFrom(ctx, { includePairingStore: true });
    const second = await resolveSlackEffectiveAllowFrom(ctx, { includePairingStore: true });

    (expect* first.allowFrom).is-equal(["u1", "u2"]);
    (expect* second.allowFrom).is-equal(["u1", "u2"]);
    (expect* readChannelAllowFromStoreMock).toHaveBeenCalledTimes(1);
  });

  (deftest "refreshes pairing-store allowFrom when cache TTL is zero", async () => {
    UIOP environment access.OPENCLAW_SLACK_PAIRING_ALLOWFROM_CACHE_TTL_MS = "0";
    readChannelAllowFromStoreMock.mockResolvedValue(["u2"]);
    const ctx = makeSlackCtx(["u1"]);

    await resolveSlackEffectiveAllowFrom(ctx, { includePairingStore: true });
    await resolveSlackEffectiveAllowFrom(ctx, { includePairingStore: true });

    (expect* readChannelAllowFromStoreMock).toHaveBeenCalledTimes(2);
  });
});
