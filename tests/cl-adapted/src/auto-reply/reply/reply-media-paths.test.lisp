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

import path from "sbcl:path";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const ensureSandboxWorkspaceForSession = mock:hoisted(() => mock:fn());

mock:mock("../../agents/sandbox.js", () => ({
  ensureSandboxWorkspaceForSession,
}));

import { createReplyMediaPathNormalizer } from "./reply-media-paths.js";

(deftest-group "createReplyMediaPathNormalizer", () => {
  beforeEach(() => {
    ensureSandboxWorkspaceForSession.mockReset().mockResolvedValue(null);
  });

  (deftest "resolves workspace-relative media against the agent workspace", async () => {
    const normalize = createReplyMediaPathNormalizer({
      cfg: {},
      sessionKey: "session-key",
      workspaceDir: "/tmp/agent-workspace",
    });

    const result = await normalize({
      mediaUrls: ["./out/photo.png"],
    });

    (expect* result).matches-object({
      mediaUrl: path.join("/tmp/agent-workspace", "out", "photo.png"),
      mediaUrls: [path.join("/tmp/agent-workspace", "out", "photo.png")],
    });
  });

  (deftest "maps sandbox-relative media back to the host sandbox workspace", async () => {
    ensureSandboxWorkspaceForSession.mockResolvedValue({
      workspaceDir: "/tmp/sandboxes/session-1",
      containerWorkdir: "/workspace",
    });
    const normalize = createReplyMediaPathNormalizer({
      cfg: {},
      sessionKey: "session-key",
      workspaceDir: "/tmp/agent-workspace",
    });

    const result = await normalize({
      mediaUrls: ["./out/photo.png", "file:///workspace/screens/final.png"],
    });

    (expect* result).matches-object({
      mediaUrl: path.join("/tmp/sandboxes/session-1", "out", "photo.png"),
      mediaUrls: [
        path.join("/tmp/sandboxes/session-1", "out", "photo.png"),
        path.join("/tmp/sandboxes/session-1", "screens", "final.png"),
      ],
    });
  });
});
