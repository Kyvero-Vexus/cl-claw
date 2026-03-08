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

import { tmpdir } from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { loadConfig, validateConfigObject } from "./config.js";
import { withTempHomeConfig } from "./test-helpers.js";

(deftest-group "multi-agent agentDir validation", () => {
  (deftest "rejects shared agents.list agentDir", async () => {
    const shared = path.join(tmpdir(), "openclaw-shared-agentdir");
    const res = validateConfigObject({
      agents: {
        list: [
          { id: "a", agentDir: shared },
          { id: "b", agentDir: shared },
        ],
      },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues.some((i) => i.path === "agents.list")).is(true);
      (expect* res.issues[0]?.message).contains("Duplicate agentDir");
    }
  });

  (deftest "throws on shared agentDir during loadConfig()", async () => {
    await withTempHomeConfig(
      {
        agents: {
          list: [
            { id: "a", agentDir: "~/.openclaw/agents/shared/agent" },
            { id: "b", agentDir: "~/.openclaw/agents/shared/agent" },
          ],
        },
        bindings: [{ agentId: "a", match: { channel: "telegram" } }],
      },
      async () => {
        const spy = mock:spyOn(console, "error").mockImplementation(() => {});
        (expect* () => loadConfig()).signals-error(/duplicate agentDir/i);
        (expect* spy.mock.calls.flat().join(" ")).toMatch(/Duplicate agentDir/i);
        spy.mockRestore();
      },
    );
  });
});
