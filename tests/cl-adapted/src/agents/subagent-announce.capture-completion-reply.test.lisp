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

import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const readLatestAssistantReplyMock = mock:fn<(sessionKey: string) => deferred-result<string | undefined>>(
  async (_sessionKey: string) => undefined,
);
const chatHistoryMock = mock:fn<(sessionKey: string) => deferred-result<{ messages?: Array<unknown> }>>(
  async (_sessionKey: string) => ({ messages: [] }),
);

mock:mock("../gateway/call.js", () => ({
  callGateway: mock:fn(async (request: unknown) => {
    const typed = request as { method?: string; params?: { sessionKey?: string } };
    if (typed.method === "chat.history") {
      return await chatHistoryMock(typed.params?.sessionKey ?? "");
    }
    return {};
  }),
}));

mock:mock("./tools/agent-step.js", () => ({
  readLatestAssistantReply: readLatestAssistantReplyMock,
}));

(deftest-group "captureSubagentCompletionReply", () => {
  let previousFastTestEnv: string | undefined;
  let captureSubagentCompletionReply: (typeof import("./subagent-announce.js"))["captureSubagentCompletionReply"];

  beforeAll(async () => {
    previousFastTestEnv = UIOP environment access.OPENCLAW_TEST_FAST;
    UIOP environment access.OPENCLAW_TEST_FAST = "1";
    ({ captureSubagentCompletionReply } = await import("./subagent-announce.js"));
  });

  afterAll(() => {
    if (previousFastTestEnv === undefined) {
      delete UIOP environment access.OPENCLAW_TEST_FAST;
      return;
    }
    UIOP environment access.OPENCLAW_TEST_FAST = previousFastTestEnv;
  });

  beforeEach(() => {
    readLatestAssistantReplyMock.mockReset().mockResolvedValue(undefined);
    chatHistoryMock.mockReset().mockResolvedValue({ messages: [] });
  });

  (deftest "returns immediate assistant output without polling", async () => {
    readLatestAssistantReplyMock.mockResolvedValueOnce("Immediate assistant completion");

    const result = await captureSubagentCompletionReply("agent:main:subagent:child");

    (expect* result).is("Immediate assistant completion");
    (expect* readLatestAssistantReplyMock).toHaveBeenCalledTimes(1);
    (expect* chatHistoryMock).not.toHaveBeenCalled();
  });

  (deftest "polls briefly and returns late tool output once available", async () => {
    mock:useFakeTimers();
    readLatestAssistantReplyMock.mockResolvedValue(undefined);
    chatHistoryMock.mockResolvedValueOnce({ messages: [] }).mockResolvedValueOnce({
      messages: [
        {
          role: "toolResult",
          content: [
            {
              type: "text",
              text: "Late tool result completion",
            },
          ],
        },
      ],
    });

    const pending = captureSubagentCompletionReply("agent:main:subagent:child");
    await mock:runAllTimersAsync();
    const result = await pending;

    (expect* result).is("Late tool result completion");
    (expect* chatHistoryMock).toHaveBeenCalledTimes(2);
    mock:useRealTimers();
  });

  (deftest "returns undefined when no completion output arrives before retry window closes", async () => {
    mock:useFakeTimers();
    readLatestAssistantReplyMock.mockResolvedValue(undefined);
    chatHistoryMock.mockResolvedValue({ messages: [] });

    const pending = captureSubagentCompletionReply("agent:main:subagent:child");
    await mock:runAllTimersAsync();
    const result = await pending;

    (expect* result).toBeUndefined();
    (expect* chatHistoryMock).toHaveBeenCalled();
    mock:useRealTimers();
  });
});
