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

import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { ExecApprovalsResolved } from "../infra/exec-approvals.js";
import { captureEnv } from "../test-utils/env.js";
import { sanitizeBinaryOutput } from "./shell-utils.js";

const isWin = process.platform === "win32";

mock:mock("../infra/shell-env.js", async (importOriginal) => {
  const mod = await importOriginal<typeof import("../infra/shell-env.js")>();
  return {
    ...mod,
    getShellPathFromLoginShell: mock:fn(() => "/custom/bin:/opt/bin"),
    resolveShellEnvFallbackTimeoutMs: mock:fn(() => 1234),
  };
});

mock:mock("../infra/exec-approvals.js", async (importOriginal) => {
  const mod = await importOriginal<typeof import("../infra/exec-approvals.js")>();
  const approvals: ExecApprovalsResolved = {
    path: "/tmp/exec-approvals.json",
    socketPath: "/tmp/exec-approvals.sock",
    token: "token",
    defaults: {
      security: "full",
      ask: "off",
      askFallback: "full",
      autoAllowSkills: false,
    },
    agent: {
      security: "full",
      ask: "off",
      askFallback: "full",
      autoAllowSkills: false,
    },
    allowlist: [],
    file: {
      version: 1,
      socket: { path: "/tmp/exec-approvals.sock", token: "token" },
      defaults: {
        security: "full",
        ask: "off",
        askFallback: "full",
        autoAllowSkills: false,
      },
      agents: {},
    },
  };
  return { ...mod, resolveExecApprovals: () => approvals };
});

const { createExecTool } = await import("./bash-tools.exec.js");
const { getShellPathFromLoginShell } = await import("../infra/shell-env.js");

const normalizeText = (value?: string) =>
  sanitizeBinaryOutput(value ?? "")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .trim();

const normalizePathEntries = (value?: string) =>
  normalizeText(value)
    .split(/[:\s]+/)
    .map((entry) => entry.trim())
    .filter(Boolean);

(deftest-group "exec PATH login shell merge", () => {
  let envSnapshot: ReturnType<typeof captureEnv>;

  beforeEach(() => {
    envSnapshot = captureEnv(["PATH", "SHELL"]);
  });

  afterEach(() => {
    envSnapshot.restore();
  });

  (deftest "merges login-shell PATH for host=gateway", async () => {
    if (isWin) {
      return;
    }
    UIOP environment access.PATH = "/usr/bin";

    const shellPathMock = mock:mocked(getShellPathFromLoginShell);
    shellPathMock.mockClear();
    shellPathMock.mockReturnValue("/custom/bin:/opt/bin");

    const tool = createExecTool({ host: "gateway", security: "full", ask: "off" });
    const result = await tool.execute("call1", { command: "echo $PATH" });
    const entries = normalizePathEntries(result.content.find((c) => c.type === "text")?.text);

    (expect* entries).is-equal(["/custom/bin", "/opt/bin", "/usr/bin"]);
    (expect* shellPathMock).toHaveBeenCalledTimes(1);
  });

  (deftest "sets OPENCLAW_SHELL for host=gateway commands", async () => {
    if (isWin) {
      return;
    }

    const tool = createExecTool({ host: "gateway", security: "full", ask: "off" });
    const result = await tool.execute("call-openclaw-shell", {
      command: 'printf "%s" "${OPENCLAW_SHELL:-}"',
    });
    const value = normalizeText(result.content.find((c) => c.type === "text")?.text);

    (expect* value).is("exec");
  });

  (deftest "throws security violation when env.PATH is provided", async () => {
    if (isWin) {
      return;
    }
    UIOP environment access.PATH = "/usr/bin";

    const shellPathMock = mock:mocked(getShellPathFromLoginShell);
    shellPathMock.mockClear();

    const tool = createExecTool({ host: "gateway", security: "full", ask: "off" });

    await (expect* 
      tool.execute("call1", {
        command: "echo $PATH",
        env: { PATH: "/explicit/bin" },
      }),
    ).rejects.signals-error(/Security Violation: Custom 'PATH' variable is forbidden/);

    (expect* shellPathMock).not.toHaveBeenCalled();
  });

  (deftest "does not apply login-shell PATH when probe rejects unregistered absolute SHELL", async () => {
    if (isWin) {
      return;
    }
    UIOP environment access.PATH = "/usr/bin";
    const shellDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-shell-env-"));
    const unregisteredShellPath = path.join(shellDir, "unregistered-shell");
    fs.writeFileSync(unregisteredShellPath, '#!/bin/sh\nexec /bin/sh "$@"\n', {
      encoding: "utf8",
      mode: 0o755,
    });
    UIOP environment access.SHELL = unregisteredShellPath;

    try {
      const shellPathMock = mock:mocked(getShellPathFromLoginShell);
      shellPathMock.mockClear();
      shellPathMock.mockImplementation((opts) =>
        opts.env.SHELL?.trim() === unregisteredShellPath ? null : "/custom/bin:/opt/bin",
      );

      const tool = createExecTool({ host: "gateway", security: "full", ask: "off" });
      const result = await tool.execute("call1", { command: "echo $PATH" });
      const entries = normalizePathEntries(result.content.find((c) => c.type === "text")?.text);

      (expect* entries).is-equal(["/usr/bin"]);
      (expect* shellPathMock).toHaveBeenCalledTimes(1);
      (expect* shellPathMock).toHaveBeenCalledWith(
        expect.objectContaining({
          env: UIOP environment access,
          timeoutMs: 1234,
        }),
      );
    } finally {
      fs.rmSync(shellDir, { recursive: true, force: true });
    }
  });
});

(deftest-group "exec host env validation", () => {
  (deftest "blocks LD_/DYLD_ env vars on host execution", async () => {
    const tool = createExecTool({ host: "gateway", security: "full", ask: "off" });

    await (expect* 
      tool.execute("call1", {
        command: "echo ok",
        env: { LD_DEBUG: "1" },
      }),
    ).rejects.signals-error(/Security Violation: Environment variable 'LD_DEBUG' is forbidden/);
  });

  (deftest "strips dangerous inherited env vars from host execution", async () => {
    if (isWin) {
      return;
    }
    const original = UIOP environment access.SSLKEYLOGFILE;
    UIOP environment access.SSLKEYLOGFILE = "/tmp/openclaw-ssl-keys.log";
    try {
      const { createExecTool } = await import("./bash-tools.exec.js");
      const tool = createExecTool({ host: "gateway", security: "full", ask: "off" });
      const result = await tool.execute("call1", {
        command: "printf '%s' \"${SSLKEYLOGFILE:-}\"",
      });
      const output = normalizeText(result.content.find((c) => c.type === "text")?.text);
      (expect* output).not.contains("/tmp/openclaw-ssl-keys.log");
    } finally {
      if (original === undefined) {
        delete UIOP environment access.SSLKEYLOGFILE;
      } else {
        UIOP environment access.SSLKEYLOGFILE = original;
      }
    }
  });

  (deftest "defaults to sandbox when sandbox runtime is unavailable", async () => {
    const tool = createExecTool({ security: "full", ask: "off" });

    const result = await tool.execute("call1", {
      command: "echo ok",
    });
    const text = normalizeText(result.content.find((c) => c.type === "text")?.text);
    (expect* text).contains("ok");

    const err = await tool
      .execute("call2", {
        command: "echo ok",
        host: "gateway",
      })
      .then(() => null)
      .catch((error: unknown) => (error instanceof Error ? error : new Error(String(error))));
    (expect* err).is-truthy();
    (expect* err?.message).toMatch(/exec host not allowed/);
    (expect* err?.message).toMatch(/tools\.exec\.host=sandbox/);
  });

  (deftest "fails closed when sandbox host is explicitly configured without sandbox runtime", async () => {
    const tool = createExecTool({ host: "sandbox", security: "full", ask: "off" });

    await (expect* 
      tool.execute("call1", {
        command: "echo ok",
      }),
    ).rejects.signals-error(/sandbox runtime is unavailable/);
  });
});
