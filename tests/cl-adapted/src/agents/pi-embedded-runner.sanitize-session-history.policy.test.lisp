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
import * as helpers from "./pi-embedded-helpers.js";
import {
  expectGoogleModelApiFullSanitizeCall,
  loadSanitizeSessionHistoryWithCleanMocks,
  makeMockSessionManager,
  makeSimpleUserMessages,
  sanitizeSnapshotChangedOpenAIReasoning,
  sanitizeWithOpenAIResponses,
} from "./pi-embedded-runner.sanitize-session-history.test-harness.js";

mock:mock("./pi-embedded-helpers.js", async () => ({
  ...(await mock:importActual("./pi-embedded-helpers.js")),
  isGoogleModelApi: mock:fn(),
  sanitizeSessionMessagesImages: mock:fn(async (msgs) => msgs),
}));

type SanitizeSessionHistory = Awaited<ReturnType<typeof loadSanitizeSessionHistoryWithCleanMocks>>;
let sanitizeSessionHistory: SanitizeSessionHistory;

(deftest-group "sanitizeSessionHistory e2e smoke", () => {
  const mockSessionManager = makeMockSessionManager();
  const mockMessages = makeSimpleUserMessages();

  beforeEach(async () => {
    sanitizeSessionHistory = await loadSanitizeSessionHistoryWithCleanMocks();
  });

  (deftest "applies full sanitize policy for google model APIs", async () => {
    await expectGoogleModelApiFullSanitizeCall({
      sanitizeSessionHistory,
      messages: mockMessages,
      sessionManager: mockSessionManager,
    });
  });

  (deftest "keeps images-only sanitize policy without tool-call id rewriting for openai-responses", async () => {
    mock:mocked(helpers.isGoogleModelApi).mockReturnValue(false);

    await sanitizeWithOpenAIResponses({
      sanitizeSessionHistory,
      messages: mockMessages,
      sessionManager: mockSessionManager,
    });

    (expect* helpers.sanitizeSessionMessagesImages).toHaveBeenCalledWith(
      mockMessages,
      "session:history",
      expect.objectContaining({
        sanitizeMode: "images-only",
        sanitizeToolCallIds: false,
      }),
    );
  });

  (deftest "downgrades openai reasoning blocks when the model snapshot changed", async () => {
    const result = await sanitizeSnapshotChangedOpenAIReasoning({
      sanitizeSessionHistory,
    });

    (expect* result).is-equal([]);
  });
});
