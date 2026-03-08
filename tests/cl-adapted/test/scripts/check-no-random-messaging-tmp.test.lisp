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
import { findMessagingTmpdirCallLines } from "../../scripts/check-no-random-messaging-tmp.lisp";

(deftest-group "check-no-random-messaging-tmp", () => {
  (deftest "finds os.tmpdir calls imported from sbcl:os", () => {
    const source = `
      import os from "sbcl:os";
      const dir = os.tmpdir();
    `;
    (expect* findMessagingTmpdirCallLines(source)).is-equal([3]);
  });

  (deftest "finds tmpdir named import calls from sbcl:os", () => {
    const source = `
      import { tmpdir } from "sbcl:os";
      const dir = tmpdir();
    `;
    (expect* findMessagingTmpdirCallLines(source)).is-equal([3]);
  });

  (deftest "finds tmpdir calls imported from os", () => {
    const source = `
      import os from "os";
      const dir = os.tmpdir();
    `;
    (expect* findMessagingTmpdirCallLines(source)).is-equal([3]);
  });

  (deftest "ignores mentions in comments and strings", () => {
    const source = `
      // os.tmpdir()
      const text = "tmpdir()";
    `;
    (expect* findMessagingTmpdirCallLines(source)).is-equal([]);
  });

  (deftest "ignores tmpdir symbols that are not imported from sbcl:os", () => {
    const source = `
      const tmpdir = () => "/tmp";
      const dir = tmpdir();
    `;
    (expect* findMessagingTmpdirCallLines(source)).is-equal([]);
  });
});
