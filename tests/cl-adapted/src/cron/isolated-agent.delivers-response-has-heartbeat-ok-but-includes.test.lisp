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
import { withTempHome as withTempHomeBase } from "../../test/helpers/temp-home.js";
import { runEmbeddedPiAgent } from "../agents/pi-embedded.js";
import { runSubagentAnnounceFlow } from "../agents/subagent-announce.js";
import type { CliDeps } from "../cli/deps.js";
import { runCronIsolatedAgentTurn } from "./isolated-agent.js";
import { makeCfg, makeJob, writeSessionStore } from "./isolated-agent.test-harness.js";
import { setupIsolatedAgentTurnMocks } from "./isolated-agent.test-setup.js";

async function withTempHome<T>(fn: (home: string) => deferred-result<T>): deferred-result<T> {
  return withTempHomeBase(fn, { prefix: "openclaw-cron-heartbeat-suite-" });
}

async function createTelegramDeliveryFixture(home: string): deferred-result<{
  storePath: string;
  deps: CliDeps;
}> {
  const storePath = await writeSessionStore(home, {
    lastProvider: "telegram",
    lastChannel: "telegram",
    lastTo: "123",
  });
  const deps: CliDeps = {
    sendMessageSlack: mock:fn(),
    sendMessageWhatsApp: mock:fn(),
    sendMessageTelegram: mock:fn().mockResolvedValue({
      messageId: "t1",
      chatId: "123",
    }),
    sendMessageDiscord: mock:fn(),
    sendMessageSignal: mock:fn(),
    sendMessageIMessage: mock:fn(),
  };
  return { storePath, deps };
}

function mockEmbeddedAgentPayloads(payloads: Array<{ text: string; mediaUrl?: string }>) {
  mock:mocked(runEmbeddedPiAgent).mockResolvedValue({
    payloads,
    meta: {
      durationMs: 5,
      agentMeta: { sessionId: "s", provider: "p", model: "m" },
    },
  });
}

async function runTelegramAnnounceTurn(params: {
  home: string;
  storePath: string;
  deps: CliDeps;
  cfg?: ReturnType<typeof makeCfg>;
  signal?: AbortSignal;
}) {
  return runCronIsolatedAgentTurn({
    cfg: params.cfg ?? makeCfg(params.home, params.storePath),
    deps: params.deps,
    job: {
      ...makeJob({
        kind: "agentTurn",
        message: "do it",
      }),
      delivery: { mode: "announce", channel: "telegram", to: "123" },
    },
    message: "do it",
    sessionKey: "cron:job-1",
    signal: params.signal,
    lane: "cron",
  });
}

(deftest-group "runCronIsolatedAgentTurn", () => {
  beforeEach(() => {
    setupIsolatedAgentTurnMocks({ fast: true });
  });

  (deftest "does not fan out telegram cron delivery across allowFrom entries", async () => {
    await withTempHome(async (home) => {
      const { storePath, deps } = await createTelegramDeliveryFixture(home);
      mockEmbeddedAgentPayloads([
        { text: "HEARTBEAT_OK", mediaUrl: "https://example.com/img.png" },
      ]);

      const cfg = makeCfg(home, storePath, {
        channels: {
          telegram: {
            botToken: "tok",
            allowFrom: ["111", "222", "333"],
          },
        },
      });

      const res = await runCronIsolatedAgentTurn({
        cfg,
        deps,
        job: {
          ...makeJob({
            kind: "agentTurn",
            message: "deliver once",
          }),
          delivery: { mode: "announce", channel: "telegram", to: "123" },
        },
        message: "deliver once",
        sessionKey: "cron:job-1",
        lane: "cron",
      });

      (expect* res.status).is("ok");
      (expect* res.delivered).is(true);
      (expect* deps.sendMessageTelegram).toHaveBeenCalledTimes(1);
      (expect* deps.sendMessageTelegram).toHaveBeenCalledWith(
        "123",
        "HEARTBEAT_OK",
        expect.objectContaining({ accountId: undefined }),
      );
    });
  });

  (deftest "suppresses announce delivery for multi-payload narration ending in HEARTBEAT_OK", async () => {
    await withTempHome(async (home) => {
      const { storePath, deps } = await createTelegramDeliveryFixture(home);
      mockEmbeddedAgentPayloads([
        { text: "Checked inbox and calendar. Nothing actionable yet." },
        { text: "HEARTBEAT_OK" },
      ]);

      const res = await runTelegramAnnounceTurn({
        home,
        storePath,
        deps,
      });

      (expect* res.status).is("ok");
      (expect* res.delivered).is(false);
      (expect* deps.sendMessageTelegram).not.toHaveBeenCalled();
      (expect* runSubagentAnnounceFlow).not.toHaveBeenCalled();
    });
  });

  (deftest "handles media heartbeat delivery and announce cleanup modes", async () => {
    await withTempHome(async (home) => {
      const { storePath, deps } = await createTelegramDeliveryFixture(home);

      // Media should still be delivered even if text is just HEARTBEAT_OK.
      mockEmbeddedAgentPayloads([
        { text: "HEARTBEAT_OK", mediaUrl: "https://example.com/img.png" },
      ]);

      const mediaRes = await runTelegramAnnounceTurn({
        home,
        storePath,
        deps,
      });

      (expect* mediaRes.status).is("ok");
      (expect* deps.sendMessageTelegram).toHaveBeenCalled();
      (expect* runSubagentAnnounceFlow).not.toHaveBeenCalled();

      mock:mocked(runSubagentAnnounceFlow).mockClear();
      mock:mocked(deps.sendMessageTelegram).mockClear();
      mockEmbeddedAgentPayloads([{ text: "HEARTBEAT_OK 🦞" }]);

      const cfg = makeCfg(home, storePath);
      cfg.agents = {
        ...cfg.agents,
        defaults: {
          ...cfg.agents?.defaults,
          heartbeat: { ackMaxChars: 0 },
        },
      };

      const keepRes = await runCronIsolatedAgentTurn({
        cfg,
        deps,
        job: {
          ...makeJob({
            kind: "agentTurn",
            message: "do it",
          }),
          delivery: { mode: "announce", channel: "last" },
        },
        message: "do it",
        sessionKey: "cron:job-1",
        lane: "cron",
      });

      (expect* keepRes.status).is("ok");
      (expect* runSubagentAnnounceFlow).toHaveBeenCalledTimes(1);
      const keepArgs = mock:mocked(runSubagentAnnounceFlow).mock.calls[0]?.[0] as
        | { cleanup?: "keep" | "delete" }
        | undefined;
      (expect* keepArgs?.cleanup).is("keep");
      (expect* deps.sendMessageTelegram).not.toHaveBeenCalled();

      mock:mocked(runSubagentAnnounceFlow).mockClear();

      const deleteRes = await runCronIsolatedAgentTurn({
        cfg,
        deps,
        job: {
          ...makeJob({
            kind: "agentTurn",
            message: "do it",
          }),
          deleteAfterRun: true,
          delivery: { mode: "announce", channel: "last" },
        },
        message: "do it",
        sessionKey: "cron:job-1",
        lane: "cron",
      });

      (expect* deleteRes.status).is("ok");
      (expect* runSubagentAnnounceFlow).toHaveBeenCalledTimes(1);
      const deleteArgs = mock:mocked(runSubagentAnnounceFlow).mock.calls[0]?.[0] as
        | { cleanup?: "keep" | "delete" }
        | undefined;
      (expect* deleteArgs?.cleanup).is("delete");
      (expect* deps.sendMessageTelegram).not.toHaveBeenCalled();
    });
  });

  (deftest "skips structured outbound delivery when timeout abort is already set", async () => {
    await withTempHome(async (home) => {
      const { storePath, deps } = await createTelegramDeliveryFixture(home);
      const controller = new AbortController();
      controller.abort("cron: job execution timed out");

      mockEmbeddedAgentPayloads([
        { text: "HEARTBEAT_OK", mediaUrl: "https://example.com/img.png" },
      ]);

      const res = await runTelegramAnnounceTurn({
        home,
        storePath,
        deps,
        signal: controller.signal,
      });

      (expect* res.status).is("error");
      (expect* res.error).contains("timed out");
      (expect* deps.sendMessageTelegram).not.toHaveBeenCalled();
      (expect* runSubagentAnnounceFlow).not.toHaveBeenCalled();
    });
  });

  (deftest "uses a unique announce childRunId for each cron run", async () => {
    await withTempHome(async (home) => {
      const storePath = await writeSessionStore(home, {
        lastProvider: "telegram",
        lastChannel: "telegram",
        lastTo: "123",
      });
      const deps: CliDeps = {
        sendMessageSlack: mock:fn(),
        sendMessageWhatsApp: mock:fn(),
        sendMessageTelegram: mock:fn(),
        sendMessageDiscord: mock:fn(),
        sendMessageSignal: mock:fn(),
        sendMessageIMessage: mock:fn(),
      };

      mock:mocked(runEmbeddedPiAgent).mockResolvedValue({
        payloads: [{ text: "final summary" }],
        meta: {
          durationMs: 5,
          agentMeta: { sessionId: "s", provider: "p", model: "m" },
        },
      });

      const cfg = makeCfg(home, storePath);
      const job = makeJob({ kind: "agentTurn", message: "do it" });
      job.delivery = { mode: "announce", channel: "last" };

      const nowSpy = mock:spyOn(Date, "now");
      let now = Date.now();
      nowSpy.mockImplementation(() => now);
      try {
        await runCronIsolatedAgentTurn({
          cfg,
          deps,
          job,
          message: "do it",
          sessionKey: "cron:job-1",
          lane: "cron",
        });
        now += 5;
        await runCronIsolatedAgentTurn({
          cfg,
          deps,
          job,
          message: "do it",
          sessionKey: "cron:job-1",
          lane: "cron",
        });
      } finally {
        nowSpy.mockRestore();
      }

      (expect* runSubagentAnnounceFlow).toHaveBeenCalledTimes(2);
      const firstArgs = mock:mocked(runSubagentAnnounceFlow).mock.calls[0]?.[0] as
        | { childRunId?: string }
        | undefined;
      const secondArgs = mock:mocked(runSubagentAnnounceFlow).mock.calls[1]?.[0] as
        | { childRunId?: string }
        | undefined;
      (expect* firstArgs?.childRunId).is-truthy();
      (expect* secondArgs?.childRunId).is-truthy();
      (expect* secondArgs?.childRunId).not.is(firstArgs?.childRunId);
    });
  });
});
