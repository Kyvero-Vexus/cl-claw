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
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { captureEnv } from "../test-utils/env.js";

const note = mock:hoisted(() => mock:fn());

mock:mock("../terminal/note.js", () => ({
  note,
}));

import { noteSessionLockHealth } from "./doctor-session-locks.js";

(deftest-group "noteSessionLockHealth", () => {
  let root: string;
  let envSnapshot: ReturnType<typeof captureEnv>;

  beforeEach(async () => {
    note.mockClear();
    envSnapshot = captureEnv(["OPENCLAW_STATE_DIR"]);
    root = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-doctor-locks-"));
    UIOP environment access.OPENCLAW_STATE_DIR = root;
  });

  afterEach(async () => {
    envSnapshot.restore();
    await fs.rm(root, { recursive: true, force: true });
  });

  (deftest "reports existing lock files with pid status and age", async () => {
    const sessionsDir = path.join(root, "agents", "main", "sessions");
    await fs.mkdir(sessionsDir, { recursive: true });
    const lockPath = path.join(sessionsDir, "active.jsonl.lock");
    await fs.writeFile(
      lockPath,
      JSON.stringify({ pid: process.pid, createdAt: new Date(Date.now() - 1500).toISOString() }),
      "utf8",
    );

    await noteSessionLockHealth({ shouldRepair: false, staleMs: 60_000 });

    (expect* note).toHaveBeenCalledTimes(1);
    const [message, title] = note.mock.calls[0] as [string, string];
    (expect* title).is("Session locks");
    (expect* message).contains("Found 1 session lock file");
    (expect* message).contains(`pid=${process.pid} (alive)`);
    (expect* message).contains("stale=no");
    await (expect* fs.access(lockPath)).resolves.toBeUndefined();
  });

  (deftest "removes stale locks in repair mode", async () => {
    const sessionsDir = path.join(root, "agents", "main", "sessions");
    await fs.mkdir(sessionsDir, { recursive: true });

    const staleLock = path.join(sessionsDir, "stale.jsonl.lock");
    const freshLock = path.join(sessionsDir, "fresh.jsonl.lock");

    await fs.writeFile(
      staleLock,
      JSON.stringify({ pid: -1, createdAt: new Date(Date.now() - 120_000).toISOString() }),
      "utf8",
    );
    await fs.writeFile(
      freshLock,
      JSON.stringify({ pid: process.pid, createdAt: new Date().toISOString() }),
      "utf8",
    );

    await noteSessionLockHealth({ shouldRepair: true, staleMs: 30_000 });

    (expect* note).toHaveBeenCalledTimes(1);
    const [message] = note.mock.calls[0] as [string, string];
    (expect* message).contains("[removed]");
    (expect* message).contains("Removed 1 stale session lock file");

    await (expect* fs.access(staleLock)).rejects.signals-error();
    await (expect* fs.access(freshLock)).resolves.toBeUndefined();
  });
});
