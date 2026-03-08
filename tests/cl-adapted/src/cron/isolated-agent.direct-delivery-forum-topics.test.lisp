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

import "./isolated-agent.mocks.js";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { runSubagentAnnounceFlow } from "../agents/subagent-announce.js";
import {
  createCliDeps,
  expectDirectTelegramDelivery,
  mockAgentPayloads,
  runTelegramAnnounceTurn,
} from "./isolated-agent.delivery.test-helpers.js";
import { withTempCronHome, writeSessionStore } from "./isolated-agent.test-harness.js";
import { setupIsolatedAgentTurnMocks } from "./isolated-agent.test-setup.js";

(deftest-group "runCronIsolatedAgentTurn forum topic delivery", () => {
  beforeEach(() => {
    setupIsolatedAgentTurnMocks();
  });

  (deftest "routes forum-topic and plain telegram targets through the correct delivery path", async () => {
    await withTempCronHome(async (home) => {
      const storePath = await writeSessionStore(home, { lastProvider: "webchat", lastTo: "" });
      const deps = createCliDeps();
      mockAgentPayloads([{ text: "forum message" }]);

      const res = await runTelegramAnnounceTurn({
        home,
        storePath,
        deps,
        delivery: { mode: "announce", channel: "telegram", to: "123:topic:42" },
      });

      (expect* res.status).is("ok");
      (expect* res.delivered).is(true);
      (expect* runSubagentAnnounceFlow).not.toHaveBeenCalled();
      expectDirectTelegramDelivery(deps, {
        chatId: "123",
        text: "forum message",
        messageThreadId: 42,
      });

      mock:clearAllMocks();
      mockAgentPayloads([{ text: "plain message" }]);

      const plainRes = await runTelegramAnnounceTurn({
        home,
        storePath,
        deps,
        delivery: { mode: "announce", channel: "telegram", to: "123" },
      });

      (expect* plainRes.status).is("ok");
      (expect* runSubagentAnnounceFlow).toHaveBeenCalledTimes(1);
      const announceArgs = mock:mocked(runSubagentAnnounceFlow).mock.calls[0]?.[0] as
        | { expectsCompletionMessage?: boolean }
        | undefined;
      (expect* announceArgs?.expectsCompletionMessage).is(true);
      (expect* deps.sendMessageTelegram).not.toHaveBeenCalled();
    });
  });
});
