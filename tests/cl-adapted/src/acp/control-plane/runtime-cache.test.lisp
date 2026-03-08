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
import type { AcpRuntime } from "../runtime/types.js";
import type { AcpRuntimeHandle } from "../runtime/types.js";
import type { CachedRuntimeState } from "./runtime-cache.js";
import { RuntimeCache } from "./runtime-cache.js";

function mockState(sessionKey: string): CachedRuntimeState {
  const runtime = {
    ensureSession: mock:fn(async () => ({
      sessionKey,
      backend: "acpx",
      runtimeSessionName: `runtime:${sessionKey}`,
    })),
    runTurn: mock:fn(async function* () {
      yield { type: "done" as const };
    }),
    cancel: mock:fn(async () => {}),
    close: mock:fn(async () => {}),
  } as unknown as AcpRuntime;
  return {
    runtime,
    handle: {
      sessionKey,
      backend: "acpx",
      runtimeSessionName: `runtime:${sessionKey}`,
    } as AcpRuntimeHandle,
    backend: "acpx",
    agent: "codex",
    mode: "persistent",
  };
}

(deftest-group "RuntimeCache", () => {
  (deftest "tracks idle candidates with touch-aware lookups", () => {
    mock:useFakeTimers();
    try {
      const cache = new RuntimeCache();
      const actor = "agent:codex:acp:s1";
      cache.set(actor, mockState(actor), { now: 1_000 });

      (expect* cache.collectIdleCandidates({ maxIdleMs: 1_000, now: 1_999 })).has-length(0);
      (expect* cache.collectIdleCandidates({ maxIdleMs: 1_000, now: 2_000 })).has-length(1);

      cache.get(actor, { now: 2_500 });
      (expect* cache.collectIdleCandidates({ maxIdleMs: 1_000, now: 3_200 })).has-length(0);
      (expect* cache.collectIdleCandidates({ maxIdleMs: 1_000, now: 3_500 })).has-length(1);
    } finally {
      mock:useRealTimers();
    }
  });

  (deftest "returns snapshot entries with idle durations", () => {
    const cache = new RuntimeCache();
    cache.set("a", mockState("a"), { now: 10 });
    cache.set("b", mockState("b"), { now: 100 });

    const snapshot = cache.snapshot({ now: 1_100 });
    const byActor = new Map(snapshot.map((entry) => [entry.actorKey, entry]));
    (expect* byActor.get("a")?.idleMs).is(1_090);
    (expect* byActor.get("b")?.idleMs).is(1_000);
  });
});
