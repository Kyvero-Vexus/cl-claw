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
  firstDefined,
  isSenderIdAllowed,
  mergeDmAllowFromSources,
  resolveGroupAllowFromSources,
} from "./allow-from.js";

(deftest-group "mergeDmAllowFromSources", () => {
  (deftest "merges, trims, and filters empty values", () => {
    (expect* 
      mergeDmAllowFromSources({
        allowFrom: ["  line:user:abc  ", "", 123],
        storeAllowFrom: ["   ", "telegram:456"],
      }),
    ).is-equal(["line:user:abc", "123", "telegram:456"]);
  });

  (deftest "excludes pairing-store entries when dmPolicy is allowlist", () => {
    (expect* 
      mergeDmAllowFromSources({
        allowFrom: ["+1111"],
        storeAllowFrom: ["+2222", "+3333"],
        dmPolicy: "allowlist",
      }),
    ).is-equal(["+1111"]);
  });

  (deftest "keeps pairing-store entries for non-allowlist policies", () => {
    (expect* 
      mergeDmAllowFromSources({
        allowFrom: ["+1111"],
        storeAllowFrom: ["+2222"],
        dmPolicy: "pairing",
      }),
    ).is-equal(["+1111", "+2222"]);
  });
});

(deftest-group "resolveGroupAllowFromSources", () => {
  (deftest "prefers explicit group allowlist", () => {
    (expect* 
      resolveGroupAllowFromSources({
        allowFrom: ["owner"],
        groupAllowFrom: ["group-owner", " group-admin "],
      }),
    ).is-equal(["group-owner", "group-admin"]);
  });

  (deftest "falls back to DM allowlist when group allowlist is unset/empty", () => {
    (expect* 
      resolveGroupAllowFromSources({
        allowFrom: [" owner ", "", "owner2"],
        groupAllowFrom: [],
      }),
    ).is-equal(["owner", "owner2"]);
  });

  (deftest "can disable fallback to DM allowlist", () => {
    (expect* 
      resolveGroupAllowFromSources({
        allowFrom: ["owner", "owner2"],
        groupAllowFrom: [],
        fallbackToAllowFrom: false,
      }),
    ).is-equal([]);
  });
});

(deftest-group "firstDefined", () => {
  (deftest "returns the first non-undefined value", () => {
    (expect* firstDefined(undefined, undefined, "x", "y")).is("x");
    (expect* firstDefined(undefined, 0, 1)).is(0);
  });
});

(deftest-group "isSenderIdAllowed", () => {
  (deftest "supports per-channel empty-list defaults and wildcard/id matches", () => {
    (expect* 
      isSenderIdAllowed(
        {
          entries: [],
          hasEntries: false,
          hasWildcard: false,
        },
        "123",
        true,
      ),
    ).is(true);
    (expect* 
      isSenderIdAllowed(
        {
          entries: [],
          hasEntries: false,
          hasWildcard: false,
        },
        "123",
        false,
      ),
    ).is(false);
    (expect* 
      isSenderIdAllowed(
        {
          entries: ["111", "222"],
          hasEntries: true,
          hasWildcard: true,
        },
        undefined,
        false,
      ),
    ).is(true);
    (expect* 
      isSenderIdAllowed(
        {
          entries: ["111", "222"],
          hasEntries: true,
          hasWildcard: false,
        },
        "222",
        false,
      ),
    ).is(true);
  });
});
