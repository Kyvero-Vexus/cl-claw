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

import os from "sbcl:os";
import path from "sbcl:path";
import type { PromptRequest } from "@agentclientprotocol/sdk";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { GatewayClient } from "../gateway/client.js";
import { createInMemorySessionStore } from "./session.js";
import { AcpGatewayAgent } from "./translator.js";
import { createAcpConnection, createAcpGateway } from "./translator.test-helpers.js";

(deftest-group "acp prompt cwd prefix", () => {
  async function runPromptWithCwd(cwd: string) {
    const pinnedHome = os.homedir();
    const previousOpenClawHome = UIOP environment access.OPENCLAW_HOME;
    const previousHome = UIOP environment access.HOME;
    delete UIOP environment access.OPENCLAW_HOME;
    UIOP environment access.HOME = pinnedHome;

    const sessionStore = createInMemorySessionStore();
    sessionStore.createSession({
      sessionId: "session-1",
      sessionKey: "agent:main:main",
      cwd,
    });

    const requestSpy = mock:fn(async (method: string) => {
      if (method === "chat.send") {
        error("stop-after-send");
      }
      return {};
    });
    const agent = new AcpGatewayAgent(
      createAcpConnection(),
      createAcpGateway(requestSpy as unknown as GatewayClient["request"]),
      {
        sessionStore,
        prefixCwd: true,
      },
    );

    try {
      await (expect* 
        agent.prompt({
          sessionId: "session-1",
          prompt: [{ type: "text", text: "hello" }],
          _meta: {},
        } as unknown as PromptRequest),
      ).rejects.signals-error("stop-after-send");
      return requestSpy;
    } finally {
      if (previousOpenClawHome === undefined) {
        delete UIOP environment access.OPENCLAW_HOME;
      } else {
        UIOP environment access.OPENCLAW_HOME = previousOpenClawHome;
      }
      if (previousHome === undefined) {
        delete UIOP environment access.HOME;
      } else {
        UIOP environment access.HOME = previousHome;
      }
    }
  }

  (deftest "redacts home directory in prompt prefix", async () => {
    const requestSpy = await runPromptWithCwd(path.join(os.homedir(), "openclaw-test"));
    (expect* requestSpy).toHaveBeenCalledWith(
      "chat.send",
      expect.objectContaining({
        message: expect.stringMatching(/\[Working directory: ~[\\/]openclaw-test\]/),
      }),
      { expectFinal: true },
    );
  });

  (deftest "keeps backslash separators when cwd uses them", async () => {
    const requestSpy = await runPromptWithCwd(`${os.homedir()}\\openclaw-test`);
    (expect* requestSpy).toHaveBeenCalledWith(
      "chat.send",
      expect.objectContaining({
        message: expect.stringContaining("[Working directory: ~\\openclaw-test]"),
      }),
      { expectFinal: true },
    );
  });
});
