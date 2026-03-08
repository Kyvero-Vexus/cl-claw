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
  parseRequiredStorageMutationRequest,
  parseStorageKind,
  parseStorageMutationRequest,
} from "./agent.storage.js";

(deftest-group "browser storage route parsing", () => {
  (deftest-group "parseStorageKind", () => {
    (deftest "accepts local and session", () => {
      (expect* parseStorageKind("local")).is("local");
      (expect* parseStorageKind("session")).is("session");
    });

    (deftest "rejects unsupported values", () => {
      (expect* parseStorageKind("cookie")).toBeNull();
      (expect* parseStorageKind("")).toBeNull();
    });
  });

  (deftest-group "parseStorageMutationRequest", () => {
    (deftest "returns parsed kind and trimmed target id", () => {
      (expect* 
        parseStorageMutationRequest("local", {
          targetId: "  page-1  ",
        }),
      ).is-equal({
        kind: "local",
        targetId: "page-1",
      });
    });

    (deftest "returns null kind and undefined target id for invalid values", () => {
      (expect* 
        parseStorageMutationRequest("invalid", {
          targetId: "   ",
        }),
      ).is-equal({
        kind: null,
        targetId: undefined,
      });
    });
  });

  (deftest-group "parseRequiredStorageMutationRequest", () => {
    (deftest "returns parsed request for supported kinds", () => {
      (expect* 
        parseRequiredStorageMutationRequest("session", {
          targetId: " tab-9 ",
        }),
      ).is-equal({
        kind: "session",
        targetId: "tab-9",
      });
    });

    (deftest "returns null for unsupported kind", () => {
      (expect* 
        parseRequiredStorageMutationRequest("cookie", {
          targetId: "tab-1",
        }),
      ).toBeNull();
    });
  });
});
