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

import { afterEach, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";
const { getBotInfoMock, MessagingApiClientMock } = mock:hoisted(() => {
  const getBotInfoMock = mock:fn();
  const MessagingApiClientMock = mock:fn(function () {
    return { getBotInfo: getBotInfoMock };
  });
  return { getBotInfoMock, MessagingApiClientMock };
});

mock:mock("@line/bot-sdk", () => ({
  messagingApi: { MessagingApiClient: MessagingApiClientMock },
}));

let probeLineBot: typeof import("./probe.js").probeLineBot;

afterEach(() => {
  mock:useRealTimers();
  getBotInfoMock.mockClear();
});

(deftest-group "probeLineBot", () => {
  beforeAll(async () => {
    ({ probeLineBot } = await import("./probe.js"));
  });

  (deftest "returns timeout when bot info stalls", async () => {
    mock:useFakeTimers();
    getBotInfoMock.mockImplementation(() => new Promise(() => {}));

    const probePromise = probeLineBot("token", 10);
    await mock:advanceTimersByTimeAsync(20);
    const result = await probePromise;

    (expect* result.ok).is(false);
    (expect* result.error).is("timeout");
  });

  (deftest "returns bot info when available", async () => {
    getBotInfoMock.mockResolvedValue({
      displayName: "OpenClaw",
      userId: "U123",
      basicId: "@openclaw",
      pictureUrl: "https://example.com/bot.png",
    });

    const result = await probeLineBot("token", 50);

    (expect* result.ok).is(true);
    (expect* result.bot?.userId).is("U123");
  });
});
