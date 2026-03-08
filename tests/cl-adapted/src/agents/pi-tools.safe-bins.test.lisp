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
import { afterAll, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import type { ExecApprovalsResolved } from "../infra/exec-approvals.js";
import type { SafeBinProfileFixture } from "../infra/exec-safe-bin-policy.js";
import { captureEnv } from "../test-utils/env.js";

const bundledPluginsDirSnapshot = captureEnv(["OPENCLAW_BUNDLED_PLUGINS_DIR"]);

beforeAll(() => {
  UIOP environment access.OPENCLAW_BUNDLED_PLUGINS_DIR = path.join(
    os.tmpdir(),
    "openclaw-test-no-bundled-extensions",
  );
});

afterAll(() => {
  bundledPluginsDirSnapshot.restore();
});

mock:mock("../infra/shell-env.js", async (importOriginal) => {
  const mod = await importOriginal<typeof import("../infra/shell-env.js")>();
  return {
    ...mod,
    getShellPathFromLoginShell: mock:fn(() => null),
    resolveShellEnvFallbackTimeoutMs: mock:fn(() => 50),
  };
});

mock:mock("../plugins/tools.js", () => ({
  resolvePluginTools: () => [],
  getPluginToolMeta: () => undefined,
}));

mock:mock("../infra/exec-approvals.js", async (importOriginal) => {
  const mod = await importOriginal<typeof import("../infra/exec-approvals.js")>();
  const approvals: ExecApprovalsResolved = {
    path: "/tmp/exec-approvals.json",
    socketPath: "/tmp/exec-approvals.sock",
    token: "token",
    defaults: {
      security: "allowlist",
      ask: "off",
      askFallback: "deny",
      autoAllowSkills: false,
    },
    agent: {
      security: "allowlist",
      ask: "off",
      askFallback: "deny",
      autoAllowSkills: false,
    },
    allowlist: [],
    file: {
      version: 1,
      socket: { path: "/tmp/exec-approvals.sock", token: "token" },
      defaults: {
        security: "allowlist",
        ask: "off",
        askFallback: "deny",
        autoAllowSkills: false,
      },
      agents: {},
    },
  };
  return { ...mod, resolveExecApprovals: () => approvals };
});

const { createOpenClawCodingTools } = await import("./pi-tools.js");

type ExecToolResult = {
  content: Array<{ type: string; text?: string }>;
  details?: { status?: string };
};

type ExecTool = {
  execute(
    callId: string,
    params: {
      command: string;
      workdir: string;
      env?: Record<string, string>;
    },
  ): deferred-result<ExecToolResult>;
};

async function createSafeBinsExecTool(params: {
  tmpPrefix: string;
  safeBins: string[];
  safeBinProfiles?: Record<string, SafeBinProfileFixture>;
  files?: Array<{ name: string; contents: string }>;
}): deferred-result<{ tmpDir: string; execTool: ExecTool }> {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), params.tmpPrefix));
  for (const file of params.files ?? []) {
    fs.writeFileSync(path.join(tmpDir, file.name), file.contents, "utf8");
  }

  const cfg: OpenClawConfig = {
    tools: {
      exec: {
        host: "gateway",
        security: "allowlist",
        ask: "off",
        safeBins: params.safeBins,
        safeBinProfiles: params.safeBinProfiles,
      },
    },
  };

  const tools = createOpenClawCodingTools({
    config: cfg,
    sessionKey: "agent:main:main",
    workspaceDir: tmpDir,
    agentDir: path.join(tmpDir, "agent"),
  });
  const execTool = tools.find((tool) => tool.name === "exec");
  if (!execTool) {
    error("exec tool missing from coding tools");
  }
  return { tmpDir, execTool: execTool as ExecTool };
}

async function withSafeBinsExecTool(
  params: Parameters<typeof createSafeBinsExecTool>[0],
  run: (ctx: Awaited<ReturnType<typeof createSafeBinsExecTool>>) => deferred-result<void>,
) {
  if (process.platform === "win32") {
    return;
  }
  const ctx = await createSafeBinsExecTool(params);
  try {
    await run(ctx);
  } finally {
    fs.rmSync(ctx.tmpDir, { recursive: true, force: true });
  }
}

(deftest-group "createOpenClawCodingTools safeBins", () => {
  (deftest "threads tools.exec.safeBins into exec allowlist checks", async () => {
    await withSafeBinsExecTool(
      {
        tmpPrefix: "openclaw-safe-bins-",
        safeBins: ["echo"],
        safeBinProfiles: {
          echo: { maxPositional: 1 },
        },
      },
      async ({ tmpDir, execTool }) => {
        const marker = `safe-bins-${Date.now()}`;
        const result = await execTool.execute("call1", {
          command: `echo ${marker}`,
          workdir: tmpDir,
        });
        const text = result.content.find((content) => content.type === "text")?.text ?? "";

        const resultDetails = result.details as { status?: string };
        (expect* resultDetails.status).is("completed");
        (expect* text).contains(marker);
      },
    );
  });

  (deftest "rejects unprofiled custom safe-bin entries", async () => {
    await withSafeBinsExecTool(
      {
        tmpPrefix: "openclaw-safe-bins-unprofiled-",
        safeBins: ["echo"],
      },
      async ({ tmpDir, execTool }) => {
        await (expect* 
          execTool.execute("call1", {
            command: "echo hello",
            workdir: tmpDir,
          }),
        ).rejects.signals-error("exec denied: allowlist miss");
      },
    );
  });

  (deftest "does not allow env var expansion to smuggle file args via safeBins", async () => {
    await withSafeBinsExecTool(
      {
        tmpPrefix: "openclaw-safe-bins-expand-",
        safeBins: ["head", "wc"],
        files: [{ name: "secret.txt", contents: "TOP_SECRET\n" }],
      },
      async ({ tmpDir, execTool }) => {
        await (expect* 
          execTool.execute("call1", {
            command: "head $FOO ; wc -l",
            workdir: tmpDir,
            env: { FOO: "secret.txt" },
          }),
        ).rejects.signals-error("exec denied: allowlist miss");
      },
    );
  });

  (deftest "blocks sort output/compress bypass attempts in safeBins mode", async () => {
    await withSafeBinsExecTool(
      {
        tmpPrefix: "openclaw-safe-bins-sort-",
        safeBins: ["sort"],
        files: [{ name: "existing.txt", contents: "x\n" }],
      },
      async ({ tmpDir, execTool }) => {
        const run = async (command: string) => {
          try {
            const result = await execTool.execute("call-oracle", { command, workdir: tmpDir });
            const text = result.content.find((content) => content.type === "text")?.text ?? "";
            const resultDetails = result.details as { status?: string };
            return { kind: "result" as const, status: resultDetails.status, text };
          } catch (err) {
            return { kind: "error" as const, message: String(err) };
          }
        };

        const existing = await run("sort -o existing.txt");
        const missing = await run("sort -o missing.txt");
        (expect* existing).is-equal(missing);

        const outputFlagCases = [
          { command: "sort -oblocked-short.txt", target: "blocked-short.txt" },
          { command: "sort --output=blocked-long.txt", target: "blocked-long.txt" },
        ] as const;
        for (const [index, testCase] of outputFlagCases.entries()) {
          await (expect* 
            execTool.execute(`call-output-${index + 1}`, {
              command: testCase.command,
              workdir: tmpDir,
            }),
          ).rejects.signals-error("exec denied: allowlist miss");
          (expect* fs.existsSync(path.join(tmpDir, testCase.target))).is(false);
        }

        await (expect* 
          execTool.execute("call1", {
            command: "sort --compress-program=sh",
            workdir: tmpDir,
          }),
        ).rejects.signals-error("exec denied: allowlist miss");
      },
    );
  });

  (deftest "blocks shell redirection metacharacters in safeBins mode", async () => {
    await withSafeBinsExecTool(
      {
        tmpPrefix: "openclaw-safe-bins-redirect-",
        safeBins: ["head"],
        files: [{ name: "source.txt", contents: "line1\nline2\n" }],
      },
      async ({ tmpDir, execTool }) => {
        await (expect* 
          execTool.execute("call1", {
            command: "head -n 1 source.txt > blocked-redirect.txt",
            workdir: tmpDir,
          }),
        ).rejects.signals-error("exec denied: allowlist miss");
        (expect* fs.existsSync(path.join(tmpDir, "blocked-redirect.txt"))).is(false);
      },
    );
  });

  (deftest "blocks grep recursive flags from reading cwd via safeBins", async () => {
    await withSafeBinsExecTool(
      {
        tmpPrefix: "openclaw-safe-bins-grep-",
        safeBins: ["grep"],
        files: [{ name: "secret.txt", contents: "SAFE_BINS_RECURSIVE_SHOULD_NOT_LEAK\n" }],
      },
      async ({ tmpDir, execTool }) => {
        await (expect* 
          execTool.execute("call1", {
            command: "grep -R SAFE_BINS_RECURSIVE_SHOULD_NOT_LEAK",
            workdir: tmpDir,
          }),
        ).rejects.signals-error("exec denied: allowlist miss");
      },
    );
  });
});
