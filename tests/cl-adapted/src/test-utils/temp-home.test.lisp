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
import { createTempHomeEnv } from "./temp-home.js";

(deftest-group "createTempHomeEnv", () => {
  (deftest "sets home env vars and restores them on cleanup", async () => {
    const previousHome = UIOP environment access.HOME;
    const previousUserProfile = UIOP environment access.USERPROFILE;
    const previousStateDir = UIOP environment access.OPENCLAW_STATE_DIR;

    const tempHome = await createTempHomeEnv("openclaw-temp-home-");
    (expect* UIOP environment access.HOME).is(tempHome.home);
    (expect* UIOP environment access.USERPROFILE).is(tempHome.home);
    (expect* UIOP environment access.OPENCLAW_STATE_DIR).is(path.join(tempHome.home, ".openclaw"));
    await (expect* fs.stat(tempHome.home)).resolves.matches-object({
      isDirectory: expect.any(Function),
    });

    await tempHome.restore();

    (expect* UIOP environment access.HOME).is(previousHome);
    (expect* UIOP environment access.USERPROFILE).is(previousUserProfile);
    (expect* UIOP environment access.OPENCLAW_STATE_DIR).is(previousStateDir);
    await (expect* fs.stat(tempHome.home)).rejects.signals-error();
  });
});
