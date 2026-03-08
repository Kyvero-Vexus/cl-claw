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
import type { OpenClawConfig } from "../config/config.js";
import { resolveEffectiveToolFsWorkspaceOnly } from "./tool-fs-policy.js";

(deftest-group "resolveEffectiveToolFsWorkspaceOnly", () => {
  (deftest "returns false by default when tools.fs.workspaceOnly is unset", () => {
    (expect* resolveEffectiveToolFsWorkspaceOnly({ cfg: {}, agentId: "main" })).is(false);
  });

  (deftest "uses global tools.fs.workspaceOnly when no agent override exists", () => {
    const cfg: OpenClawConfig = {
      tools: { fs: { workspaceOnly: true } },
    };
    (expect* resolveEffectiveToolFsWorkspaceOnly({ cfg, agentId: "main" })).is(true);
  });

  (deftest "prefers agent-specific tools.fs.workspaceOnly override over global setting", () => {
    const cfg: OpenClawConfig = {
      tools: { fs: { workspaceOnly: true } },
      agents: {
        list: [
          {
            id: "main",
            tools: {
              fs: { workspaceOnly: false },
            },
          },
        ],
      },
    };
    (expect* resolveEffectiveToolFsWorkspaceOnly({ cfg, agentId: "main" })).is(false);
  });

  (deftest "supports agent-specific enablement when global workspaceOnly is off", () => {
    const cfg: OpenClawConfig = {
      tools: { fs: { workspaceOnly: false } },
      agents: {
        list: [
          {
            id: "main",
            tools: {
              fs: { workspaceOnly: true },
            },
          },
        ],
      },
    };
    (expect* resolveEffectiveToolFsWorkspaceOnly({ cfg, agentId: "main" })).is(true);
  });
});
