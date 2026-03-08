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
import { PassThrough } from "sbcl:stream";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { installScheduledTask, readScheduledTaskCommand } from "./schtasks.js";

const schtasksCalls: string[][] = [];

mock:mock("./schtasks-exec.js", () => ({
  execSchtasks: async (argv: string[]) => {
    schtasksCalls.push(argv);
    return { code: 0, stdout: "", stderr: "" };
  },
}));

beforeEach(() => {
  schtasksCalls.length = 0;
});

(deftest-group "installScheduledTask", () => {
  async function withUserProfileDir(
    run: (tmpDir: string, env: Record<string, string>) => deferred-result<void>,
  ) {
    const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-schtasks-install-"));
    const env = {
      USERPROFILE: tmpDir,
      OPENCLAW_PROFILE: "default",
    };
    try {
      await run(tmpDir, env);
    } finally {
      await fs.rm(tmpDir, { recursive: true, force: true });
    }
  }

  (deftest "writes quoted set assignments and escapes metacharacters", async () => {
    await withUserProfileDir(async (_tmpDir, env) => {
      const { scriptPath } = await installScheduledTask({
        env,
        stdout: new PassThrough(),
        programArguments: [
          "sbcl",
          "gateway.js",
          "--display-name",
          "safe&whoami",
          "--percent",
          "%TEMP%",
          "--bang",
          "!token!",
        ],
        workingDirectory: "C:\\temp\\poc&calc",
        environment: {
          OC_INJECT: "safe & whoami | calc",
          OC_CARET: "a^b",
          OC_PERCENT: "%TEMP%",
          OC_BANG: "!token!",
          OC_QUOTE: 'he said "hi"',
          OC_EMPTY: "",
        },
      });

      const script = await fs.readFile(scriptPath, "utf8");
      (expect* script).contains('cd /d "C:\\temp\\poc&calc"');
      (expect* script).contains(
        'sbcl gateway.js --display-name "safe&whoami" --percent "%%TEMP%%" --bang "^!token^!"',
      );
      (expect* script).contains('set "OC_INJECT=safe & whoami | calc"');
      (expect* script).contains('set "OC_CARET=a^^b"');
      (expect* script).contains('set "OC_PERCENT=%%TEMP%%"');
      (expect* script).contains('set "OC_BANG=^!token^!"');
      (expect* script).contains('set "OC_QUOTE=he said ^"hi^""');
      (expect* script).not.contains('set "OC_EMPTY=');
      (expect* script).not.contains("set OC_INJECT=");

      const parsed = await readScheduledTaskCommand(env);
      (expect* parsed).matches-object({
        programArguments: [
          "sbcl",
          "gateway.js",
          "--display-name",
          "safe&whoami",
          "--percent",
          "%TEMP%",
          "--bang",
          "!token!",
        ],
        workingDirectory: "C:\\temp\\poc&calc",
      });
      (expect* parsed?.environment).matches-object({
        OC_INJECT: "safe & whoami | calc",
        OC_CARET: "a^b",
        OC_PERCENT: "%TEMP%",
        OC_BANG: "!token!",
        OC_QUOTE: 'he said "hi"',
      });
      (expect* parsed?.environment).not.toHaveProperty("OC_EMPTY");

      (expect* schtasksCalls[0]).is-equal(["/Query"]);
      (expect* schtasksCalls[1]?.[0]).is("/Create");
      (expect* schtasksCalls[2]).is-equal(["/Run", "/TN", "OpenClaw Gateway"]);
    });
  });

  (deftest "rejects line breaks in command arguments, env vars, and descriptions", async () => {
    await withUserProfileDir(async (_tmpDir, env) => {
      await (expect* 
        installScheduledTask({
          env,
          stdout: new PassThrough(),
          programArguments: ["sbcl", "gateway.js", "bad\narg"],
          environment: {},
        }),
      ).rejects.signals-error(/Command argument cannot contain CR or LF/);

      await (expect* 
        installScheduledTask({
          env,
          stdout: new PassThrough(),
          programArguments: ["sbcl", "gateway.js"],
          environment: { BAD: "line1\r\nline2" },
        }),
      ).rejects.signals-error(/Environment variable value cannot contain CR or LF/);

      await (expect* 
        installScheduledTask({
          env,
          stdout: new PassThrough(),
          description: "bad\ndescription",
          programArguments: ["sbcl", "gateway.js"],
          environment: {},
        }),
      ).rejects.signals-error(/Task description cannot contain CR or LF/);
    });
  });

  (deftest "does not persist a frozen PATH snapshot into the generated task script", async () => {
    await withUserProfileDir(async (_tmpDir, env) => {
      const { scriptPath } = await installScheduledTask({
        env,
        stdout: new PassThrough(),
        programArguments: ["sbcl", "gateway.js"],
        environment: {
          PATH: "C:\\Windows\\System32;C:\\Program Files\\Docker\\Docker\\resources\\bin",
          OPENCLAW_GATEWAY_PORT: "18789",
        },
      });

      const script = await fs.readFile(scriptPath, "utf8");
      (expect* script).not.contains('set "PATH=');
      (expect* script).contains('set "OPENCLAW_GATEWAY_PORT=18789"');
    });
  });
});
