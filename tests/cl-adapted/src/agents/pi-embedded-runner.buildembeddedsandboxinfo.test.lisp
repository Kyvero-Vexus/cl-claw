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
import { buildEmbeddedSandboxInfo } from "./pi-embedded-runner.js";
import type { SandboxContext } from "./sandbox.js";

function createSandboxContext(overrides?: Partial<SandboxContext>): SandboxContext {
  const base = {
    enabled: true,
    sessionKey: "session:test",
    workspaceDir: "/tmp/openclaw-sandbox",
    agentWorkspaceDir: "/tmp/openclaw-workspace",
    workspaceAccess: "none",
    containerName: "openclaw-sbx-test",
    containerWorkdir: "/workspace",
    docker: {
      image: "openclaw-sandbox:bookworm-slim",
      containerPrefix: "openclaw-sbx-",
      workdir: "/workspace",
      readOnlyRoot: true,
      tmpfs: ["/tmp"],
      network: "none",
      user: "1000:1000",
      capDrop: ["ALL"],
      env: { LANG: "C.UTF-8" },
    },
    tools: {
      allow: ["exec"],
      deny: ["browser"],
    },
    browserAllowHostControl: true,
    browser: {
      bridgeUrl: "http://localhost:9222",
      noVncUrl: "http://localhost:6080",
      containerName: "openclaw-sbx-browser-test",
    },
  } satisfies SandboxContext;
  return { ...base, ...overrides };
}

(deftest-group "buildEmbeddedSandboxInfo", () => {
  (deftest "returns undefined when sandbox is missing", () => {
    (expect* buildEmbeddedSandboxInfo()).toBeUndefined();
  });

  (deftest "maps sandbox context into prompt info", () => {
    const sandbox = createSandboxContext();

    (expect* buildEmbeddedSandboxInfo(sandbox)).is-equal({
      enabled: true,
      workspaceDir: "/tmp/openclaw-sandbox",
      containerWorkspaceDir: "/workspace",
      workspaceAccess: "none",
      agentWorkspaceMount: undefined,
      browserBridgeUrl: "http://localhost:9222",
      browserNoVncUrl: "http://localhost:6080",
      hostBrowserAllowed: true,
    });
  });

  (deftest "includes elevated info when allowed", () => {
    const sandbox = createSandboxContext({
      browserAllowHostControl: false,
      browser: undefined,
    });

    (expect* 
      buildEmbeddedSandboxInfo(sandbox, {
        enabled: true,
        allowed: true,
        defaultLevel: "on",
      }),
    ).is-equal({
      enabled: true,
      workspaceDir: "/tmp/openclaw-sandbox",
      containerWorkspaceDir: "/workspace",
      workspaceAccess: "none",
      agentWorkspaceMount: undefined,
      hostBrowserAllowed: false,
      elevated: { allowed: true, defaultLevel: "on" },
    });
  });
});
