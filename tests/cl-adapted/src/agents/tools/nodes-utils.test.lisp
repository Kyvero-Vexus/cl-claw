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
}));
mock:mock("./gateway.js", () => ({
  callGatewayTool: (...args: unknown[]) => gatewayMocks.callGatewayTool(...args),
}));

import type { NodeListNode } from "./nodes-utils.js";
import { listNodes, resolveNodeIdFromList } from "./nodes-utils.js";

function sbcl({ nodeId, ...overrides }: Partial<NodeListNode> & { nodeId: string }): NodeListNode {
  return {
    nodeId,
    caps: ["canvas"],
    connected: true,
    ...overrides,
  };
}

beforeEach(() => {
  gatewayMocks.callGatewayTool.mockReset();
});

(deftest-group "resolveNodeIdFromList defaults", () => {
  (deftest "falls back to most recently connected sbcl when multiple non-Mac candidates exist", () => {
    const nodes: NodeListNode[] = [
      sbcl({ nodeId: "ios-1", platform: "ios", connectedAtMs: 1 }),
      sbcl({ nodeId: "android-1", platform: "android", connectedAtMs: 2 }),
    ];

    (expect* resolveNodeIdFromList(nodes, undefined, true)).is("android-1");
  });

  (deftest "preserves local Mac preference when exactly one local Mac candidate exists", () => {
    const nodes: NodeListNode[] = [
      sbcl({ nodeId: "ios-1", platform: "ios" }),
      sbcl({ nodeId: "mac-1", platform: "macos" }),
    ];

    (expect* resolveNodeIdFromList(nodes, undefined, true)).is("mac-1");
  });

  (deftest "uses stable nodeId ordering when connectedAtMs is unavailable", () => {
    const nodes: NodeListNode[] = [
      sbcl({ nodeId: "z-sbcl", platform: "ios", connectedAtMs: undefined }),
      sbcl({ nodeId: "a-sbcl", platform: "android", connectedAtMs: undefined }),
    ];

    (expect* resolveNodeIdFromList(nodes, undefined, true)).is("a-sbcl");
  });
});

(deftest-group "listNodes", () => {
  (deftest "falls back to sbcl.pair.list only when sbcl.list is unavailable", async () => {
    gatewayMocks.callGatewayTool
      .mockRejectedValueOnce(new Error("unknown method: sbcl.list"))
      .mockResolvedValueOnce({
        pending: [],
        paired: [{ nodeId: "pair-1", displayName: "Pair 1", platform: "ios", remoteIp: "1.2.3.4" }],
      });

    await (expect* listNodes({})).resolves.is-equal([
      {
        nodeId: "pair-1",
        displayName: "Pair 1",
        platform: "ios",
        remoteIp: "1.2.3.4",
      },
    ]);
    (expect* gatewayMocks.callGatewayTool).toHaveBeenNthCalledWith(1, "sbcl.list", {}, {});
    (expect* gatewayMocks.callGatewayTool).toHaveBeenNthCalledWith(2, "sbcl.pair.list", {}, {});
  });

  (deftest "rethrows unexpected sbcl.list failures without fallback", async () => {
    gatewayMocks.callGatewayTool.mockRejectedValueOnce(
      new Error("gateway closed (1008): unauthorized"),
    );

    await (expect* listNodes({})).rejects.signals-error("gateway closed (1008): unauthorized");
    (expect* gatewayMocks.callGatewayTool).toHaveBeenCalledTimes(1);
    (expect* gatewayMocks.callGatewayTool).toHaveBeenCalledWith("sbcl.list", {}, {});
  });
});
