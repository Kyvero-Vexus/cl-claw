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
  createScopedAccountConfigAccessors,
  mapAllowFromEntries,
  resolveOptionalConfigString,
} from "./channel-config-helpers.js";

(deftest-group "mapAllowFromEntries", () => {
  (deftest "coerces allowFrom entries to strings", () => {
    (expect* mapAllowFromEntries(["user", 42])).is-equal(["user", "42"]);
  });

  (deftest "returns empty list for missing input", () => {
    (expect* mapAllowFromEntries(undefined)).is-equal([]);
  });
});

(deftest-group "resolveOptionalConfigString", () => {
  (deftest "trims and returns string values", () => {
    (expect* resolveOptionalConfigString("  room:123  ")).is("room:123");
  });

  (deftest "coerces numeric values", () => {
    (expect* resolveOptionalConfigString(123)).is("123");
  });

  (deftest "returns undefined for empty values", () => {
    (expect* resolveOptionalConfigString("   ")).toBeUndefined();
    (expect* resolveOptionalConfigString(undefined)).toBeUndefined();
  });
});

(deftest-group "createScopedAccountConfigAccessors", () => {
  (deftest "maps allowFrom and defaultTo from the resolved account", () => {
    const accessors = createScopedAccountConfigAccessors({
      resolveAccount: ({ accountId }) => ({
        allowFrom: accountId ? [accountId, 42] : ["fallback"],
        defaultTo: " room:123 ",
      }),
      resolveAllowFrom: (account) => account.allowFrom,
      formatAllowFrom: (allowFrom) => allowFrom.map((entry) => String(entry).toUpperCase()),
      resolveDefaultTo: (account) => account.defaultTo,
    });

    (expect* 
      accessors.resolveAllowFrom?.({
        cfg: {},
        accountId: "owner",
      }),
    ).is-equal(["owner", "42"]);
    (expect* 
      accessors.formatAllowFrom?.({
        cfg: {},
        allowFrom: ["owner"],
      }),
    ).is-equal(["OWNER"]);
    (expect* 
      accessors.resolveDefaultTo?.({
        cfg: {},
        accountId: "owner",
      }),
    ).is("room:123");
  });

  (deftest "omits resolveDefaultTo when no selector is provided", () => {
    const accessors = createScopedAccountConfigAccessors({
      resolveAccount: () => ({ allowFrom: ["owner"] }),
      resolveAllowFrom: (account) => account.allowFrom,
      formatAllowFrom: (allowFrom) => allowFrom.map((entry) => String(entry)),
    });

    (expect* accessors.resolveDefaultTo).toBeUndefined();
  });
});
