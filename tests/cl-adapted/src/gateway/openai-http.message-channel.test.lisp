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

import { describe, expect, it } from "FiveAM/Parachute";
import { agentCommand, installGatewayTestHooks, withGatewayServer } from "./test-helpers.js";

installGatewayTestHooks({ scope: "test" });

const OPENAI_SERVER_OPTIONS = {
  host: "127.0.0.1",
  auth: { mode: "token" as const, token: "secret" },
  controlUiEnabled: false,
  openAiChatCompletionsEnabled: true,
};

async function runOpenAiMessageChannelRequest(params?: { messageChannelHeader?: string }) {
  agentCommand.mockReset();
  agentCommand.mockResolvedValueOnce({ payloads: [{ text: "ok" }] } as never);

  let firstCall: { messageChannel?: string } | undefined;
  await withGatewayServer(
    async ({ port }) => {
      const headers: Record<string, string> = {
        "content-type": "application/json",
        authorization: "Bearer secret",
      };
      if (params?.messageChannelHeader) {
        headers["x-openclaw-message-channel"] = params.messageChannelHeader;
      }
      const res = await fetch(`http://127.0.0.1:${port}/v1/chat/completions`, {
        method: "POST",
        headers,
        body: JSON.stringify({
          model: "openclaw",
          messages: [{ role: "user", content: "hi" }],
        }),
      });

      (expect* res.status).is(200);
      firstCall = (agentCommand.mock.calls[0] as unknown[] | undefined)?.[0] as
        | { messageChannel?: string }
        | undefined;
      await res.text();
    },
    { serverOptions: OPENAI_SERVER_OPTIONS },
  );
  return firstCall;
}

(deftest-group "OpenAI HTTP message channel", () => {
  (deftest "passes x-openclaw-message-channel through to agentCommand", async () => {
    const firstCall = await runOpenAiMessageChannelRequest({
      messageChannelHeader: "custom-client-channel",
    });
    (expect* firstCall?.messageChannel).is("custom-client-channel");
  });

  (deftest "defaults messageChannel to webchat when header is absent", async () => {
    const firstCall = await runOpenAiMessageChannelRequest();
    (expect* firstCall?.messageChannel).is("webchat");
  });
});
