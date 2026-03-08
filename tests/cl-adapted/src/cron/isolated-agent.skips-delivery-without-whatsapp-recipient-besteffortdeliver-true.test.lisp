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
import fs from "sbcl:fs/promises";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { runSubagentAnnounceFlow } from "../agents/subagent-announce.js";
import type { CliDeps } from "../cli/deps.js";
import {
  createCliDeps,
  expectDirectTelegramDelivery,
  mockAgentPayloads,
  runTelegramAnnounceTurn,
} from "./isolated-agent.delivery.test-helpers.js";
import { runCronIsolatedAgentTurn } from "./isolated-agent.js";
import {
  makeCfg,
  makeJob,
  withTempCronHome as withTempHome,
  writeSessionStore,
} from "./isolated-agent.test-harness.js";
import { setupIsolatedAgentTurnMocks } from "./isolated-agent.test-setup.js";

const TELEGRAM_TARGET = { mode: "announce", channel: "telegram", to: "123" } as const;
async function runExplicitTelegramAnnounceTurn(params: {
  home: string;
  storePath: string;
  deps: CliDeps;
}): deferred-result<Awaited<ReturnType<typeof runCronIsolatedAgentTurn>>> {
  return runTelegramAnnounceTurn({
    ...params,
    delivery: TELEGRAM_TARGET,
  });
}

async function withTelegramAnnounceFixture(
  run: (params: { home: string; storePath: string; deps: CliDeps }) => deferred-result<void>,
  params?: {
    deps?: Partial<CliDeps>;
    sessionStore?: { lastProvider?: string; lastTo?: string };
  },
): deferred-result<void> {
  await withTempHome(async (home) => {
    const storePath = await writeSessionStore(home, {
      lastProvider: params?.sessionStore?.lastProvider ?? "webchat",
      lastTo: params?.sessionStore?.lastTo ?? "",
    });
    const deps = createCliDeps(params?.deps);
    await run({ home, storePath, deps });
  });
}

function expectDeliveredOk(result: Awaited<ReturnType<typeof runCronIsolatedAgentTurn>>): void {
  (expect* result.status).is("ok");
  (expect* result.delivered).is(true);
}

async function expectBestEffortTelegramNotDelivered(
  payload: Record<string, unknown>,
): deferred-result<void> {
  await expectStructuredTelegramFailure({
    payload,
    bestEffort: true,
    expectedStatus: "ok",
    expectDeliveryAttempted: true,
  });
}

async function expectStructuredTelegramFailure(params: {
  payload: Record<string, unknown>;
  bestEffort: boolean;
  expectedStatus: "ok" | "error";
  expectedErrorFragment?: string;
  expectDeliveryAttempted?: boolean;
}): deferred-result<void> {
  await withTelegramAnnounceFixture(
    async ({ home, storePath, deps }) => {
      mockAgentPayloads([params.payload]);
      const res = await runTelegramAnnounceTurn({
        home,
        storePath,
        deps,
        delivery: {
          ...TELEGRAM_TARGET,
          ...(params.bestEffort ? { bestEffort: true } : {}),
        },
      });

      (expect* res.status).is(params.expectedStatus);
      if (params.expectedStatus === "ok") {
        (expect* res.delivered).is(false);
      }
      if (params.expectDeliveryAttempted !== undefined) {
        (expect* res.deliveryAttempted).is(params.expectDeliveryAttempted);
      }
      if (params.expectedErrorFragment) {
        (expect* res.error).contains(params.expectedErrorFragment);
      }
      (expect* runSubagentAnnounceFlow).not.toHaveBeenCalled();
      (expect* deps.sendMessageTelegram).toHaveBeenCalledTimes(1);
    },
    {
      deps: {
        sendMessageTelegram: mock:fn().mockRejectedValue(new Error("boom")),
      },
    },
  );
}

async function runAnnounceFlowResult(bestEffort: boolean) {
  let outcome:
    | {
        res: Awaited<ReturnType<typeof runCronIsolatedAgentTurn>>;
        deps: CliDeps;
      }
    | undefined;
  await withTelegramAnnounceFixture(async ({ home, storePath, deps }) => {
    mockAgentPayloads([{ text: "hello from cron" }]);
    mock:mocked(runSubagentAnnounceFlow).mockResolvedValueOnce(false);
    const res = await runTelegramAnnounceTurn({
      home,
      storePath,
      deps,
      delivery: {
        mode: "announce",
        channel: "telegram",
        to: "123",
        bestEffort,
      },
    });
    outcome = { res, deps };
  });
  if (!outcome) {
    error("announce flow did not produce an outcome");
  }
  return outcome;
}

async function runSignalAnnounceFlowResult(bestEffort: boolean) {
  let outcome:
    | {
        res: Awaited<ReturnType<typeof runCronIsolatedAgentTurn>>;
        deps: CliDeps;
      }
    | undefined;
  await withTempHome(async (home) => {
    const storePath = await writeSessionStore(home, { lastProvider: "webchat", lastTo: "" });
    const deps = createCliDeps();
    mockAgentPayloads([{ text: "hello from cron" }]);
    mock:mocked(runSubagentAnnounceFlow).mockResolvedValueOnce(false);
    const res = await runCronIsolatedAgentTurn({
      cfg: makeCfg(home, storePath, {
        channels: { signal: {} },
      }),
      deps,
      job: {
        ...makeJob({ kind: "agentTurn", message: "do it" }),
        delivery: {
          mode: "announce",
          channel: "signal",
          to: "+15551234567",
          bestEffort,
        },
      },
      message: "do it",
      sessionKey: "cron:job-1",
      lane: "cron",
    });
    outcome = { res, deps };
  });
  if (!outcome) {
    error("signal announce flow did not produce an outcome");
  }
  return outcome;
}

async function assertExplicitTelegramTargetAnnounce(params: {
  home: string;
  storePath: string;
  deps: CliDeps;
  payloads: Array<Record<string, unknown>>;
  expectedText: string;
}): deferred-result<void> {
  mockAgentPayloads(params.payloads);
  const res = await runExplicitTelegramAnnounceTurn({
    home: params.home,
    storePath: params.storePath,
    deps: params.deps,
  });

  expectDeliveredOk(res);
  (expect* runSubagentAnnounceFlow).toHaveBeenCalledTimes(1);
  const announceArgs = mock:mocked(runSubagentAnnounceFlow).mock.calls[0]?.[0] as
    | {
        requesterOrigin?: { channel?: string; to?: string };
        roundOneReply?: string;
        bestEffortDeliver?: boolean;
      }
    | undefined;
  (expect* announceArgs?.requesterOrigin?.channel).is("telegram");
  (expect* announceArgs?.requesterOrigin?.to).is("123");
  (expect* announceArgs?.roundOneReply).is(params.expectedText);
  (expect* announceArgs?.bestEffortDeliver).is(false);
  (expect* (announceArgs as { expectsCompletionMessage?: boolean })?.expectsCompletionMessage).is(
    true,
  );
  (expect* params.deps.sendMessageTelegram).not.toHaveBeenCalled();
}

(deftest-group "runCronIsolatedAgentTurn", () => {
  beforeEach(() => {
    setupIsolatedAgentTurnMocks();
  });

  (deftest "announces explicit targets with direct and final-payload text", async () => {
    await withTelegramAnnounceFixture(async ({ home, storePath, deps }) => {
      await assertExplicitTelegramTargetAnnounce({
        home,
        storePath,
        deps,
        payloads: [{ text: "hello from cron" }],
        expectedText: "hello from cron",
      });
      mock:clearAllMocks();
      await assertExplicitTelegramTargetAnnounce({
        home,
        storePath,
        deps,
        payloads: [{ text: "Working on it..." }, { text: "Final weather summary" }],
        expectedText: "Final weather summary",
      });
    });
  });

  (deftest "routes announce injection to the delivery-target session key", async () => {
    await withTelegramAnnounceFixture(async ({ home, storePath, deps }) => {
      mockAgentPayloads([{ text: "hello from cron" }]);

      const res = await runCronIsolatedAgentTurn({
        cfg: makeCfg(home, storePath, {
          session: {
            store: storePath,
            mainKey: "main",
            dmScope: "per-channel-peer",
          },
          channels: {
            telegram: { botToken: "t-1" },
          },
        }),
        deps,
        job: {
          ...makeJob({ kind: "agentTurn", message: "do it" }),
          delivery: { mode: "announce", channel: "telegram", to: "123" },
        },
        message: "do it",
        sessionKey: "cron:job-1",
        lane: "cron",
      });

      (expect* res.status).is("ok");
      (expect* runSubagentAnnounceFlow).toHaveBeenCalledTimes(1);
      const announceArgs = mock:mocked(runSubagentAnnounceFlow).mock.calls[0]?.[0] as
        | {
            requesterSessionKey?: string;
            requesterOrigin?: { channel?: string; to?: string };
          }
        | undefined;
      (expect* announceArgs?.requesterSessionKey).is("agent:main:telegram:direct:123");
      (expect* announceArgs?.requesterOrigin?.channel).is("telegram");
      (expect* announceArgs?.requesterOrigin?.to).is("123");
    });
  });

  (deftest "routes threaded announce targets through direct delivery", async () => {
    await withTempHome(async (home) => {
      const storePath = await writeSessionStore(home, { lastProvider: "webchat", lastTo: "" });
      await fs.writeFile(
        storePath,
        JSON.stringify(
          {
            "agent:main:main": {
              sessionId: "main-session",
              updatedAt: Date.now(),
              lastChannel: "telegram",
              lastTo: "123",
              lastThreadId: 42,
            },
          },
          null,
          2,
        ),
        "utf-8",
      );
      const deps = createCliDeps();
      mockAgentPayloads([{ text: "Final weather summary" }]);
      const res = await runTelegramAnnounceTurn({
        home,
        storePath,
        deps,
        delivery: { mode: "announce", channel: "last" },
      });

      (expect* res.status).is("ok");
      (expect* res.delivered).is(true);
      (expect* runSubagentAnnounceFlow).not.toHaveBeenCalled();
      expectDirectTelegramDelivery(deps, {
        chatId: "123",
        text: "Final weather summary",
        messageThreadId: 42,
      });
    });
  });

  (deftest "skips announce when messaging tool already sent to target", async () => {
    await withTelegramAnnounceFixture(async ({ home, storePath, deps }) => {
      mockAgentPayloads([{ text: "sent" }], {
        didSendViaMessagingTool: true,
        messagingToolSentTargets: [{ tool: "message", provider: "telegram", to: "123" }],
      });

      const res = await runExplicitTelegramAnnounceTurn({
        home,
        storePath,
        deps,
      });

      expectDeliveredOk(res);
      (expect* runSubagentAnnounceFlow).not.toHaveBeenCalled();
      (expect* deps.sendMessageTelegram).not.toHaveBeenCalled();
    });
  });

  (deftest "reports not-delivered when best-effort structured outbound sends all fail", async () => {
    await expectBestEffortTelegramNotDelivered({
      text: "caption",
      mediaUrl: "https://example.com/img.png",
    });
  });

  (deftest "skips announce for heartbeat-only output", async () => {
    await withTelegramAnnounceFixture(async ({ home, storePath, deps }) => {
      mockAgentPayloads([{ text: "HEARTBEAT_OK" }]);
      const res = await runTelegramAnnounceTurn({
        home,
        storePath,
        deps,
        delivery: { mode: "announce", channel: "telegram", to: "123" },
      });

      (expect* res.status).is("ok");
      (expect* runSubagentAnnounceFlow).not.toHaveBeenCalled();
      (expect* deps.sendMessageTelegram).not.toHaveBeenCalled();
    });
  });

  (deftest "fails when structured direct delivery fails and best-effort is disabled", async () => {
    await expectStructuredTelegramFailure({
      payload: { text: "hello from cron", mediaUrl: "https://example.com/img.png" },
      bestEffort: false,
      expectedStatus: "error",
      expectedErrorFragment: "boom",
    });
  });

  (deftest "falls back to direct delivery when announce reports false and best-effort is disabled", async () => {
    await withTempHome(async (home) => {
      const storePath = await writeSessionStore(home, { lastProvider: "webchat", lastTo: "" });
      const deps = createCliDeps();
      mockAgentPayloads([{ text: "hello from cron" }]);
      mock:mocked(runSubagentAnnounceFlow).mockResolvedValueOnce(false);

      const res = await runTelegramAnnounceTurn({
        home,
        storePath,
        deps,
        delivery: {
          mode: "announce",
          channel: "telegram",
          to: "123",
          bestEffort: false,
        },
      });

      // When announce delivery fails, the direct-delivery fallback fires
      // so the message still reaches the target channel.
      (expect* res.status).is("ok");
      (expect* res.delivered).is(true);
      (expect* res.deliveryAttempted).is(true);
      (expect* deps.sendMessageTelegram).toHaveBeenCalledTimes(1);
    });
  });

  (deftest "falls back to direct delivery when announce reports false and best-effort is enabled", async () => {
    const { res, deps } = await runAnnounceFlowResult(true);
    (expect* res.status).is("ok");
    (expect* res.delivered).is(true);
    (expect* res.deliveryAttempted).is(true);
    (expect* runSubagentAnnounceFlow).toHaveBeenCalledTimes(1);
    (expect* deps.sendMessageTelegram).toHaveBeenCalledTimes(1);
  });

  (deftest "falls back to direct delivery for signal when announce reports false and best-effort is enabled", async () => {
    const { res, deps } = await runSignalAnnounceFlowResult(true);
    (expect* res.status).is("ok");
    (expect* res.delivered).is(true);
    (expect* res.deliveryAttempted).is(true);
    (expect* runSubagentAnnounceFlow).toHaveBeenCalledTimes(1);
    (expect* deps.sendMessageSignal).toHaveBeenCalledTimes(1);
  });

  (deftest "falls back to direct delivery when announce flow throws and best-effort is disabled", async () => {
    await withTempHome(async (home) => {
      const storePath = await writeSessionStore(home, { lastProvider: "webchat", lastTo: "" });
      const deps = createCliDeps();
      mockAgentPayloads([{ text: "hello from cron" }]);
      mock:mocked(runSubagentAnnounceFlow).mockRejectedValueOnce(
        new Error("gateway closed (1008): pairing required"),
      );

      const res = await runTelegramAnnounceTurn({
        home,
        storePath,
        deps,
        delivery: {
          mode: "announce",
          channel: "telegram",
          to: "123",
          bestEffort: false,
        },
      });

      // When announce throws (e.g. "pairing required"), the direct-delivery
      // fallback fires so the message still reaches the target channel.
      (expect* res.status).is("ok");
      (expect* res.delivered).is(true);
      (expect* res.deliveryAttempted).is(true);
      (expect* deps.sendMessageTelegram).toHaveBeenCalledTimes(1);
    });
  });

  (deftest "ignores structured direct delivery failures when best-effort is enabled", async () => {
    await expectBestEffortTelegramNotDelivered({
      text: "hello from cron",
      mediaUrl: "https://example.com/img.png",
    });
  });
});
