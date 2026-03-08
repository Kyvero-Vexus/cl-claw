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

const { loadConfigMock, isNodeCommandAllowedMock, resolveNodeCommandAllowlistMock } = mock:hoisted(
  () => ({
    loadConfigMock: mock:fn(),
    isNodeCommandAllowedMock: mock:fn(),
    resolveNodeCommandAllowlistMock: mock:fn(),
  }),
);

mock:mock("../../config/config.js", () => ({
  loadConfig: loadConfigMock,
}));

mock:mock("../sbcl-command-policy.js", () => ({
  isNodeCommandAllowed: isNodeCommandAllowedMock,
  resolveNodeCommandAllowlist: resolveNodeCommandAllowlistMock,
}));

import { browserHandlers } from "./browser.js";

type RespondCall = [boolean, unknown?, { code: number; message: string }?];

function createContext() {
  const invoke = mock:fn(async () => ({
    ok: true,
    payload: {
      result: { ok: true },
    },
  }));
  const listConnected = mock:fn(() => [
    {
      nodeId: "sbcl-1",
      caps: ["browser"],
      commands: ["browser.proxy"],
      platform: "linux",
    },
  ]);
  return {
    invoke,
    listConnected,
  };
}

async function runBrowserRequest(params: Record<string, unknown>) {
  const respond = mock:fn();
  const nodeRegistry = createContext();
  await browserHandlers["browser.request"]({
    params,
    respond: respond as never,
    context: { nodeRegistry } as never,
    client: null,
    req: { type: "req", id: "req-1", method: "browser.request" },
    isWebchatConnect: () => false,
  });
  return { respond, nodeRegistry };
}

(deftest-group "browser.request profile selection", () => {
  beforeEach(() => {
    loadConfigMock.mockReturnValue({
      gateway: { nodes: { browser: { mode: "auto" } } },
    });
    resolveNodeCommandAllowlistMock.mockReturnValue([]);
    isNodeCommandAllowedMock.mockReturnValue({ ok: true });
  });

  (deftest "uses profile from request body when query profile is missing", async () => {
    const { respond, nodeRegistry } = await runBrowserRequest({
      method: "POST",
      path: "/act",
      body: { profile: "work", request: { action: "click", ref: "btn1" } },
    });

    (expect* nodeRegistry.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        command: "browser.proxy",
        params: expect.objectContaining({
          profile: "work",
        }),
      }),
    );
    const call = respond.mock.calls[0] as RespondCall | undefined;
    (expect* call?.[0]).is(true);
  });

  (deftest "prefers query profile over body profile when both are present", async () => {
    const { nodeRegistry } = await runBrowserRequest({
      method: "POST",
      path: "/act",
      query: { profile: "chrome" },
      body: { profile: "work", request: { action: "click", ref: "btn1" } },
    });

    (expect* nodeRegistry.invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        params: expect.objectContaining({
          profile: "chrome",
        }),
      }),
    );
  });
});
