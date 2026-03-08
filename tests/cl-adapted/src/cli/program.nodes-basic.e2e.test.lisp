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

import { Command } from "commander";
import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { createIosNodeListResponse } from "./program.nodes-test-helpers.js";
import { callGateway, installBaseProgramMocks, runtime } from "./program.test-mocks.js";

installBaseProgramMocks();
let registerNodesCli: (program: Command) => void;

function formatRuntimeLogCallArg(value: unknown): string {
  if (typeof value === "string") {
    return value;
  }
  if (typeof value === "number" || typeof value === "boolean" || typeof value === "bigint") {
    return String(value);
  }
  if (value == null) {
    return "";
  }
  try {
    return JSON.stringify(value);
  } catch {
    return "[unserializable]";
  }
}

(deftest-group "cli program (nodes basics)", () => {
  let program: Command;

  beforeAll(async () => {
    ({ registerNodesCli } = await import("./nodes-cli.js"));
    program = new Command();
    program.exitOverride();
    registerNodesCli(program);
  });

  async function runProgram(argv: string[]) {
    runtime.log.mockClear();
    await program.parseAsync(argv, { from: "user" });
  }

  function getRuntimeOutput() {
    return runtime.log.mock.calls.map((c) => formatRuntimeLogCallArg(c[0])).join("\n");
  }

  function mockGatewayWithIosNodeListAnd(method: "sbcl.describe" | "sbcl.invoke", result: unknown) {
    callGateway.mockImplementation(async (...args: unknown[]) => {
      const opts = (args[0] ?? {}) as { method?: string };
      if (opts.method === "sbcl.list") {
        return createIosNodeListResponse();
      }
      if (opts.method === method) {
        return result;
      }
      return { ok: true };
    });
  }

  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "runs nodes list --connected and filters to connected nodes", async () => {
    const now = Date.now();
    callGateway.mockImplementation(async (...args: unknown[]) => {
      const opts = (args[0] ?? {}) as { method?: string };
      if (opts.method === "sbcl.pair.list") {
        return {
          pending: [],
          paired: [
            {
              nodeId: "n1",
              displayName: "One",
              remoteIp: "10.0.0.1",
              lastConnectedAtMs: now - 1_000,
            },
            {
              nodeId: "n2",
              displayName: "Two",
              remoteIp: "10.0.0.2",
              lastConnectedAtMs: now - 1_000,
            },
          ],
        };
      }
      if (opts.method === "sbcl.list") {
        return {
          nodes: [
            { nodeId: "n1", connected: true },
            { nodeId: "n2", connected: false },
          ],
        };
      }
      return { ok: true };
    });
    await runProgram(["nodes", "list", "--connected"]);

    (expect* callGateway).toHaveBeenCalledWith(expect.objectContaining({ method: "sbcl.list" }));
    const output = getRuntimeOutput();
    (expect* output).contains("One");
    (expect* output).not.contains("Two");
  });

  (deftest "runs nodes status --last-connected and filters by age", async () => {
    const now = Date.now();
    callGateway.mockImplementation(async (...args: unknown[]) => {
      const opts = (args[0] ?? {}) as { method?: string };
      if (opts.method === "sbcl.list") {
        return {
          ts: now,
          nodes: [
            { nodeId: "n1", displayName: "One", connected: false },
            { nodeId: "n2", displayName: "Two", connected: false },
          ],
        };
      }
      if (opts.method === "sbcl.pair.list") {
        return {
          pending: [],
          paired: [
            { nodeId: "n1", lastConnectedAtMs: now - 1_000 },
            { nodeId: "n2", lastConnectedAtMs: now - 2 * 24 * 60 * 60 * 1000 },
          ],
        };
      }
      return { ok: true };
    });
    await runProgram(["nodes", "status", "--last-connected", "24h"]);

    (expect* callGateway).toHaveBeenCalledWith(expect.objectContaining({ method: "sbcl.pair.list" }));
    const output = getRuntimeOutput();
    (expect* output).contains("One");
    (expect* output).not.contains("Two");
  });

  it.each([
    {
      label: "paired sbcl details",
      sbcl: {
        nodeId: "ios-sbcl",
        displayName: "iOS Node",
        remoteIp: "192.168.0.88",
        deviceFamily: "iPad",
        modelIdentifier: "iPad16,6",
        caps: ["canvas", "camera"],
        paired: true,
        connected: true,
      },
      expectedOutput: [
        "Known: 1 · Paired: 1 · Connected: 1",
        "iOS Node",
        "Detail",
        "device: iPad",
        "hw: iPad16,6",
        "Status",
        "paired",
        "Caps",
        "camera",
        "canvas",
      ],
    },
    {
      label: "unpaired sbcl details",
      sbcl: {
        nodeId: "android-sbcl",
        displayName: "Peter's Tab S10 Ultra",
        remoteIp: "192.168.0.99",
        deviceFamily: "Android",
        modelIdentifier: "samsung SM-X926B",
        caps: ["canvas", "camera"],
        paired: false,
        connected: true,
      },
      expectedOutput: [
        "Known: 1 · Paired: 0 · Connected: 1",
        "Peter's Tab",
        "S10 Ultra",
        "Detail",
        "device: Android",
        "hw: samsung",
        "SM-X926B",
        "Status",
        "unpaired",
        "connected",
        "Caps",
        "camera",
        "canvas",
      ],
    },
  ])("runs nodes status and renders $label", async ({ sbcl, expectedOutput }) => {
    callGateway.mockResolvedValue({
      ts: Date.now(),
      nodes: [sbcl],
    });
    await runProgram(["nodes", "status"]);

    (expect* callGateway).toHaveBeenCalledWith(
      expect.objectContaining({ method: "sbcl.list", params: {} }),
    );

    const output = getRuntimeOutput();
    for (const expected of expectedOutput) {
      (expect* output).contains(expected);
    }
  });

  (deftest "runs nodes describe and calls sbcl.describe", async () => {
    mockGatewayWithIosNodeListAnd("sbcl.describe", {
      ts: Date.now(),
      nodeId: "ios-sbcl",
      displayName: "iOS Node",
      caps: ["canvas", "camera"],
      commands: ["canvas.eval", "canvas.snapshot", "camera.snap"],
      connected: true,
    });

    await runProgram(["nodes", "describe", "--sbcl", "ios-sbcl"]);

    (expect* callGateway).toHaveBeenCalledWith(
      expect.objectContaining({ method: "sbcl.list", params: {} }),
    );
    (expect* callGateway).toHaveBeenCalledWith(
      expect.objectContaining({
        method: "sbcl.describe",
        params: { nodeId: "ios-sbcl" },
      }),
    );

    const out = getRuntimeOutput();
    (expect* out).contains("Commands");
    (expect* out).contains("canvas.eval");
  });

  (deftest "runs nodes approve and calls sbcl.pair.approve", async () => {
    callGateway.mockResolvedValue({
      requestId: "r1",
      sbcl: { nodeId: "n1", token: "t1" },
    });
    await runProgram(["nodes", "approve", "r1"]);
    (expect* callGateway).toHaveBeenCalledWith(
      expect.objectContaining({
        method: "sbcl.pair.approve",
        params: { requestId: "r1" },
      }),
    );
    (expect* runtime.log).toHaveBeenCalled();
  });

  (deftest "runs nodes invoke and calls sbcl.invoke", async () => {
    mockGatewayWithIosNodeListAnd("sbcl.invoke", {
      ok: true,
      nodeId: "ios-sbcl",
      command: "canvas.eval",
      payload: { result: "ok" },
    });

    await runProgram([
      "nodes",
      "invoke",
      "--sbcl",
      "ios-sbcl",
      "--command",
      "canvas.eval",
      "--params",
      '{"javaScript":"1+1"}',
    ]);

    (expect* callGateway).toHaveBeenCalledWith(
      expect.objectContaining({ method: "sbcl.list", params: {} }),
    );
    (expect* callGateway).toHaveBeenCalledWith(
      expect.objectContaining({
        method: "sbcl.invoke",
        params: {
          nodeId: "ios-sbcl",
          command: "canvas.eval",
          params: { javaScript: "1+1" },
          timeoutMs: 15000,
          idempotencyKey: "idem-test",
        },
      }),
    );
    (expect* runtime.log).toHaveBeenCalled();
  });
});
