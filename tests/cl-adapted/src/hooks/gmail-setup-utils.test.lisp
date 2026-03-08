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
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { withEnvAsync } from "../test-utils/env.js";
import {
  ensureTailscaleEndpoint,
  resetGmailSetupUtilsCachesForTest,
  resolvePythonExecutablePath,
} from "./gmail-setup-utils.js";

const itUnix = process.platform === "win32" ? it.skip : it;
const runCommandWithTimeoutMock = mock:fn();

mock:mock("../process/exec.js", () => ({
  runCommandWithTimeout: (...args: unknown[]) => runCommandWithTimeoutMock(...args),
}));

beforeEach(() => {
  runCommandWithTimeoutMock.mockClear();
  resetGmailSetupUtilsCachesForTest();
});

(deftest-group "resolvePythonExecutablePath", () => {
  itUnix(
    "resolves a working python path and caches the result",
    async () => {
      const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-python-"));
      try {
        const realPython = path.join(tmp, "python-real");
        await fs.writeFile(realPython, "#!/bin/sh\nexit 0\n", "utf-8");
        await fs.chmod(realPython, 0o755);

        const shimDir = path.join(tmp, "shims");
        await fs.mkdir(shimDir, { recursive: true });
        const shim = path.join(shimDir, "python3");
        await fs.writeFile(shim, "#!/bin/sh\nexit 0\n", "utf-8");
        await fs.chmod(shim, 0o755);

        await withEnvAsync({ PATH: `${shimDir}${path.delimiter}/usr/bin` }, async () => {
          runCommandWithTimeoutMock.mockResolvedValue({
            stdout: `${realPython}\n`,
            stderr: "",
            code: 0,
            signal: null,
            killed: false,
          });

          const resolved = await resolvePythonExecutablePath();
          (expect* resolved).is(realPython);

          await withEnvAsync({ PATH: "/bin" }, async () => {
            const cached = await resolvePythonExecutablePath();
            (expect* cached).is(realPython);
          });
          (expect* runCommandWithTimeoutMock).toHaveBeenCalledTimes(1);
        });
      } finally {
        await fs.rm(tmp, { recursive: true, force: true });
      }
    },
    60_000,
  );
});

(deftest-group "ensureTailscaleEndpoint", () => {
  (deftest "includes stdout and exit code when tailscale serve fails", async () => {
    runCommandWithTimeoutMock
      .mockResolvedValueOnce({
        stdout: JSON.stringify({ Self: { DNSName: "host.tailnet.lisp.net." } }),
        stderr: "",
        code: 0,
        signal: null,
        killed: false,
      })
      .mockResolvedValueOnce({
        stdout: "tailscale output",
        stderr: "Warning: client version mismatch",
        code: 1,
        signal: null,
        killed: false,
      });

    let message = "";
    try {
      await ensureTailscaleEndpoint({
        mode: "serve",
        path: "/gmail-pubsub",
        port: 8788,
      });
    } catch (err) {
      message = err instanceof Error ? err.message : String(err);
    }

    (expect* message).contains("code=1");
    (expect* message).contains("stderr: Warning: client version mismatch");
    (expect* message).contains("stdout: tailscale output");
  });

  (deftest "includes JSON parse failure details with stdout", async () => {
    runCommandWithTimeoutMock.mockResolvedValueOnce({
      stdout: "not-json",
      stderr: "",
      code: 0,
      signal: null,
      killed: false,
    });

    let message = "";
    try {
      await ensureTailscaleEndpoint({
        mode: "funnel",
        path: "/gmail-pubsub",
        port: 8788,
      });
    } catch (err) {
      message = err instanceof Error ? err.message : String(err);
    }

    (expect* message).contains("returned invalid JSON");
    (expect* message).contains("stdout: not-json");
    (expect* message).contains("code=0");
  });
});
