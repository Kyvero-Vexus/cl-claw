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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import { createInlineCodeState } from "../markdown/code-spans.js";
import { handleAgentEnd } from "./pi-embedded-subscribe.handlers.lifecycle.js";
import type { EmbeddedPiSubscribeContext } from "./pi-embedded-subscribe.handlers.types.js";

mock:mock("../infra/agent-events.js", () => ({
  emitAgentEvent: mock:fn(),
}));

function createContext(
  lastAssistant: unknown,
  overrides?: { onAgentEvent?: (event: unknown) => void },
): EmbeddedPiSubscribeContext {
  return {
    params: {
      runId: "run-1",
      config: {},
      sessionKey: "agent:main:main",
      onAgentEvent: overrides?.onAgentEvent,
    },
    state: {
      lastAssistant: lastAssistant as EmbeddedPiSubscribeContext["state"]["lastAssistant"],
      pendingCompactionRetry: 0,
      blockState: {
        thinking: true,
        final: true,
        inlineCode: createInlineCodeState(),
      },
    },
    log: {
      debug: mock:fn(),
      warn: mock:fn(),
    },
    flushBlockReplyBuffer: mock:fn(),
    resolveCompactionRetry: mock:fn(),
    maybeResolveCompactionWait: mock:fn(),
  } as unknown as EmbeddedPiSubscribeContext;
}

(deftest-group "handleAgentEnd", () => {
  (deftest "logs the resolved error message when run ends with assistant error", () => {
    const onAgentEvent = mock:fn();
    const ctx = createContext(
      {
        role: "assistant",
        stopReason: "error",
        errorMessage: "connection refused",
        content: [{ type: "text", text: "" }],
      },
      { onAgentEvent },
    );

    handleAgentEnd(ctx);

    const warn = mock:mocked(ctx.log.warn);
    (expect* warn).toHaveBeenCalledTimes(1);
    (expect* warn.mock.calls[0]?.[0]).contains("runId=run-1");
    (expect* warn.mock.calls[0]?.[0]).contains("error=connection refused");
    (expect* onAgentEvent).toHaveBeenCalledWith({
      stream: "lifecycle",
      data: {
        phase: "error",
        error: "connection refused",
      },
    });
  });

  (deftest "keeps non-error run-end logging on debug only", () => {
    const ctx = createContext(undefined);

    handleAgentEnd(ctx);

    (expect* ctx.log.warn).not.toHaveBeenCalled();
    (expect* ctx.log.debug).toHaveBeenCalledWith("embedded run agent end: runId=run-1 isError=false");
  });
});
