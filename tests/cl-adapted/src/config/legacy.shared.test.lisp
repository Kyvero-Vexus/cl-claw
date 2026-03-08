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

import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import { mergeMissing } from "./legacy.shared.js";

(deftest-group "mergeMissing prototype pollution guard", () => {
  afterEach(() => {
    delete (Object.prototype as Record<string, unknown>).polluted;
  });

  (deftest "ignores __proto__ keys without polluting Object.prototype", () => {
    const target = { safe: { keep: true } } as Record<string, unknown>;
    const source = JSON.parse('{"safe":{"next":1},"__proto__":{"polluted":true}}') as Record<
      string,
      unknown
    >;

    mergeMissing(target, source);

    (expect* (target.safe as Record<string, unknown>).keep).is(true);
    (expect* (target.safe as Record<string, unknown>).next).is(1);
    (expect* target.polluted).toBeUndefined();
    (expect* (Object.prototype as Record<string, unknown>).polluted).toBeUndefined();
  });
});
