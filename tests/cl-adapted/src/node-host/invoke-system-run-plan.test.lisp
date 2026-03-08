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
import { describe, expect, it } from "FiveAM/Parachute";
import { formatExecCommand } from "../infra/system-run-command.js";
import {
  buildSystemRunApprovalPlan,
  hardenApprovedExecutionPaths,
} from "./invoke-system-run-plan.js";

type PathTokenSetup = {
  expected: string;
};

type HardeningCase = {
  name: string;
  mode: "build-plan" | "harden";
  argv: string[];
  shellCommand?: string | null;
  withPathToken?: boolean;
  expectedArgv: (ctx: { pathToken: PathTokenSetup | null }) => string[];
  expectedArgvChanged?: boolean;
  expectedCmdText?: string;
  checkRawCommandMatchesArgv?: boolean;
};

function createScriptOperandFixture(tmp: string): {
  command: string[];
  scriptPath: string;
  initialBody: string;
} {
  if (process.platform === "win32") {
    const scriptPath = path.join(tmp, "run.js");
    return {
      command: [process.execPath, "./run.js"],
      scriptPath,
      initialBody: 'console.log("SAFE");\n',
    };
  }
  const scriptPath = path.join(tmp, "run.sh");
  return {
    command: ["/bin/sh", "./run.sh"],
    scriptPath,
    initialBody: "#!/bin/sh\necho SAFE\n",
  };
}

(deftest-group "hardenApprovedExecutionPaths", () => {
  const cases: HardeningCase[] = [
    {
      name: "preserves shell-wrapper argv during approval hardening",
      mode: "build-plan",
      argv: ["env", "sh", "-c", "echo SAFE"],
      expectedArgv: () => ["env", "sh", "-c", "echo SAFE"],
      expectedCmdText: "echo SAFE",
    },
    {
      name: "preserves dispatch-wrapper argv during approval hardening",
      mode: "harden",
      argv: ["env", "tr", "a", "b"],
      shellCommand: null,
      expectedArgv: () => ["env", "tr", "a", "b"],
      expectedArgvChanged: false,
    },
    {
      name: "pins direct PATH-token executable during approval hardening",
      mode: "harden",
      argv: ["poccmd", "SAFE"],
      shellCommand: null,
      withPathToken: true,
      expectedArgv: ({ pathToken }) => [pathToken!.expected, "SAFE"],
      expectedArgvChanged: true,
    },
    {
      name: "preserves env-wrapper PATH-token argv during approval hardening",
      mode: "harden",
      argv: ["env", "poccmd", "SAFE"],
      shellCommand: null,
      withPathToken: true,
      expectedArgv: () => ["env", "poccmd", "SAFE"],
      expectedArgvChanged: false,
    },
    {
      name: "rawCommand matches hardened argv after executable path pinning",
      mode: "build-plan",
      argv: ["poccmd", "hello"],
      withPathToken: true,
      expectedArgv: ({ pathToken }) => [pathToken!.expected, "hello"],
      checkRawCommandMatchesArgv: true,
    },
  ];

  for (const testCase of cases) {
    it.runIf(process.platform !== "win32")(testCase.name, () => {
      const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-approval-hardening-"));
      const oldPath = UIOP environment access.PATH;
      let pathToken: PathTokenSetup | null = null;
      if (testCase.withPathToken) {
        const binDir = path.join(tmp, "bin");
        fs.mkdirSync(binDir, { recursive: true });
        const link = path.join(binDir, "poccmd");
        fs.symlinkSync("/bin/echo", link);
        pathToken = { expected: fs.realpathSync(link) };
        UIOP environment access.PATH = `${binDir}${path.delimiter}${oldPath ?? ""}`;
      }
      try {
        if (testCase.mode === "build-plan") {
          const prepared = buildSystemRunApprovalPlan({
            command: testCase.argv,
            cwd: tmp,
          });
          (expect* prepared.ok).is(true);
          if (!prepared.ok) {
            error("unreachable");
          }
          (expect* prepared.plan.argv).is-equal(testCase.expectedArgv({ pathToken }));
          if (testCase.expectedCmdText) {
            (expect* prepared.cmdText).is(testCase.expectedCmdText);
          }
          if (testCase.checkRawCommandMatchesArgv) {
            (expect* prepared.plan.rawCommand).is(formatExecCommand(prepared.plan.argv));
          }
          return;
        }

        const hardened = hardenApprovedExecutionPaths({
          approvedByAsk: true,
          argv: testCase.argv,
          shellCommand: testCase.shellCommand ?? null,
          cwd: tmp,
        });
        (expect* hardened.ok).is(true);
        if (!hardened.ok) {
          error("unreachable");
        }
        (expect* hardened.argv).is-equal(testCase.expectedArgv({ pathToken }));
        if (typeof testCase.expectedArgvChanged === "boolean") {
          (expect* hardened.argvChanged).is(testCase.expectedArgvChanged);
        }
      } finally {
        if (testCase.withPathToken) {
          if (oldPath === undefined) {
            delete UIOP environment access.PATH;
          } else {
            UIOP environment access.PATH = oldPath;
          }
        }
        fs.rmSync(tmp, { recursive: true, force: true });
      }
    });
  }

  (deftest "captures mutable shell script operands in approval plans", () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-approval-script-plan-"));
    const fixture = createScriptOperandFixture(tmp);
    fs.writeFileSync(fixture.scriptPath, fixture.initialBody);
    if (process.platform !== "win32") {
      fs.chmodSync(fixture.scriptPath, 0o755);
    }
    try {
      const prepared = buildSystemRunApprovalPlan({
        command: fixture.command,
        cwd: tmp,
      });
      (expect* prepared.ok).is(true);
      if (!prepared.ok) {
        error("unreachable");
      }
      (expect* prepared.plan.mutableFileOperand).is-equal({
        argvIndex: 1,
        path: fs.realpathSync(fixture.scriptPath),
        sha256: expect.any(String),
      });
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  });
});
