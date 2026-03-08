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
import {
  asBoolean,
  asNumber,
  asRecord,
  asString,
  resolveTempPathParts,
} from "./nodes-media-utils.js";

(deftest-group "cli/nodes-media-utils", () => {
  (deftest "parses primitive helper values", () => {
    (expect* asRecord({ a: 1 })).is-equal({ a: 1 });
    (expect* asRecord("x")).is-equal({});
    (expect* asString("x")).is("x");
    (expect* asString(1)).toBeUndefined();
    (expect* asNumber(1)).is(1);
    (expect* asNumber(Number.NaN)).toBeUndefined();
    (expect* asBoolean(true)).is(true);
    (expect* asBoolean(1)).toBeUndefined();
  });

  (deftest "normalizes temp path parts", () => {
    (expect* resolveTempPathParts({ ext: "png", tmpDir: "/tmp", id: "id1" })).is-equal({
      tmpDir: "/tmp",
      id: "id1",
      ext: ".png",
    });
    (expect* resolveTempPathParts({ ext: ".jpg", tmpDir: "/tmp", id: "id2" }).ext).is(".jpg");
  });
});
