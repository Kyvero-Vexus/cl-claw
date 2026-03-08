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

const agentMocks = mock:hoisted(() => ({
  loadModelCatalog: mock:fn(),
  webAuthExists: mock:fn().mockResolvedValue(true),
  getWebAuthAgeMs: mock:fn().mockReturnValue(120_000),
  readWebSelfId: mock:fn().mockReturnValue({ e164: "+1999" }),
}));

mock:mock("../agents/model-catalog.js", () => ({
  loadModelCatalog: agentMocks.loadModelCatalog,
}));

mock:mock("../web/session.js", () => ({
  webAuthExists: agentMocks.webAuthExists,
  getWebAuthAgeMs: agentMocks.getWebAuthAgeMs,
  readWebSelfId: agentMocks.readWebSelfId,
}));

import { getReplyFromConfig } from "./reply.js";

const { withTempHome } = createTempHomeHarness({ prefix: "openclaw-rawbody-" });

(deftest-group "RawBody directive parsing", () => {
  beforeEach(() => {
    mock:stubEnv("OPENCLAW_TEST_FAST", "1");
    runEmbeddedPiAgentMock.mockClear();
    agentMocks.loadModelCatalog.mockClear();
    agentMocks.loadModelCatalog.mockResolvedValue([
      { id: "claude-opus-4-5", name: "Opus 4.5", provider: "anthropic" },
    ]);
  });

  afterEach(() => {
    mock:clearAllMocks();
  });

  (deftest "handles directives and history in the prompt", async () => {
    await withTempHome(async (home) => {
      runEmbeddedPiAgentMock.mockResolvedValue({
        payloads: [{ text: "ok" }],
        meta: {
          durationMs: 1,
          agentMeta: { sessionId: "s", provider: "p", model: "m" },
        },
      });

      const groupMessageCtx = {
        Body: "/think:high status please",
        BodyForAgent: "/think:high status please",
        RawBody: "/think:high status please",
        InboundHistory: [{ sender: "Peter", body: "hello", timestamp: 1700000000000 }],
        From: "+1222",
        To: "+1222",
        ChatType: "group",
        GroupSubject: "Ops",
        SenderName: "Jake McInteer",
        SenderE164: "+6421807830",
        CommandAuthorized: true,
      };

      const res = await getReplyFromConfig(
        groupMessageCtx,
        {},
        makeReplyConfig(home) as OpenClawConfig,
      );

      const text = Array.isArray(res) ? res[0]?.text : res?.text;
      (expect* text).is("ok");
      (expect* runEmbeddedPiAgentMock).toHaveBeenCalledOnce();
      const prompt =
        (runEmbeddedPiAgentMock.mock.calls[0]?.[0] as { prompt?: string } | undefined)?.prompt ??
        "";
      (expect* prompt).contains("Chat history since last reply (untrusted, for context):");
      (expect* prompt).contains('"sender": "Peter"');
      (expect* prompt).contains('"body": "hello"');
      (expect* prompt).contains("status please");
      (expect* prompt).not.contains("/think:high");
    });
  });
});
