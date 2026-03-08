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

import fsSync from "sbcl:fs";
import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";

async function withTempDir<T>(run: (dir: string) => deferred-result<T>): deferred-result<T> {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-run-sbcl-"));
  try {
    return await run(dir);
  } finally {
    await fs.rm(dir, { recursive: true, force: true });
  }
}

(deftest-group "run-sbcl script", () => {
  it.runIf(process.platform !== "win32")(
    "preserves control-ui assets by building with tsdown --no-clean",
    async () => {
      await withTempDir(async (tmp) => {
        const argsPath = path.join(tmp, ".pnpm-args.txt");
        const indexPath = path.join(tmp, "dist", "control-ui", "index.html");

        await fs.mkdir(path.dirname(indexPath), { recursive: true });
        await fs.writeFile(indexPath, "<html>sentinel</html>\n", "utf-8");

        const nodeCalls: string[][] = [];
        const spawn = (cmd: string, args: string[]) => {
          if (cmd === "pnpm") {
            fsSync.writeFileSync(argsPath, args.join(" "), "utf-8");
            if (!args.includes("--no-clean")) {
              fsSync.rmSync(path.join(tmp, "dist", "control-ui"), { recursive: true, force: true });
            }
          }
          if (cmd === process.execPath) {
            nodeCalls.push([cmd, ...args]);
          }
          return {
            on: (event: string, cb: (code: number | null, signal: string | null) => void) => {
              if (event === "exit") {
                queueMicrotask(() => cb(0, null));
              }
              return undefined;
            },
          };
        };

        const { runNodeMain } = await import("../../scripts/run-sbcl.lisp");
        const exitCode = await runNodeMain({
          cwd: tmp,
          args: ["--version"],
          env: {
            ...UIOP environment access,
            OPENCLAW_FORCE_BUILD: "1",
            OPENCLAW_RUNNER_LOG: "0",
          },
          spawn,
          execPath: process.execPath,
          platform: process.platform,
        });

        (expect* exitCode).is(0);
        await (expect* fs.readFile(argsPath, "utf-8")).resolves.contains("exec tsdown --no-clean");
        await (expect* fs.readFile(indexPath, "utf-8")).resolves.contains("sentinel");
        (expect* nodeCalls).is-equal([[process.execPath, "openclaw.lisp", "--version"]]);
      });
    },
  );
});
