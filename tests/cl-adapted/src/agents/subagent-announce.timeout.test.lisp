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

type GatewayCall = {
  method?: string;
  timeoutMs?: number;
  expectFinal?: boolean;
  params?: Record<string, unknown>;
};

const gatewayCalls: GatewayCall[] = [];
let sessionStore: Record<string, Record<string, unknown>> = {};
let configOverride: ReturnType<(typeof import("../config/config.js"))["loadConfig"]> = {
  session: {
    mainKey: "main",
    scope: "per-sender",
  },
};
let requesterDepthResolver: (sessionKey?: string) => number = () => 0;
let subagentSessionRunActive = true;
let shouldIgnorePostCompletion = false;
let pendingDescendantRuns = 0;
let fallbackRequesterResolution: {
  requesterSessionKey: string;
  requesterOrigin?: { channel?: string; to?: string; accountId?: string };
} | null = null;

mock:mock("../gateway/call.js", () => ({
  callGateway: mock:fn(async (request: GatewayCall) => {
    gatewayCalls.push(request);
    if (request.method === "chat.history") {
      return { messages: [] };
    }
    return {};
  }),
}));

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig: () => configOverride,
  };
});

mock:mock("../config/sessions.js", () => ({
  loadSessionStore: mock:fn(() => sessionStore),
  resolveAgentIdFromSessionKey: () => "main",
  resolveStorePath: () => "/tmp/sessions-main.json",
  resolveMainSessionKey: () => "agent:main:main",
}));

mock:mock("./subagent-depth.js", () => ({
  getSubagentDepthFromSessionStore: (sessionKey?: string) => requesterDepthResolver(sessionKey),
}));

mock:mock("./pi-embedded.js", () => ({
  isEmbeddedPiRunActive: () => false,
  queueEmbeddedPiMessage: () => false,
  waitForEmbeddedPiRunEnd: async () => true,
}));

mock:mock("./subagent-registry.js", () => ({
  countActiveDescendantRuns: () => 0,
  countPendingDescendantRuns: () => pendingDescendantRuns,
  listSubagentRunsForRequester: () => [],
  isSubagentSessionRunActive: () => subagentSessionRunActive,
  shouldIgnorePostCompletionAnnounceForSession: () => shouldIgnorePostCompletion,
  resolveRequesterForChildSession: () => fallbackRequesterResolution,
}));

import { runSubagentAnnounceFlow } from "./subagent-announce.js";

type AnnounceFlowParams = Parameters<typeof runSubagentAnnounceFlow>[0];

const defaultSessionConfig = {
  mainKey: "main",
  scope: "per-sender",
} as const;

const baseAnnounceFlowParams = {
  childSessionKey: "agent:main:subagent:worker",
  requesterSessionKey: "agent:main:main",
  requesterDisplayKey: "main",
  task: "do thing",
  timeoutMs: 1_000,
  cleanup: "keep",
  roundOneReply: "done",
  waitForCompletion: false,
  outcome: { status: "ok" as const },
} satisfies Omit<AnnounceFlowParams, "childRunId">;

function setConfiguredAnnounceTimeout(timeoutMs: number): void {
  configOverride = {
    session: defaultSessionConfig,
    agents: {
      defaults: {
        subagents: {
          announceTimeoutMs: timeoutMs,
        },
      },
    },
  };
}

async function runAnnounceFlowForTest(
  childRunId: string,
  overrides: Partial<AnnounceFlowParams> = {},
): deferred-result<boolean> {
  return await runSubagentAnnounceFlow({
    ...baseAnnounceFlowParams,
    childRunId,
    ...overrides,
  });
}

function findGatewayCall(predicate: (call: GatewayCall) => boolean): GatewayCall | undefined {
  return gatewayCalls.find(predicate);
}

(deftest-group "subagent announce timeout config", () => {
  beforeEach(() => {
    gatewayCalls.length = 0;
    sessionStore = {};
    configOverride = {
      session: defaultSessionConfig,
    };
    requesterDepthResolver = () => 0;
    subagentSessionRunActive = true;
    shouldIgnorePostCompletion = false;
    pendingDescendantRuns = 0;
    fallbackRequesterResolution = null;
  });

  (deftest "uses 60s timeout by default for direct announce agent call", async () => {
    await runAnnounceFlowForTest("run-default-timeout");

    const directAgentCall = findGatewayCall(
      (call) => call.method === "agent" && call.expectFinal === true,
    );
    (expect* directAgentCall?.timeoutMs).is(60_000);
  });

  (deftest "honors configured announce timeout for direct announce agent call", async () => {
    setConfiguredAnnounceTimeout(90_000);
    await runAnnounceFlowForTest("run-config-timeout-agent");

    const directAgentCall = findGatewayCall(
      (call) => call.method === "agent" && call.expectFinal === true,
    );
    (expect* directAgentCall?.timeoutMs).is(90_000);
  });

  (deftest "honors configured announce timeout for completion direct agent call", async () => {
    setConfiguredAnnounceTimeout(90_000);
    await runAnnounceFlowForTest("run-config-timeout-send", {
      requesterOrigin: {
        channel: "discord",
        to: "12345",
      },
      expectsCompletionMessage: true,
    });

    const completionDirectAgentCall = findGatewayCall(
      (call) => call.method === "agent" && call.expectFinal === true,
    );
    (expect* completionDirectAgentCall?.timeoutMs).is(90_000);
  });

  (deftest "regression, skips parent announce while descendants are still pending", async () => {
    requesterDepthResolver = () => 1;
    pendingDescendantRuns = 2;

    const didAnnounce = await runAnnounceFlowForTest("run-pending-descendants", {
      requesterSessionKey: "agent:main:subagent:parent",
      requesterDisplayKey: "agent:main:subagent:parent",
    });

    (expect* didAnnounce).is(false);
    (expect* 
      findGatewayCall((call) => call.method === "agent" && call.expectFinal === true),
    ).toBeUndefined();
  });

  (deftest "regression, supports cron announceType without declaration order errors", async () => {
    const didAnnounce = await runAnnounceFlowForTest("run-announce-type", {
      announceType: "cron job",
      expectsCompletionMessage: true,
      requesterOrigin: { channel: "discord", to: "channel:cron" },
    });

    (expect* didAnnounce).is(true);
    const directAgentCall = findGatewayCall(
      (call) => call.method === "agent" && call.expectFinal === true,
    );
    const internalEvents =
      (directAgentCall?.params?.internalEvents as Array<{ announceType?: string }>) ?? [];
    (expect* internalEvents[0]?.announceType).is("cron job");
  });

  (deftest "regression, routes child announce to parent session instead of grandparent when parent session still exists", async () => {
    const parentSessionKey = "agent:main:subagent:parent";
    requesterDepthResolver = (sessionKey?: string) =>
      sessionKey === parentSessionKey ? 1 : sessionKey?.includes(":subagent:") ? 1 : 0;
    subagentSessionRunActive = false;
    shouldIgnorePostCompletion = false;
    fallbackRequesterResolution = {
      requesterSessionKey: "agent:main:main",
      requesterOrigin: { channel: "discord", to: "chan-main", accountId: "acct-main" },
    };
    // No sessionId on purpose: existence in store should still count as alive.
    sessionStore[parentSessionKey] = { updatedAt: Date.now() };

    await runAnnounceFlowForTest("run-parent-route", {
      requesterSessionKey: parentSessionKey,
      requesterDisplayKey: parentSessionKey,
      childSessionKey: `${parentSessionKey}:subagent:child`,
    });

    const directAgentCall = findGatewayCall(
      (call) => call.method === "agent" && call.expectFinal === true,
    );
    (expect* directAgentCall?.params?.sessionKey).is(parentSessionKey);
    (expect* directAgentCall?.params?.deliver).is(false);
  });

  (deftest "regression, falls back to grandparent only when parent subagent session is missing", async () => {
    const parentSessionKey = "agent:main:subagent:parent-missing";
    requesterDepthResolver = (sessionKey?: string) =>
      sessionKey === parentSessionKey ? 1 : sessionKey?.includes(":subagent:") ? 1 : 0;
    subagentSessionRunActive = false;
    shouldIgnorePostCompletion = false;
    fallbackRequesterResolution = {
      requesterSessionKey: "agent:main:main",
      requesterOrigin: { channel: "discord", to: "chan-main", accountId: "acct-main" },
    };

    await runAnnounceFlowForTest("run-parent-fallback", {
      requesterSessionKey: parentSessionKey,
      requesterDisplayKey: parentSessionKey,
      childSessionKey: `${parentSessionKey}:subagent:child`,
    });

    const directAgentCall = findGatewayCall(
      (call) => call.method === "agent" && call.expectFinal === true,
    );
    (expect* directAgentCall?.params?.sessionKey).is("agent:main:main");
    (expect* directAgentCall?.params?.deliver).is(true);
    (expect* directAgentCall?.params?.channel).is("discord");
    (expect* directAgentCall?.params?.to).is("chan-main");
    (expect* directAgentCall?.params?.accountId).is("acct-main");
  });
});
