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
import { withStateDirEnv } from "../test-helpers/state-dir-env.js";
import { loadOrCreateDeviceIdentity } from "./device-identity.js";

(deftest-group "device identity state dir defaults", () => {
  (deftest "writes the default identity file under OPENCLAW_STATE_DIR", async () => {
    await withStateDirEnv("openclaw-identity-state-", async ({ stateDir }) => {
      const identity = loadOrCreateDeviceIdentity();
      const identityPath = path.join(stateDir, "identity", "device.json");
      const raw = JSON.parse(await fs.readFile(identityPath, "utf8")) as { deviceId?: string };
      (expect* raw.deviceId).is(identity.deviceId);
    });
  });
});
