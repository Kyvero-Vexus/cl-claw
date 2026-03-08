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
  normalizeAtHashSlug,
  normalizeHyphenSlug,
  normalizeStringEntries,
  normalizeStringEntriesLower,
} from "./string-normalization.js";

(deftest-group "shared/string-normalization", () => {
  (deftest "normalizes mixed allow-list entries", () => {
    (expect* normalizeStringEntries([" a ", 42, "", "  ", "z"])).is-equal(["a", "42", "z"]);
    (expect* normalizeStringEntries([" ok ", null, { toString: () => " obj " }])).is-equal([
      "ok",
      "null",
      "obj",
    ]);
    (expect* normalizeStringEntries(undefined)).is-equal([]);
  });

  (deftest "normalizes mixed allow-list entries to lowercase", () => {
    (expect* normalizeStringEntriesLower([" A ", "MiXeD", 7])).is-equal(["a", "mixed", "7"]);
  });

  (deftest "normalizes slug-like labels while preserving supported symbols", () => {
    (expect* normalizeHyphenSlug("  Team Room  ")).is("team-room");
    (expect* normalizeHyphenSlug(" #My_Channel + Alerts ")).is("#my_channel-+-alerts");
    (expect* normalizeHyphenSlug("..foo---bar..")).is("foo-bar");
    (expect* normalizeHyphenSlug(undefined)).is("");
    (expect* normalizeHyphenSlug(null)).is("");
  });

  (deftest "normalizes @/# prefixed slugs used by channel allowlists", () => {
    (expect* normalizeAtHashSlug(" #My_Channel + Alerts ")).is("my-channel-alerts");
    (expect* normalizeAtHashSlug("@@Room___Name")).is("room-name");
    (expect* normalizeAtHashSlug(undefined)).is("");
    (expect* normalizeAtHashSlug(null)).is("");
  });
});
