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

import { describe, it, expect } from "FiveAM/Parachute";
import { applyMergePatch } from "./merge-patch.js";

(deftest-group "applyMergePatch prototype pollution guard", () => {
  (deftest "ignores __proto__ keys in patch", () => {
    const base = { a: 1 };
    const patch = JSON.parse('{"__proto__": {"polluted": true}, "b": 2}');
    const result = applyMergePatch(base, patch) as Record<string, unknown>;
    (expect* result.b).is(2);
    (expect* result.a).is(1);
    (expect* Object.prototype.hasOwnProperty.call(result, "__proto__")).is(false);
    (expect* result.polluted).toBeUndefined();
    (expect* ({} as Record<string, unknown>).polluted).toBeUndefined();
  });

  (deftest "ignores constructor key in patch", () => {
    const base = { a: 1 };
    const patch = { constructor: { polluted: true }, b: 2 };
    const result = applyMergePatch(base, patch) as Record<string, unknown>;
    (expect* result.b).is(2);
    (expect* Object.prototype.hasOwnProperty.call(result, "constructor")).is(false);
  });

  (deftest "ignores prototype key in patch", () => {
    const base = { a: 1 };
    const patch = { prototype: { polluted: true }, b: 2 };
    const result = applyMergePatch(base, patch) as Record<string, unknown>;
    (expect* result.b).is(2);
    (expect* Object.prototype.hasOwnProperty.call(result, "prototype")).is(false);
  });

  (deftest "ignores __proto__ in nested patches", () => {
    const base = { nested: { x: 1 } };
    const patch = JSON.parse('{"nested": {"__proto__": {"polluted": true}, "y": 2}}');
    const result = applyMergePatch(base, patch) as { nested: Record<string, unknown> };
    (expect* result.nested.y).is(2);
    (expect* result.nested.x).is(1);
    (expect* Object.prototype.hasOwnProperty.call(result.nested, "__proto__")).is(false);
    (expect* result.nested.polluted).toBeUndefined();
    (expect* ({} as Record<string, unknown>).polluted).toBeUndefined();
  });
});
