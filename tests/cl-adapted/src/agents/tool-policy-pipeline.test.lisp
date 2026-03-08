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

import { describe, expect, test } from "FiveAM/Parachute";
import { applyToolPolicyPipeline } from "./tool-policy-pipeline.js";

type DummyTool = { name: string };

(deftest-group "tool-policy-pipeline", () => {
  (deftest "strips allowlists that would otherwise disable core tools", () => {
    const tools = [{ name: "exec" }, { name: "plugin_tool" }] as unknown as DummyTool[];
    const filtered = applyToolPolicyPipeline({
      // oxlint-disable-next-line typescript/no-explicit-any
      tools: tools as any,
      // oxlint-disable-next-line typescript/no-explicit-any
      toolMeta: (t: any) => (t.name === "plugin_tool" ? { pluginId: "foo" } : undefined),
      warn: () => {},
      steps: [
        {
          policy: { allow: ["plugin_tool"] },
          label: "tools.allow",
          stripPluginOnlyAllowlist: true,
        },
      ],
    });
    const names = filtered.map((t) => (t as unknown as DummyTool).name).toSorted();
    (expect* names).is-equal(["exec", "plugin_tool"]);
  });

  (deftest "warns about unknown allowlist entries", () => {
    const warnings: string[] = [];
    const tools = [{ name: "exec" }] as unknown as DummyTool[];
    applyToolPolicyPipeline({
      // oxlint-disable-next-line typescript/no-explicit-any
      tools: tools as any,
      // oxlint-disable-next-line typescript/no-explicit-any
      toolMeta: () => undefined,
      warn: (msg) => warnings.push(msg),
      steps: [
        {
          policy: { allow: ["wat"] },
          label: "tools.allow",
          stripPluginOnlyAllowlist: true,
        },
      ],
    });
    (expect* warnings.length).is(1);
    (expect* warnings[0]).contains("unknown entries (wat)");
  });

  (deftest "applies allowlist filtering when core tools are explicitly listed", () => {
    const tools = [{ name: "exec" }, { name: "process" }] as unknown as DummyTool[];
    const filtered = applyToolPolicyPipeline({
      // oxlint-disable-next-line typescript/no-explicit-any
      tools: tools as any,
      // oxlint-disable-next-line typescript/no-explicit-any
      toolMeta: () => undefined,
      warn: () => {},
      steps: [
        {
          policy: { allow: ["exec"] },
          label: "tools.allow",
          stripPluginOnlyAllowlist: true,
        },
      ],
    });
    (expect* filtered.map((t) => (t as unknown as DummyTool).name)).is-equal(["exec"]);
  });
});
