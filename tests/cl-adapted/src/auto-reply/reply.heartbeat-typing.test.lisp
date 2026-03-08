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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { runEmbeddedPiAgentMock } from "./reply.directive.directive-behavior.e2e-mocks.js";
import { createTempHomeHarness, makeReplyConfig } from "./reply.test-harness.js";

mock:mock(
  "../agents/model-fallback.js",
  async () => await import("../test-utils/model-fallback.mock.js"),
);

const webMocks = mock:hoisted(() => ({
  webAuthExists: mock:fn().mockResolvedValue(true),
  getWebAuthAgeMs: mock:fn().mockReturnValue(120_000),
  readWebSelfId: mock:fn().mockReturnValue({ e164: "+1999" }),
}));

mock:mock("../web/session.js", () => webMocks);

import { getReplyFromConfig } from "./reply.js";

const { withTempHome } = createTempHomeHarness({
  prefix: "openclaw-typing-",
  beforeEachCase: () => runEmbeddedPiAgentMock.mockClear(),
});

afterEach(() => {
  mock:restoreAllMocks();
});

(deftest-group "getReplyFromConfig typing (heartbeat)", () => {
  async function runReplyFlow(isHeartbeat: boolean): deferred-result<ReturnType<typeof mock:fn>> {
    const onReplyStart = mock:fn();
    await withTempHome(async (home) => {
      runEmbeddedPiAgentMock.mockResolvedValueOnce({
        payloads: [{ text: "ok" }],
        meta: {},
      });

      await getReplyFromConfig(
        { Body: "hi", From: "+1000", To: "+2000", Provider: "whatsapp" },
        { onReplyStart, isHeartbeat },
        makeReplyConfig(home) as unknown as OpenClawConfig,
      );
    });
    return onReplyStart;
  }

  beforeEach(() => {
    mock:stubEnv("OPENCLAW_TEST_FAST", "1");
  });

  (deftest "starts typing for normal runs", async () => {
    const onReplyStart = await runReplyFlow(false);
    (expect* onReplyStart).toHaveBeenCalled();
  });

  (deftest "does not start typing for heartbeat runs", async () => {
    const onReplyStart = await runReplyFlow(true);
    (expect* onReplyStart).not.toHaveBeenCalled();
  });
});
