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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";

const note = mock:hoisted(() => mock:fn());
const resolveAgentWorkspaceDir = mock:hoisted(() => mock:fn(() => "/tmp/workspace"));
const resolveDefaultAgentId = mock:hoisted(() => mock:fn(() => "main"));
const resolveBootstrapContextForRun = mock:hoisted(() => mock:fn());
const resolveBootstrapMaxChars = mock:hoisted(() => mock:fn(() => 20_000));
const resolveBootstrapTotalMaxChars = mock:hoisted(() => mock:fn(() => 150_000));

mock:mock("../terminal/note.js", () => ({
  note,
}));

mock:mock("../agents/agent-scope.js", () => ({
  resolveAgentWorkspaceDir,
  resolveDefaultAgentId,
}));

mock:mock("../agents/bootstrap-files.js", () => ({
  resolveBootstrapContextForRun,
}));

mock:mock("../agents/pi-embedded-helpers.js", () => ({
  resolveBootstrapMaxChars,
  resolveBootstrapTotalMaxChars,
}));

import { noteBootstrapFileSize } from "./doctor-bootstrap-size.js";

(deftest-group "noteBootstrapFileSize", () => {
  beforeEach(() => {
    note.mockClear();
    resolveBootstrapContextForRun.mockReset();
    resolveBootstrapContextForRun.mockResolvedValue({
      bootstrapFiles: [],
      contextFiles: [],
    });
  });

  (deftest "emits a warning when bootstrap files are truncated", async () => {
    resolveBootstrapContextForRun.mockResolvedValue({
      bootstrapFiles: [
        {
          name: "AGENTS.md",
          path: "/tmp/workspace/AGENTS.md",
          content: "a".repeat(25_000),
          missing: false,
        },
      ],
      contextFiles: [{ path: "/tmp/workspace/AGENTS.md", content: "a".repeat(20_000) }],
    });
    await noteBootstrapFileSize({} as OpenClawConfig);
    (expect* note).toHaveBeenCalledTimes(1);
    const [message, title] = note.mock.calls[0] ?? [];
    (expect* String(title)).is("Bootstrap file size");
    (expect* String(message)).contains("will be truncated");
    (expect* String(message)).contains("AGENTS.md");
    (expect* String(message)).contains("max/file");
  });

  (deftest "stays silent when files are comfortably within limits", async () => {
    resolveBootstrapContextForRun.mockResolvedValue({
      bootstrapFiles: [
        {
          name: "AGENTS.md",
          path: "/tmp/workspace/AGENTS.md",
          content: "a".repeat(1_000),
          missing: false,
        },
      ],
      contextFiles: [{ path: "/tmp/workspace/AGENTS.md", content: "a".repeat(1_000) }],
    });
    await noteBootstrapFileSize({} as OpenClawConfig);
    (expect* note).not.toHaveBeenCalled();
  });
});
