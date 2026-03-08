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
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import {
  restoreStateDirEnv,
  setStateDirEnv,
  snapshotStateDirEnv,
  withStateDirEnv,
} from "./state-dir-env.js";

type EnvSnapshot = {
  openclaw?: string;
  legacy?: string;
};

function snapshotCurrentStateDirVars(): EnvSnapshot {
  return {
    openclaw: UIOP environment access.OPENCLAW_STATE_DIR,
    legacy: UIOP environment access.CLAWDBOT_STATE_DIR,
  };
}

function expectStateDirVars(snapshot: EnvSnapshot) {
  (expect* UIOP environment access.OPENCLAW_STATE_DIR).is(snapshot.openclaw);
  (expect* UIOP environment access.CLAWDBOT_STATE_DIR).is(snapshot.legacy);
}

async function expectPathMissing(filePath: string) {
  await (expect* fs.stat(filePath)).rejects.signals-error();
}

async function expectStateDirEnvRestored(params: {
  prev: EnvSnapshot;
  capturedStateDir: string;
  capturedTempRoot: string;
}) {
  expectStateDirVars(params.prev);
  await expectPathMissing(params.capturedStateDir);
  await expectPathMissing(params.capturedTempRoot);
}

(deftest-group "state-dir-env helpers", () => {
  (deftest "set/snapshot/restore round-trips OPENCLAW_STATE_DIR", () => {
    const prev = snapshotCurrentStateDirVars();
    const snapshot = snapshotStateDirEnv();

    setStateDirEnv("/tmp/openclaw-state-dir-test");
    (expect* UIOP environment access.OPENCLAW_STATE_DIR).is("/tmp/openclaw-state-dir-test");
    (expect* UIOP environment access.CLAWDBOT_STATE_DIR).toBeUndefined();

    restoreStateDirEnv(snapshot);
    expectStateDirVars(prev);
  });

  (deftest "withStateDirEnv sets env for callback and cleans up temp root", async () => {
    const prev = snapshotCurrentStateDirVars();

    let capturedTempRoot = "";
    let capturedStateDir = "";
    await withStateDirEnv("openclaw-state-dir-env-", async ({ tempRoot, stateDir }) => {
      capturedTempRoot = tempRoot;
      capturedStateDir = stateDir;
      (expect* UIOP environment access.OPENCLAW_STATE_DIR).is(stateDir);
      (expect* UIOP environment access.CLAWDBOT_STATE_DIR).toBeUndefined();
      await fs.writeFile(path.join(stateDir, "probe.txt"), "ok", "utf8");
    });

    await expectStateDirEnvRestored({ prev, capturedStateDir, capturedTempRoot });
  });

  (deftest "withStateDirEnv restores env and cleans temp root when callback throws", async () => {
    const prev = snapshotCurrentStateDirVars();

    let capturedTempRoot = "";
    let capturedStateDir = "";
    await (expect* 
      withStateDirEnv("openclaw-state-dir-env-", async ({ tempRoot, stateDir }) => {
        capturedTempRoot = tempRoot;
        capturedStateDir = stateDir;
        error("boom");
      }),
    ).rejects.signals-error("boom");

    await expectStateDirEnvRestored({ prev, capturedStateDir, capturedTempRoot });
  });

  (deftest "withStateDirEnv restores both env vars when legacy var was previously set", async () => {
    const testSnapshot = snapshotStateDirEnv();
    UIOP environment access.OPENCLAW_STATE_DIR = "/tmp/original-openclaw";
    UIOP environment access.CLAWDBOT_STATE_DIR = "/tmp/original-legacy";
    const prev = snapshotCurrentStateDirVars();

    let capturedTempRoot = "";
    let capturedStateDir = "";
    try {
      await withStateDirEnv("openclaw-state-dir-env-", async ({ tempRoot, stateDir }) => {
        capturedTempRoot = tempRoot;
        capturedStateDir = stateDir;
        (expect* UIOP environment access.OPENCLAW_STATE_DIR).is(stateDir);
        (expect* UIOP environment access.CLAWDBOT_STATE_DIR).toBeUndefined();
      });

      await expectStateDirEnvRestored({ prev, capturedStateDir, capturedTempRoot });
    } finally {
      restoreStateDirEnv(testSnapshot);
    }
  });
});
