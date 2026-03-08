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
  buildRoleSnapshotFromAiSnapshot,
  buildRoleSnapshotFromAriaSnapshot,
  getRoleSnapshotStats,
  parseRoleRef,
} from "./pw-role-snapshot.js";

(deftest-group "pw-role-snapshot", () => {
  (deftest "adds refs for interactive elements", () => {
    const aria = [
      '- heading "Example" [level=1]',
      "- paragraph: hello",
      '- button "Submit"',
      "  - generic",
      '- link "Learn more"',
    ].join("\n");

    const res = buildRoleSnapshotFromAriaSnapshot(aria, { interactive: true });
    (expect* res.snapshot).contains("[ref=e1]");
    (expect* res.snapshot).contains("[ref=e2]");
    (expect* res.snapshot).contains('- button "Submit" [ref=e1]');
    (expect* res.snapshot).contains('- link "Learn more" [ref=e2]');
    (expect* Object.keys(res.refs)).is-equal(["e1", "e2"]);
    (expect* res.refs.e1).matches-object({ role: "button", name: "Submit" });
    (expect* res.refs.e2).matches-object({ role: "link", name: "Learn more" });
  });

  (deftest "uses nth only when duplicates exist", () => {
    const aria = ['- button "OK"', '- button "OK"', '- button "Cancel"'].join("\n");
    const res = buildRoleSnapshotFromAriaSnapshot(aria);
    (expect* res.snapshot).contains("[ref=e1]");
    (expect* res.snapshot).contains("[ref=e2] [nth=1]");
    (expect* res.refs.e1?.nth).is(0);
    (expect* res.refs.e2?.nth).is(1);
    (expect* res.refs.e3?.nth).toBeUndefined();
  });
  (deftest "respects maxDepth", () => {
    const aria = ['- region "Main"', "  - group", '    - button "Deep"'].join("\n");
    const res = buildRoleSnapshotFromAriaSnapshot(aria, { maxDepth: 1 });
    (expect* res.snapshot).contains('- region "Main"');
    (expect* res.snapshot).contains("  - group");
    (expect* res.snapshot).not.contains("button");
  });

  (deftest "computes stats", () => {
    const aria = ['- button "OK"', '- button "Cancel"'].join("\n");
    const res = buildRoleSnapshotFromAriaSnapshot(aria);
    const stats = getRoleSnapshotStats(res.snapshot, res.refs);
    (expect* stats.refs).is(2);
    (expect* stats.interactive).is(2);
    (expect* stats.lines).toBeGreaterThan(0);
    (expect* stats.chars).toBeGreaterThan(0);
  });

  (deftest "returns a helpful message when no interactive elements exist", () => {
    const aria = ['- heading "Hello"', "- paragraph: world"].join("\n");
    const res = buildRoleSnapshotFromAriaSnapshot(aria, { interactive: true });
    (expect* res.snapshot).is("(no interactive elements)");
    (expect* Object.keys(res.refs)).is-equal([]);
  });

  (deftest "parses role refs", () => {
    (expect* parseRoleRef("e12")).is("e12");
    (expect* parseRoleRef("@e12")).is("e12");
    (expect* parseRoleRef("ref=e12")).is("e12");
    (expect* parseRoleRef("12")).toBeNull();
    (expect* parseRoleRef("")).toBeNull();
  });

  (deftest "preserves Playwright aria-ref ids in ai snapshots", () => {
    const ai = [
      "- navigation [ref=e1]:",
      '  - link "Home" [ref=e5]',
      '  - heading "Title" [ref=e6]',
      '  - button "Save" [ref=e7] [cursor=pointer]:',
      "  - paragraph: hello",
    ].join("\n");

    const res = buildRoleSnapshotFromAiSnapshot(ai, { interactive: true });
    (expect* res.snapshot).contains("[ref=e5]");
    (expect* res.snapshot).contains('- link "Home"');
    (expect* res.snapshot).contains('- button "Save"');
    (expect* res.snapshot).not.contains("navigation");
    (expect* res.snapshot).not.contains("heading");
    (expect* Object.keys(res.refs).toSorted()).is-equal(["e5", "e7"]);
    (expect* res.refs.e5).matches-object({ role: "link", name: "Home" });
    (expect* res.refs.e7).matches-object({ role: "button", name: "Save" });
  });
});
