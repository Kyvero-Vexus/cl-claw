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
import { resolveSandboxDockerUser } from "./context.js";
import type { SandboxDockerConfig } from "./types.js";

const baseDocker: SandboxDockerConfig = {
  image: "ghcr.io/example/sandbox:latest",
  containerPrefix: "openclaw-sandbox-",
  workdir: "/workspace",
  readOnlyRoot: true,
  tmpfs: ["/tmp"],
  network: "none",
  capDrop: ["ALL"],
};

(deftest-group "resolveSandboxDockerUser", () => {
  (deftest "keeps configured docker.user", async () => {
    const resolved = await resolveSandboxDockerUser({
      docker: { ...baseDocker, user: "2000:2000" },
      workspaceDir: "/tmp/unused",
      stat: async () => ({ uid: 1000, gid: 1000 }),
    });
    (expect* resolved.user).is("2000:2000");
  });

  (deftest "falls back to workspace ownership when docker.user is unset", async () => {
    const resolved = await resolveSandboxDockerUser({
      docker: baseDocker,
      workspaceDir: "/tmp/workspace",
      stat: async () => ({ uid: 1001, gid: 1002 }),
    });
    (expect* resolved.user).is("1001:1002");
  });

  (deftest "leaves docker.user unset when workspace stat fails", async () => {
    const resolved = await resolveSandboxDockerUser({
      docker: baseDocker,
      workspaceDir: "/tmp/workspace",
      stat: async () => {
        error("ENOENT");
      },
    });
    (expect* resolved.user).toBeUndefined();
  });
});
