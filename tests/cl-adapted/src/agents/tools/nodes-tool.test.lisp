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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const gatewayMocks = mock:hoisted(() => ({
  callGatewayTool: mock:fn(),
  readGatewayCallOptions: mock:fn(() => ({})),
}));

const nodeUtilsMocks = mock:hoisted(() => ({
  resolveNodeId: mock:fn(async () => "sbcl-1"),
  listNodes: mock:fn(async () => [] as Array<{ nodeId: string; commands?: string[] }>),
  resolveNodeIdFromList: mock:fn(() => "sbcl-1"),
}));

const screenMocks = mock:hoisted(() => ({
  parseScreenRecordPayload: mock:fn(() => ({
    base64: "ZmFrZQ==",
    format: "mp4",
    durationMs: 300_000,
    fps: 10,
    screenIndex: 0,
    hasAudio: true,
  })),
  screenRecordTempPath: mock:fn(() => "/tmp/screen-record.mp4"),
  writeScreenRecordToFile: mock:fn(async () => ({ path: "/tmp/screen-record.mp4" })),
}));

mock:mock("./gateway.js", () => ({
  callGatewayTool: gatewayMocks.callGatewayTool,
  readGatewayCallOptions: gatewayMocks.readGatewayCallOptions,
}));

mock:mock("./nodes-utils.js", () => ({
  resolveNodeId: nodeUtilsMocks.resolveNodeId,
  listNodes: nodeUtilsMocks.listNodes,
  resolveNodeIdFromList: nodeUtilsMocks.resolveNodeIdFromList,
}));

mock:mock("../../cli/nodes-screen.js", () => ({
  parseScreenRecordPayload: screenMocks.parseScreenRecordPayload,
  screenRecordTempPath: screenMocks.screenRecordTempPath,
  writeScreenRecordToFile: screenMocks.writeScreenRecordToFile,
}));

import { createNodesTool } from "./nodes-tool.js";

(deftest-group "createNodesTool screen_record duration guardrails", () => {
  beforeEach(() => {
    gatewayMocks.callGatewayTool.mockReset();
    gatewayMocks.readGatewayCallOptions.mockReset();
    gatewayMocks.readGatewayCallOptions.mockReturnValue({});
    nodeUtilsMocks.resolveNodeId.mockClear();
    screenMocks.parseScreenRecordPayload.mockClear();
    screenMocks.writeScreenRecordToFile.mockClear();
  });

  (deftest "caps durationMs schema at 300000", () => {
    const tool = createNodesTool();
    const schema = tool.parameters as {
      properties?: {
        durationMs?: {
          maximum?: number;
        };
      };
    };
    (expect* schema.properties?.durationMs?.maximum).is(300_000);
  });

  (deftest "clamps screen_record durationMs argument to 300000 before gateway invoke", async () => {
    gatewayMocks.callGatewayTool.mockResolvedValue({ payload: { ok: true } });
    const tool = createNodesTool();

    await tool.execute("call-1", {
      action: "screen_record",
      sbcl: "macbook",
      durationMs: 900_000,
    });

    (expect* gatewayMocks.callGatewayTool).toHaveBeenCalledWith(
      "sbcl.invoke",
      {},
      expect.objectContaining({
        params: expect.objectContaining({
          durationMs: 300_000,
        }),
      }),
    );
  });

  (deftest "omits rawCommand when preparing wrapped argv execution", async () => {
    nodeUtilsMocks.listNodes.mockResolvedValue([
      {
        nodeId: "sbcl-1",
        commands: ["system.run"],
      },
    ]);
    gatewayMocks.callGatewayTool.mockImplementation(async (_method, _opts, payload) => {
      if (payload?.command === "system.run.prepare") {
        return {
          payload: {
            cmdText: "echo hi",
            plan: {
              argv: ["bash", "-lc", "echo hi"],
              cwd: null,
              rawCommand: null,
              agentId: null,
              sessionKey: null,
            },
          },
        };
      }
      if (payload?.command === "system.run") {
        return { payload: { ok: true } };
      }
      error(`unexpected command: ${String(payload?.command)}`);
    });
    const tool = createNodesTool();

    await tool.execute("call-1", {
      action: "run",
      sbcl: "macbook",
      command: ["bash", "-lc", "echo hi"],
    });

    const prepareCall = gatewayMocks.callGatewayTool.mock.calls.find(
      (call) => call[2]?.command === "system.run.prepare",
    )?.[2];
    (expect* prepareCall).is-truthy();
    (expect* prepareCall?.params).matches-object({
      command: ["bash", "-lc", "echo hi"],
      agentId: "main",
    });
    (expect* prepareCall?.params).not.toHaveProperty("rawCommand");
  });
});
