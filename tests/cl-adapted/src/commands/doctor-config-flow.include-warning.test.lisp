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
import { withTempHomeConfig } from "../config/test-helpers.js";
import { note } from "../terminal/note.js";

mock:mock("../terminal/note.js", () => ({
  note: mock:fn(),
}));

import { loadAndMaybeMigrateDoctorConfig } from "./doctor-config-flow.js";

const noteSpy = mock:mocked(note);

(deftest-group "doctor include warning", () => {
  (deftest "surfaces include confinement hint for escaped include paths", async () => {
    await withTempHomeConfig({ $include: "/etc/passwd" }, async () => {
      await loadAndMaybeMigrateDoctorConfig({
        options: { nonInteractive: true },
        confirm: async () => false,
      });
    });

    (expect* noteSpy).toHaveBeenCalledWith(
      expect.stringContaining("$include paths must stay under:"),
      "Doctor warnings",
    );
  });
});
