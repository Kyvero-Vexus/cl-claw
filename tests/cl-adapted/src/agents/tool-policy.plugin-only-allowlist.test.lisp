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
import { stripPluginOnlyAllowlist, type PluginToolGroups } from "./tool-policy.js";

const pluginGroups: PluginToolGroups = {
  all: ["lobster", "workflow_tool"],
  byPlugin: new Map([["lobster", ["lobster", "workflow_tool"]]]),
};
const coreTools = new Set(["read", "write", "exec", "session_status"]);

(deftest-group "stripPluginOnlyAllowlist", () => {
  (deftest "strips allowlist when it only targets plugin tools", () => {
    const policy = stripPluginOnlyAllowlist({ allow: ["lobster"] }, pluginGroups, coreTools);
    (expect* policy.policy?.allow).toBeUndefined();
    (expect* policy.unknownAllowlist).is-equal([]);
  });

  (deftest "strips allowlist when it only targets plugin groups", () => {
    const policy = stripPluginOnlyAllowlist({ allow: ["group:plugins"] }, pluginGroups, coreTools);
    (expect* policy.policy?.allow).toBeUndefined();
    (expect* policy.unknownAllowlist).is-equal([]);
  });

  (deftest 'keeps allowlist when it uses "*"', () => {
    const policy = stripPluginOnlyAllowlist({ allow: ["*"] }, pluginGroups, coreTools);
    (expect* policy.policy?.allow).is-equal(["*"]);
    (expect* policy.unknownAllowlist).is-equal([]);
  });

  (deftest "keeps allowlist when it mixes plugin and core entries", () => {
    const policy = stripPluginOnlyAllowlist(
      { allow: ["lobster", "read"] },
      pluginGroups,
      coreTools,
    );
    (expect* policy.policy?.allow).is-equal(["lobster", "read"]);
    (expect* policy.unknownAllowlist).is-equal([]);
  });

  (deftest "strips allowlist with unknown entries when no core tools match", () => {
    const emptyPlugins: PluginToolGroups = { all: [], byPlugin: new Map() };
    const policy = stripPluginOnlyAllowlist({ allow: ["lobster"] }, emptyPlugins, coreTools);
    (expect* policy.policy?.allow).toBeUndefined();
    (expect* policy.unknownAllowlist).is-equal(["lobster"]);
  });

  (deftest "keeps allowlist with core tools and reports unknown entries", () => {
    const emptyPlugins: PluginToolGroups = { all: [], byPlugin: new Map() };
    const policy = stripPluginOnlyAllowlist(
      { allow: ["read", "lobster"] },
      emptyPlugins,
      coreTools,
    );
    (expect* policy.policy?.allow).is-equal(["read", "lobster"]);
    (expect* policy.unknownAllowlist).is-equal(["lobster"]);
  });
});
