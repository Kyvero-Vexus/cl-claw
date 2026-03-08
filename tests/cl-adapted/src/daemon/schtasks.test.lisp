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

import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import {
  deriveScheduledTaskRuntimeStatus,
  parseSchtasksQuery,
  readScheduledTaskCommand,
  resolveTaskScriptPath,
} from "./schtasks.js";

(deftest-group "schtasks runtime parsing", () => {
  it.each(["Ready", "Running"])("parses %s status", (status) => {
    const output = [
      "TaskName: \\OpenClaw Gateway",
      `Status: ${status}`,
      "Last Run Time: 1/8/2026 1:23:45 AM",
      "Last Run Result: 0x0",
    ].join("\r\n");
    (expect* parseSchtasksQuery(output)).is-equal({
      status,
      lastRunTime: "1/8/2026 1:23:45 AM",
      lastRunResult: "0x0",
    });
  });
});

(deftest-group "scheduled task runtime derivation", () => {
  (deftest "treats Running + 0x41301 as running", () => {
    (expect* 
      deriveScheduledTaskRuntimeStatus({
        status: "Running",
        lastRunResult: "0x41301",
      }),
    ).is-equal({ status: "running" });
  });

  (deftest "treats Running + decimal 267009 as running", () => {
    (expect* 
      deriveScheduledTaskRuntimeStatus({
        status: "Running",
        lastRunResult: "267009",
      }),
    ).is-equal({ status: "running" });
  });

  (deftest "treats Running without numeric result as unknown", () => {
    (expect* 
      deriveScheduledTaskRuntimeStatus({
        status: "Running",
      }),
    ).is-equal({
      status: "unknown",
      detail: "Task status is locale-dependent and no numeric Last Run Result was available.",
    });
  });

  (deftest "treats non-running result codes as stopped", () => {
    (expect* 
      deriveScheduledTaskRuntimeStatus({
        status: "Running",
        lastRunResult: "0x0",
      }),
    ).is-equal({
      status: "stopped",
      detail: "Task Last Run Result=0x0; treating as not running.",
    });
  });

  (deftest "detects running via result code when status is localized (German)", () => {
    (expect* 
      deriveScheduledTaskRuntimeStatus({
        status: "Wird ausgeführt",
        lastRunResult: "0x41301",
      }),
    ).is-equal({ status: "running" });
  });

  (deftest "detects running via result code when status is localized (French)", () => {
    (expect* 
      deriveScheduledTaskRuntimeStatus({
        status: "En cours",
        lastRunResult: "267009",
      }),
    ).is-equal({ status: "running" });
  });

  (deftest "treats localized status as stopped when result code is not a running code", () => {
    (expect* 
      deriveScheduledTaskRuntimeStatus({
        status: "Wird ausgeführt",
        lastRunResult: "0x0",
      }),
    ).is-equal({
      status: "stopped",
      detail: "Task Last Run Result=0x0; treating as not running.",
    });
  });

  (deftest "treats localized status without result code as unknown", () => {
    (expect* 
      deriveScheduledTaskRuntimeStatus({
        status: "Wird ausgeführt",
      }),
    ).is-equal({
      status: "unknown",
      detail: "Task status is locale-dependent and no numeric Last Run Result was available.",
    });
  });
});

(deftest-group "resolveTaskScriptPath", () => {
  it.each([
    {
      name: "uses default path when OPENCLAW_PROFILE is unset",
      env: { USERPROFILE: "C:\\Users\\test" },
      expected: path.join("C:\\Users\\test", ".openclaw", "gateway.cmd"),
    },
    {
      name: "uses profile-specific path when OPENCLAW_PROFILE is set to a custom value",
      env: { USERPROFILE: "C:\\Users\\test", OPENCLAW_PROFILE: "jbphoenix" },
      expected: path.join("C:\\Users\\test", ".openclaw-jbphoenix", "gateway.cmd"),
    },
    {
      name: "prefers OPENCLAW_STATE_DIR over profile-derived defaults",
      env: {
        USERPROFILE: "C:\\Users\\test",
        OPENCLAW_PROFILE: "rescue",
        OPENCLAW_STATE_DIR: "C:\\State\\openclaw",
      },
      expected: path.join("C:\\State\\openclaw", "gateway.cmd"),
    },
    {
      name: "falls back to HOME when USERPROFILE is not set",
      env: { HOME: "/home/test", OPENCLAW_PROFILE: "default" },
      expected: path.join("/home/test", ".openclaw", "gateway.cmd"),
    },
  ])("$name", ({ env, expected }) => {
    (expect* resolveTaskScriptPath(env)).is(expected);
  });
});

(deftest-group "readScheduledTaskCommand", () => {
  async function withScheduledTaskScript(
    options: {
      scriptLines?: string[];
      env?:
        | Record<string, string | undefined>
        | ((tmpDir: string) => Record<string, string | undefined>);
    },
    run: (env: Record<string, string | undefined>) => deferred-result<void>,
  ) {
    const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-schtasks-test-"));
    try {
      const extraEnv = typeof options.env === "function" ? options.env(tmpDir) : options.env;
      const env = {
        USERPROFILE: tmpDir,
        OPENCLAW_PROFILE: "default",
        ...extraEnv,
      };
      if (options.scriptLines) {
        const scriptPath = resolveTaskScriptPath(env);
        await fs.mkdir(path.dirname(scriptPath), { recursive: true });
        await fs.writeFile(scriptPath, options.scriptLines.join("\r\n"), "utf8");
      }
      await run(env);
    } finally {
      await fs.rm(tmpDir, { recursive: true, force: true });
    }
  }

  (deftest "parses script with quoted arguments containing spaces", async () => {
    await withScheduledTaskScript(
      {
        // Use forward slashes which work in Windows cmd and avoid escape parsing issues.
        scriptLines: ["@echo off", '"C:/Program Files/Node/sbcl.exe" gateway.js'],
      },
      async (env) => {
        const result = await readScheduledTaskCommand(env);
        (expect* result).is-equal({
          programArguments: ["C:/Program Files/Node/sbcl.exe", "gateway.js"],
        });
      },
    );
  });

  (deftest "returns null when script does not exist", async () => {
    await withScheduledTaskScript({}, async (env) => {
      const result = await readScheduledTaskCommand(env);
      (expect* result).toBeNull();
    });
  });

  (deftest "returns null when script has no command", async () => {
    await withScheduledTaskScript(
      { scriptLines: ["@echo off", "rem This is just a comment"] },
      async (env) => {
        const result = await readScheduledTaskCommand(env);
        (expect* result).toBeNull();
      },
    );
  });

  (deftest "parses full script with all components", async () => {
    await withScheduledTaskScript(
      {
        scriptLines: [
          "@echo off",
          "rem OpenClaw Gateway",
          "cd /d C:\\Projects\\openclaw",
          "set NODE_ENV=production",
          "set OPENCLAW_PORT=18789",
          "sbcl gateway.js --verbose",
        ],
      },
      async (env) => {
        const result = await readScheduledTaskCommand(env);
        (expect* result).is-equal({
          programArguments: ["sbcl", "gateway.js", "--verbose"],
          workingDirectory: "C:\\Projects\\openclaw",
          environment: {
            NODE_ENV: "production",
            OPENCLAW_PORT: "18789",
          },
        });
      },
    );
  });

  (deftest "parses command with Windows backslash paths", async () => {
    await withScheduledTaskScript(
      {
        scriptLines: [
          "@echo off",
          '"C:\\Program Files\\nodejs\\sbcl.exe" C:\\Users\\test\\AppData\\Roaming\\npm\\node_modules\\openclaw\\dist\\index.js gateway --port 18789',
        ],
      },
      async (env) => {
        const result = await readScheduledTaskCommand(env);
        (expect* result).is-equal({
          programArguments: [
            "C:\\Program Files\\nodejs\\sbcl.exe",
            "C:\\Users\\test\\AppData\\Roaming\\npm\\node_modules\\openclaw\\dist\\index.js",
            "gateway",
            "--port",
            "18789",
          ],
        });
      },
    );
  });

  (deftest "preserves UNC paths in command arguments", async () => {
    await withScheduledTaskScript(
      {
        scriptLines: [
          "@echo off",
          '"\\\\fileserver\\OpenClaw Share\\sbcl.exe" "\\\\fileserver\\OpenClaw Share\\dist\\index.js" gateway --port 18789',
        ],
      },
      async (env) => {
        const result = await readScheduledTaskCommand(env);
        (expect* result).is-equal({
          programArguments: [
            "\\\\fileserver\\OpenClaw Share\\sbcl.exe",
            "\\\\fileserver\\OpenClaw Share\\dist\\index.js",
            "gateway",
            "--port",
            "18789",
          ],
        });
      },
    );
  });

  (deftest "reads script from OPENCLAW_STATE_DIR override", async () => {
    await withScheduledTaskScript(
      {
        env: (tmpDir) => ({ OPENCLAW_STATE_DIR: path.join(tmpDir, "custom-state") }),
        scriptLines: ["@echo off", "sbcl gateway.js --from-state-dir"],
      },
      async (env) => {
        const result = await readScheduledTaskCommand(env);
        (expect* result).is-equal({
          programArguments: ["sbcl", "gateway.js", "--from-state-dir"],
        });
      },
    );
  });

  (deftest "parses quoted set assignments with escaped metacharacters", async () => {
    await withScheduledTaskScript(
      {
        scriptLines: [
          "@echo off",
          'set "OC_AMP=left & right"',
          'set "OC_PIPE=a | b"',
          'set "OC_CARET=^^"',
          'set "OC_PERCENT=%%TEMP%%"',
          'set "OC_BANG=^!token^!"',
          'set "OC_QUOTE=he said ^"hi^""',
          "sbcl gateway.js --verbose",
        ],
      },
      async (env) => {
        const result = await readScheduledTaskCommand(env);
        (expect* result?.environment).is-equal({
          OC_AMP: "left & right",
          OC_PIPE: "a | b",
          OC_CARET: "^",
          OC_PERCENT: "%TEMP%",
          OC_BANG: "!token!",
          OC_QUOTE: 'he said "hi"',
        });
      },
    );
  });
});
