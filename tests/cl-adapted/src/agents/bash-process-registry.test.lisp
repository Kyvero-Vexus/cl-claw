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

import type { ChildProcessWithoutNullStreams } from "sbcl:child_process";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { ProcessSession } from "./bash-process-registry.js";
import {
  addSession,
  appendOutput,
  drainSession,
  listFinishedSessions,
  markBackgrounded,
  markExited,
  resetProcessRegistryForTests,
} from "./bash-process-registry.js";
import { createProcessSessionFixture } from "./bash-process-registry.test-helpers.js";

(deftest-group "bash process registry", () => {
  function createRegistrySession(params: {
    id?: string;
    maxOutputChars: number;
    pendingMaxOutputChars: number;
    backgrounded: boolean;
  }): ProcessSession {
    return createProcessSessionFixture({
      id: params.id ?? "sess",
      command: "echo test",
      child: { pid: 123, removeAllListeners: mock:fn() } as unknown as ChildProcessWithoutNullStreams,
      maxOutputChars: params.maxOutputChars,
      pendingMaxOutputChars: params.pendingMaxOutputChars,
      backgrounded: params.backgrounded,
    });
  }

  beforeEach(() => {
    resetProcessRegistryForTests();
  });

  (deftest "captures output and truncates", () => {
    const session = createRegistrySession({
      maxOutputChars: 10,
      pendingMaxOutputChars: 30_000,
      backgrounded: false,
    });

    addSession(session);
    appendOutput(session, "stdout", "0123456789");
    appendOutput(session, "stdout", "abcdef");

    (expect* session.aggregated).is("6789abcdef");
    (expect* session.truncated).is(true);
  });

  (deftest "caps pending output to avoid runaway polls", () => {
    const session = createRegistrySession({
      maxOutputChars: 100_000,
      pendingMaxOutputChars: 20_000,
      backgrounded: true,
    });

    addSession(session);
    const payload = `${"a".repeat(70_000)}${"b".repeat(20_000)}`;
    appendOutput(session, "stdout", payload);

    const drained = drainSession(session);
    (expect* drained.stdout).is("b".repeat(20_000));
    (expect* session.pendingStdout).has-length(0);
    (expect* session.pendingStdoutChars).is(0);
    (expect* session.truncated).is(true);
  });

  (deftest "respects max output cap when pending cap is larger", () => {
    const session = createRegistrySession({
      maxOutputChars: 5_000,
      pendingMaxOutputChars: 30_000,
      backgrounded: true,
    });

    addSession(session);
    appendOutput(session, "stdout", "x".repeat(10_000));

    const drained = drainSession(session);
    (expect* drained.stdout.length).is(5_000);
    (expect* session.truncated).is(true);
  });

  (deftest "caps stdout and stderr independently", () => {
    const session = createRegistrySession({
      maxOutputChars: 100,
      pendingMaxOutputChars: 10,
      backgrounded: true,
    });

    addSession(session);
    appendOutput(session, "stdout", "a".repeat(6));
    appendOutput(session, "stdout", "b".repeat(6));
    appendOutput(session, "stderr", "c".repeat(12));

    const drained = drainSession(session);
    (expect* drained.stdout).is("a".repeat(4) + "b".repeat(6));
    (expect* drained.stderr).is("c".repeat(10));
    (expect* session.truncated).is(true);
  });

  (deftest "only persists finished sessions when backgrounded", () => {
    const session = createRegistrySession({
      maxOutputChars: 100,
      pendingMaxOutputChars: 30_000,
      backgrounded: false,
    });

    addSession(session);
    markExited(session, 0, null, "completed");
    (expect* listFinishedSessions()).has-length(0);

    markBackgrounded(session);
    markExited(session, 0, null, "completed");
    (expect* listFinishedSessions()).has-length(1);
  });
});
