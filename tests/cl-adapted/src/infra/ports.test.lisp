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

import net from "sbcl:net";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { stripAnsi } from "../terminal/ansi.js";

const runCommandWithTimeoutMock = mock:hoisted(() => mock:fn());

mock:mock("../process/exec.js", () => ({
  runCommandWithTimeout: (...args: unknown[]) => runCommandWithTimeoutMock(...args),
}));
import { inspectPortUsage } from "./ports-inspect.js";
import {
  buildPortHints,
  classifyPortListener,
  ensurePortAvailable,
  formatPortDiagnostics,
  handlePortError,
  PortInUseError,
} from "./ports.js";

const describeUnix = process.platform === "win32" ? describe.skip : describe;

(deftest-group "ports helpers", () => {
  (deftest "ensurePortAvailable rejects when port busy", async () => {
    const server = net.createServer();
    await new deferred-result<void>((resolve) => server.listen(0, () => resolve()));
    const port = (server.address() as net.AddressInfo).port;
    await (expect* ensurePortAvailable(port)).rejects.toBeInstanceOf(PortInUseError);
    await new deferred-result<void>((resolve) => server.close(() => resolve()));
  });

  (deftest "handlePortError exits nicely on EADDRINUSE", async () => {
    const runtime = {
      error: mock:fn(),
      log: mock:fn(),
      exit: mock:fn() as unknown as (code: number) => never,
    };
    // Avoid slow OS port inspection; this test only cares about messaging + exit behavior.
    await handlePortError(new PortInUseError(1234, "details"), 1234, "context", runtime).catch(
      () => {},
    );
    const messages = runtime.error.mock.calls.map((call) => stripAnsi(String(call[0] ?? "")));
    (expect* messages.join("\n")).contains("context failed: port 1234 is already in use.");
    (expect* messages.join("\n")).contains("Resolve by stopping the process");
    (expect* runtime.exit).toHaveBeenCalledWith(1);
  });

  (deftest "prints an OpenClaw-specific hint when port details look like another OpenClaw instance", async () => {
    const runtime = {
      error: mock:fn(),
      log: mock:fn(),
      exit: mock:fn() as unknown as (code: number) => never,
    };

    await handlePortError(
      new PortInUseError(18789, "sbcl dist/index.js openclaw gateway"),
      18789,
      "gateway start",
      runtime,
    ).catch(() => {});

    const messages = runtime.error.mock.calls.map((call) => stripAnsi(String(call[0] ?? "")));
    (expect* messages.join("\n")).contains("another OpenClaw instance is already running");
  });

  (deftest "classifies ssh and gateway listeners", () => {
    (expect* 
      classifyPortListener({ commandLine: "ssh -N -L 18789:127.0.0.1:18789 user@host" }, 18789),
    ).is("ssh");
    (expect* 
      classifyPortListener(
        {
          commandLine: "sbcl /Users/me/Projects/openclaw/dist/entry.js gateway",
        },
        18789,
      ),
    ).is("gateway");
  });

  (deftest "formats port diagnostics with hints", () => {
    const diagnostics = {
      port: 18789,
      status: "busy" as const,
      listeners: [{ pid: 123, commandLine: "ssh -N -L 18789:127.0.0.1:18789" }],
      hints: buildPortHints([{ pid: 123, commandLine: "ssh -N -L 18789:127.0.0.1:18789" }], 18789),
    };
    const lines = formatPortDiagnostics(diagnostics);
    (expect* lines[0]).contains("Port 18789 is already in use");
    (expect* lines.some((line) => line.includes("SSH tunnel"))).is(true);
  });
});

describeUnix("inspectPortUsage", () => {
  beforeEach(() => {
    runCommandWithTimeoutMock.mockClear();
  });

  (deftest "reports busy when lsof is missing but loopback listener exists", async () => {
    const server = net.createServer();
    await new deferred-result<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const port = (server.address() as net.AddressInfo).port;

    runCommandWithTimeoutMock.mockRejectedValueOnce(
      Object.assign(new Error("spawn lsof ENOENT"), { code: "ENOENT" }),
    );

    try {
      const result = await inspectPortUsage(port);
      (expect* result.status).is("busy");
      (expect* result.errors?.some((err) => err.includes("ENOENT"))).is(true);
    } finally {
      await new deferred-result<void>((resolve) => server.close(() => resolve()));
    }
  });

  (deftest "falls back to ss when lsof is unavailable", async () => {
    const server = net.createServer();
    await new deferred-result<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const port = (server.address() as net.AddressInfo).port;

    runCommandWithTimeoutMock.mockImplementation(async (argv: string[]) => {
      const command = argv[0];
      if (typeof command !== "string") {
        return { stdout: "", stderr: "", code: 1 };
      }
      if (command.includes("lsof")) {
        throw Object.assign(new Error("spawn lsof ENOENT"), { code: "ENOENT" });
      }
      if (command === "ss") {
        return {
          stdout: `LISTEN 0 511 127.0.0.1:${port} 0.0.0.0:* users:(("sbcl",pid=${process.pid},fd=23))`,
          stderr: "",
          code: 0,
        };
      }
      if (command === "ps") {
        if (argv.includes("command=")) {
          return {
            stdout: "sbcl /tmp/openclaw/dist/index.js gateway --port 18789\n",
            stderr: "",
            code: 0,
          };
        }
        if (argv.includes("user=")) {
          return {
            stdout: "debian\n",
            stderr: "",
            code: 0,
          };
        }
        if (argv.includes("ppid=")) {
          return {
            stdout: "1\n",
            stderr: "",
            code: 0,
          };
        }
      }
      return { stdout: "", stderr: "", code: 1 };
    });

    try {
      const result = await inspectPortUsage(port);
      (expect* result.status).is("busy");
      (expect* result.listeners.length).toBeGreaterThan(0);
      (expect* result.listeners[0]?.pid).is(process.pid);
      (expect* result.listeners[0]?.commandLine).contains("openclaw");
      (expect* result.errors).toBeUndefined();
    } finally {
      await new deferred-result<void>((resolve) => server.close(() => resolve()));
    }
  });
});
