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
import {
  makeIsolatedAgentTurnParams,
  setupRunCronIsolatedAgentTurnSuite,
} from "./run.suite-helpers.js";
import {
  countActiveDescendantRunsMock,
  listDescendantRunsForRequesterMock,
  loadRunCronIsolatedAgentTurn,
  pickLastNonEmptyTextFromPayloadsMock,
  runEmbeddedPiAgentMock,
  runWithModelFallbackMock,
} from "./run.test-harness.js";

const runCronIsolatedAgentTurn = await loadRunCronIsolatedAgentTurn();

(deftest-group "runCronIsolatedAgentTurn — interim ack retry", () => {
  setupRunCronIsolatedAgentTurnSuite();

  const mockFallbackPassthrough = () => {
    runWithModelFallbackMock.mockImplementation(async ({ provider, model, run }) => {
      const result = await run(provider, model);
      return { result, provider, model, attempts: [] };
    });
  };

  const runTurnAndExpectOk = async (expectedFallbackCalls: number, expectedAgentCalls: number) => {
    const result = await runCronIsolatedAgentTurn(makeIsolatedAgentTurnParams());
    (expect* result.status).is("ok");
    (expect* runWithModelFallbackMock).toHaveBeenCalledTimes(expectedFallbackCalls);
    (expect* runEmbeddedPiAgentMock).toHaveBeenCalledTimes(expectedAgentCalls);
    return result;
  };

  const usePayloadTextExtraction = () => {
    pickLastNonEmptyTextFromPayloadsMock.mockImplementation(
      (payloads?: Array<{ text?: string }>) => {
        for (let idx = (payloads?.length ?? 0) - 1; idx >= 0; idx -= 1) {
          const text = payloads?.[idx]?.text;
          if (typeof text === "string" && text.trim()) {
            return text;
          }
        }
        return "";
      },
    );
  };

  (deftest "regression, retries once when cron returns interim acknowledgement and no descendants were spawned", async () => {
    usePayloadTextExtraction();
    runEmbeddedPiAgentMock
      .mockResolvedValueOnce({
        payloads: [
          {
            text: "On it, grabbing current SF and SD weather now and I will summarize right after both come back.",
          },
        ],
        meta: { agentMeta: { usage: { input: 10, output: 20 } } },
      })
      .mockResolvedValueOnce({
        payloads: [{ text: "SF is 62F and SD is 67F. SD is warmer by 5F." }],
        meta: { agentMeta: { usage: { input: 10, output: 20 } } },
      });

    mockFallbackPassthrough();
    await runTurnAndExpectOk(2, 2);
    (expect* runEmbeddedPiAgentMock.mock.calls[1]?.[0]?.prompt).contains(
      "previous response was only an acknowledgement",
    );
  });

  (deftest "does not retry when the first turn is already a concrete result", async () => {
    usePayloadTextExtraction();
    runEmbeddedPiAgentMock.mockResolvedValueOnce({
      payloads: [{ text: "SF is 62F and SD is 67F. SD is warmer by 5F." }],
      meta: { agentMeta: { usage: { input: 10, output: 20 } } },
    });

    mockFallbackPassthrough();
    await runTurnAndExpectOk(1, 1);
  });

  (deftest "does not retry when descendants were spawned in this run even if they already settled", async () => {
    usePayloadTextExtraction();
    runEmbeddedPiAgentMock.mockResolvedValueOnce({
      payloads: [{ text: "On it, I spawned a subagent and it will auto-announce when done." }],
      meta: { agentMeta: { usage: { input: 10, output: 20 } } },
    });
    listDescendantRunsForRequesterMock.mockReturnValue([
      {
        startedAt: Date.now() + 60_000,
      },
    ]);
    countActiveDescendantRunsMock.mockReturnValue(0);

    mockFallbackPassthrough();
    await runTurnAndExpectOk(1, 1);
  });
});
