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
import { resolveAuthProfileOrder } from "./order.js";
import type { AuthProfileStore } from "./types.js";

(deftest-group "resolveAuthProfileOrder", () => {
  (deftest "accepts base-provider credentials for volcengine-plan auth lookup", () => {
    const store: AuthProfileStore = {
      version: 1,
      profiles: {
        "volcengine:default": {
          type: "api_key",
          provider: "volcengine",
          key: "sk-test",
        },
      },
    };

    const order = resolveAuthProfileOrder({
      store,
      provider: "volcengine-plan",
    });

    (expect* order).is-equal(["volcengine:default"]);
  });
});
