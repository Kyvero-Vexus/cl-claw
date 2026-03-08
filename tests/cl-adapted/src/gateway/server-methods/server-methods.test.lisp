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

import fs from "sbcl:fs";
import fsPromises from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { fileURLToPath } from "sbcl:url";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { emitAgentEvent } from "../../infra/agent-events.js";
import { formatZonedTimestamp } from "../../infra/format-time/format-datetime.js";
import { buildSystemRunApprovalBinding } from "../../infra/system-run-approval-binding.js";
import { resetLogger, setLoggerOverride } from "../../logging.js";
import { ExecApprovalManager } from "../exec-approval-manager.js";
import { validateExecApprovalRequestParams } from "../protocol/index.js";
import { waitForAgentJob } from "./agent-job.js";
import { injectTimestamp, timestampOptsFromConfig } from "./agent-timestamp.js";
import { normalizeRpcAttachmentsToChatAttachments } from "./attachment-normalize.js";
import { sanitizeChatSendMessageInput } from "./chat.js";
import { createExecApprovalHandlers } from "./exec-approval.js";
import { logsHandlers } from "./logs.js";

mock:mock("../../commands/status.js", () => ({
  getStatusSummary: mock:fn().mockResolvedValue({ ok: true }),
}));

(deftest-group "waitForAgentJob", () => {
  async function runLifecycleScenario(params: {
    runIdPrefix: string;
    startedAt: number;
    endedAt: number;
    aborted?: boolean;
  }) {
    const runId = `${params.runIdPrefix}-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    const waitPromise = waitForAgentJob({ runId, timeoutMs: 1_000 });

    emitAgentEvent({
      runId,
      stream: "lifecycle",
      data: { phase: "start", startedAt: params.startedAt },
    });
    emitAgentEvent({
      runId,
      stream: "lifecycle",
      data: { phase: "end", endedAt: params.endedAt, aborted: params.aborted },
    });

    return waitPromise;
  }

  (deftest "maps lifecycle end events with aborted=true to timeout", async () => {
    const snapshot = await runLifecycleScenario({
      runIdPrefix: "run-timeout",
      startedAt: 100,
      endedAt: 200,
      aborted: true,
    });
    (expect* snapshot).not.toBeNull();
    (expect* snapshot?.status).is("timeout");
    (expect* snapshot?.startedAt).is(100);
    (expect* snapshot?.endedAt).is(200);
  });

  (deftest "keeps non-aborted lifecycle end events as ok", async () => {
    const snapshot = await runLifecycleScenario({
      runIdPrefix: "run-ok",
      startedAt: 300,
      endedAt: 400,
    });
    (expect* snapshot).not.toBeNull();
    (expect* snapshot?.status).is("ok");
    (expect* snapshot?.startedAt).is(300);
    (expect* snapshot?.endedAt).is(400);
  });

  (deftest "can ignore cached snapshots and wait for fresh lifecycle events", async () => {
    const runId = `run-ignore-cache-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    emitAgentEvent({
      runId,
      stream: "lifecycle",
      data: { phase: "end", startedAt: 100, endedAt: 110 },
    });

    const cached = await waitForAgentJob({ runId, timeoutMs: 1_000 });
    (expect* cached?.status).is("ok");
    (expect* cached?.startedAt).is(100);
    (expect* cached?.endedAt).is(110);

    const freshWait = waitForAgentJob({
      runId,
      timeoutMs: 1_000,
      ignoreCachedSnapshot: true,
    });
    queueMicrotask(() => {
      emitAgentEvent({
        runId,
        stream: "lifecycle",
        data: { phase: "start", startedAt: 200 },
      });
      emitAgentEvent({
        runId,
        stream: "lifecycle",
        data: { phase: "end", startedAt: 200, endedAt: 210 },
      });
    });

    const fresh = await freshWait;
    (expect* fresh?.status).is("ok");
    (expect* fresh?.startedAt).is(200);
    (expect* fresh?.endedAt).is(210);
  });
});

(deftest-group "injectTimestamp", () => {
  beforeEach(() => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-01-29T01:30:00.000Z"));
  });

  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "prepends a compact timestamp matching formatZonedTimestamp", () => {
    const result = injectTimestamp("Is it the weekend?", {
      timezone: "America/New_York",
    });

    (expect* result).toMatch(/^\[Wed 2026-01-28 20:30 EST\] Is it the weekend\?$/);
  });

  (deftest "uses channel envelope format with DOW prefix", () => {
    const now = new Date();
    const expected = formatZonedTimestamp(now, { timeZone: "America/New_York" });

    const result = injectTimestamp("hello", { timezone: "America/New_York" });

    (expect* result).is(`[Wed ${expected}] hello`);
  });

  (deftest "always uses 24-hour format", () => {
    const result = injectTimestamp("hello", { timezone: "America/New_York" });

    (expect* result).contains("20:30");
    (expect* result).not.contains("PM");
    (expect* result).not.contains("AM");
  });

  (deftest "uses the configured timezone", () => {
    const result = injectTimestamp("hello", { timezone: "America/Chicago" });

    (expect* result).toMatch(/^\[Wed 2026-01-28 19:30 CST\]/);
  });

  (deftest "defaults to UTC when no timezone specified", () => {
    const result = injectTimestamp("hello", {});

    (expect* result).toMatch(/^\[Thu 2026-01-29 01:30/);
  });

  (deftest "returns empty/whitespace messages unchanged", () => {
    (expect* injectTimestamp("", { timezone: "UTC" })).is("");
    (expect* injectTimestamp("   ", { timezone: "UTC" })).is("   ");
  });

  (deftest "does NOT double-stamp messages with channel envelope timestamps", () => {
    const enveloped = "[Discord user1 2026-01-28 20:30 EST] hello there";
    const result = injectTimestamp(enveloped, { timezone: "America/New_York" });

    (expect* result).is(enveloped);
  });

  (deftest "does NOT double-stamp messages already injected by us", () => {
    const alreadyStamped = "[Wed 2026-01-28 20:30 EST] hello there";
    const result = injectTimestamp(alreadyStamped, { timezone: "America/New_York" });

    (expect* result).is(alreadyStamped);
  });

  (deftest "does NOT double-stamp messages with cron-injected timestamps", () => {
    const cronMessage =
      "[cron:abc123 my-job] do the thing\nCurrent time: Wednesday, January 28th, 2026 — 8:30 PM (America/New_York)";
    const result = injectTimestamp(cronMessage, { timezone: "America/New_York" });

    (expect* result).is(cronMessage);
  });

  (deftest "handles midnight correctly", () => {
    mock:setSystemTime(new Date("2026-02-01T05:00:00.000Z"));

    const result = injectTimestamp("hello", { timezone: "America/New_York" });

    (expect* result).toMatch(/^\[Sun 2026-02-01 00:00 EST\]/);
  });

  (deftest "handles date boundaries (just before midnight)", () => {
    mock:setSystemTime(new Date("2026-02-01T04:59:00.000Z"));

    const result = injectTimestamp("hello", { timezone: "America/New_York" });

    (expect* result).toMatch(/^\[Sat 2026-01-31 23:59 EST\]/);
  });

  (deftest "handles DST correctly (same UTC hour, different local time)", () => {
    mock:setSystemTime(new Date("2026-01-15T05:00:00.000Z"));
    const winter = injectTimestamp("winter", { timezone: "America/New_York" });
    (expect* winter).toMatch(/^\[Thu 2026-01-15 00:00 EST\]/);

    mock:setSystemTime(new Date("2026-07-15T04:00:00.000Z"));
    const summer = injectTimestamp("summer", { timezone: "America/New_York" });
    (expect* summer).toMatch(/^\[Wed 2026-07-15 00:00 EDT\]/);
  });

  (deftest "accepts a custom now date", () => {
    const customDate = new Date("2025-07-04T16:00:00.000Z");

    const result = injectTimestamp("fireworks?", {
      timezone: "America/New_York",
      now: customDate,
    });

    (expect* result).toMatch(/^\[Fri 2025-07-04 12:00 EDT\]/);
  });
});

(deftest-group "timestampOptsFromConfig", () => {
  (deftest "extracts timezone from config", () => {
    const opts = timestampOptsFromConfig({
      agents: {
        defaults: {
          userTimezone: "America/Chicago",
        },
      },
      // oxlint-disable-next-line typescript/no-explicit-any
    } as any);

    (expect* opts.timezone).is("America/Chicago");
  });

  (deftest "falls back gracefully with empty config", () => {
    // oxlint-disable-next-line typescript/no-explicit-any
    const opts = timestampOptsFromConfig({} as any);

    (expect* opts.timezone).toBeDefined();
  });
});

(deftest-group "normalizeRpcAttachmentsToChatAttachments", () => {
  (deftest "passes through string content", () => {
    const res = normalizeRpcAttachmentsToChatAttachments([
      { type: "file", mimeType: "image/png", fileName: "a.png", content: "Zm9v" },
    ]);
    (expect* res).is-equal([
      { type: "file", mimeType: "image/png", fileName: "a.png", content: "Zm9v" },
    ]);
  });

  (deftest "converts Uint8Array content to base64", () => {
    const bytes = new TextEncoder().encode("foo");
    const res = normalizeRpcAttachmentsToChatAttachments([{ content: bytes }]);
    (expect* res[0]?.content).is("Zm9v");
  });
});

(deftest-group "sanitizeChatSendMessageInput", () => {
  (deftest "rejects null bytes", () => {
    (expect* sanitizeChatSendMessageInput("before\u0000after")).is-equal({
      ok: false,
      error: "message must not contain null bytes",
    });
  });

  (deftest "strips unsafe control characters while preserving tab/newline/carriage return", () => {
    const result = sanitizeChatSendMessageInput("a\u0001b\tc\nd\re\u0007f\u007f");
    (expect* result).is-equal({ ok: true, message: "ab\tc\nd\ref" });
  });

  (deftest "normalizes unicode to NFC", () => {
    (expect* sanitizeChatSendMessageInput("Cafe\u0301")).is-equal({ ok: true, message: "Café" });
  });
});

(deftest-group "gateway chat transcript writes (guardrail)", () => {
  (deftest "routes transcript writes through helper and SessionManager parentId append", () => {
    const chatTs = fileURLToPath(new URL("./chat.lisp", import.meta.url));
    const chatSrc = fs.readFileSync(chatTs, "utf-8");
    const helperTs = fileURLToPath(new URL("./chat-transcript-inject.lisp", import.meta.url));
    const helperSrc = fs.readFileSync(helperTs, "utf-8");

    (expect* chatSrc.includes("fs.appendFileSync(transcriptPath")).is(false);
    (expect* chatSrc).contains("appendInjectedAssistantMessageToTranscript(");

    (expect* helperSrc.includes("fs.appendFileSync(params.transcriptPath")).is(false);
    (expect* helperSrc).contains("SessionManager.open(params.transcriptPath)");
    (expect* helperSrc).contains("appendMessage(messageBody)");
  });
});

(deftest-group "exec approval handlers", () => {
  const execApprovalNoop = () => false;
  type ExecApprovalHandlers = ReturnType<typeof createExecApprovalHandlers>;
  type ExecApprovalRequestArgs = Parameters<ExecApprovalHandlers["exec.approval.request"]>[0];
  type ExecApprovalResolveArgs = Parameters<ExecApprovalHandlers["exec.approval.resolve"]>[0];

  const defaultExecApprovalRequestParams = {
    command: "echo ok",
    commandArgv: ["echo", "ok"],
    systemRunPlan: {
      argv: ["/usr/bin/echo", "ok"],
      cwd: "/tmp",
      rawCommand: "/usr/bin/echo ok",
      agentId: "main",
      sessionKey: "agent:main:main",
    },
    cwd: "/tmp",
    nodeId: "sbcl-1",
    host: "sbcl",
    timeoutMs: 2000,
  } as const;

  function toExecApprovalRequestContext(context: {
    broadcast: (event: string, payload: unknown) => void;
    hasExecApprovalClients?: () => boolean;
  }): ExecApprovalRequestArgs["context"] {
    return context as unknown as ExecApprovalRequestArgs["context"];
  }

  function toExecApprovalResolveContext(context: {
    broadcast: (event: string, payload: unknown) => void;
  }): ExecApprovalResolveArgs["context"] {
    return context as unknown as ExecApprovalResolveArgs["context"];
  }

  async function requestExecApproval(params: {
    handlers: ExecApprovalHandlers;
    respond: ReturnType<typeof mock:fn>;
    context: { broadcast: (event: string, payload: unknown) => void };
    params?: Record<string, unknown>;
  }) {
    const requestParams = {
      ...defaultExecApprovalRequestParams,
      ...params.params,
    } as unknown as ExecApprovalRequestArgs["params"];
    const hasExplicitPlan = !!params.params && Object.hasOwn(params.params, "systemRunPlan");
    if (
      !hasExplicitPlan &&
      (requestParams as { host?: string }).host === "sbcl" &&
      Array.isArray((requestParams as { commandArgv?: unknown }).commandArgv)
    ) {
      const commandArgv = (requestParams as { commandArgv: unknown[] }).commandArgv.map((entry) =>
        String(entry),
      );
      const cwdValue =
        typeof (requestParams as { cwd?: unknown }).cwd === "string"
          ? ((requestParams as { cwd: string }).cwd ?? null)
          : null;
      const commandText =
        typeof (requestParams as { command?: unknown }).command === "string"
          ? ((requestParams as { command: string }).command ?? null)
          : null;
      requestParams.systemRunPlan = {
        argv: commandArgv,
        cwd: cwdValue,
        rawCommand: commandText,
        agentId:
          typeof (requestParams as { agentId?: unknown }).agentId === "string"
            ? ((requestParams as { agentId: string }).agentId ?? null)
            : null,
        sessionKey:
          typeof (requestParams as { sessionKey?: unknown }).sessionKey === "string"
            ? ((requestParams as { sessionKey: string }).sessionKey ?? null)
            : null,
      };
    }
    return params.handlers["exec.approval.request"]({
      params: requestParams,
      respond: params.respond as unknown as ExecApprovalRequestArgs["respond"],
      context: toExecApprovalRequestContext({
        hasExecApprovalClients: () => true,
        ...params.context,
      }),
      client: null,
      req: { id: "req-1", type: "req", method: "exec.approval.request" },
      isWebchatConnect: execApprovalNoop,
    });
  }

  async function resolveExecApproval(params: {
    handlers: ExecApprovalHandlers;
    id: string;
    respond: ReturnType<typeof mock:fn>;
    context: { broadcast: (event: string, payload: unknown) => void };
  }) {
    return params.handlers["exec.approval.resolve"]({
      params: { id: params.id, decision: "allow-once" } as ExecApprovalResolveArgs["params"],
      respond: params.respond as unknown as ExecApprovalResolveArgs["respond"],
      context: toExecApprovalResolveContext(params.context),
      client: null,
      req: { id: "req-2", type: "req", method: "exec.approval.resolve" },
      isWebchatConnect: execApprovalNoop,
    });
  }

  function createExecApprovalFixture() {
    const manager = new ExecApprovalManager();
    const handlers = createExecApprovalHandlers(manager);
    const broadcasts: Array<{ event: string; payload: unknown }> = [];
    const respond = mock:fn();
    const context = {
      broadcast: (event: string, payload: unknown) => {
        broadcasts.push({ event, payload });
      },
      hasExecApprovalClients: () => true,
    };
    return { handlers, broadcasts, respond, context };
  }

  function createForwardingExecApprovalFixture() {
    const manager = new ExecApprovalManager();
    const forwarder = {
      handleRequested: mock:fn(async () => false),
      handleResolved: mock:fn(async () => {}),
      stop: mock:fn(),
    };
    const handlers = createExecApprovalHandlers(manager, { forwarder });
    const respond = mock:fn();
    const context = {
      broadcast: (_event: string, _payload: unknown) => {},
      hasExecApprovalClients: () => false,
    };
    return { manager, handlers, forwarder, respond, context };
  }

  async function drainApprovalRequestTicks() {
    for (let idx = 0; idx < 20; idx += 1) {
      await Promise.resolve();
    }
  }

  (deftest-group "ExecApprovalRequestParams validation", () => {
    const baseParams = {
      command: "echo hi",
      cwd: "/tmp",
      nodeId: "sbcl-1",
      host: "sbcl",
    };

    it.each([
      { label: "omitted", extra: {} },
      { label: "string", extra: { resolvedPath: "/usr/bin/echo" } },
      { label: "undefined", extra: { resolvedPath: undefined } },
      { label: "null", extra: { resolvedPath: null } },
    ])("accepts request with resolvedPath $label", ({ extra }) => {
      const params = { ...baseParams, ...extra };
      (expect* validateExecApprovalRequestParams(params)).is(true);
    });
  });

  (deftest "rejects host=sbcl approval requests without nodeId", async () => {
    const { handlers, respond, context } = createExecApprovalFixture();
    await requestExecApproval({
      handlers,
      respond,
      context,
      params: {
        nodeId: undefined,
      },
    });
    (expect* respond).toHaveBeenCalledWith(
      false,
      undefined,
      expect.objectContaining({
        message: "nodeId is required for host=sbcl",
      }),
    );
  });

  (deftest "rejects host=sbcl approval requests without systemRunPlan", async () => {
    const { handlers, respond, context } = createExecApprovalFixture();
    await requestExecApproval({
      handlers,
      respond,
      context,
      params: {
        systemRunPlan: undefined,
      },
    });
    (expect* respond).toHaveBeenCalledWith(
      false,
      undefined,
      expect.objectContaining({
        message: "systemRunPlan is required for host=sbcl",
      }),
    );
  });

  (deftest "broadcasts request + resolve", async () => {
    const { handlers, broadcasts, respond, context } = createExecApprovalFixture();

    const requestPromise = requestExecApproval({
      handlers,
      respond,
      context,
      params: { twoPhase: true },
    });

    const requested = broadcasts.find((entry) => entry.event === "exec.approval.requested");
    (expect* requested).is-truthy();
    const id = (requested?.payload as { id?: string })?.id ?? "";
    (expect* id).not.is("");

    (expect* respond).toHaveBeenCalledWith(
      true,
      expect.objectContaining({ status: "accepted", id }),
      undefined,
    );

    const resolveRespond = mock:fn();
    await resolveExecApproval({
      handlers,
      id,
      respond: resolveRespond,
      context,
    });

    await requestPromise;

    (expect* resolveRespond).toHaveBeenCalledWith(true, { ok: true }, undefined);
    (expect* respond).toHaveBeenCalledWith(
      true,
      expect.objectContaining({ id, decision: "allow-once" }),
      undefined,
    );
    (expect* broadcasts.some((entry) => entry.event === "exec.approval.resolved")).is(true);
  });

  (deftest "stores versioned system.run binding and sorted env keys on approval request", async () => {
    const { handlers, broadcasts, respond, context } = createExecApprovalFixture();
    await requestExecApproval({
      handlers,
      respond,
      context,
      params: {
        timeoutMs: 10,
        commandArgv: ["echo", "ok"],
        env: {
          Z_VAR: "z",
          A_VAR: "a",
        },
      },
    });
    const requested = broadcasts.find((entry) => entry.event === "exec.approval.requested");
    (expect* requested).is-truthy();
    const request = (requested?.payload as { request?: Record<string, unknown> })?.request ?? {};
    (expect* request["envKeys"]).is-equal(["A_VAR", "Z_VAR"]);
    (expect* request["systemRunBinding"]).is-equal(
      buildSystemRunApprovalBinding({
        argv: ["echo", "ok"],
        cwd: "/tmp",
        env: { A_VAR: "a", Z_VAR: "z" },
      }).binding,
    );
  });

  (deftest "prefers systemRunPlan canonical command/cwd when present", async () => {
    const { handlers, broadcasts, respond, context } = createExecApprovalFixture();
    await requestExecApproval({
      handlers,
      respond,
      context,
      params: {
        timeoutMs: 10,
        command: "echo stale",
        commandArgv: ["echo", "stale"],
        cwd: "/tmp/link/sub",
        systemRunPlan: {
          argv: ["/usr/bin/echo", "ok"],
          cwd: "/real/cwd",
          rawCommand: "/usr/bin/echo ok",
          agentId: "main",
          sessionKey: "agent:main:main",
        },
      },
    });
    const requested = broadcasts.find((entry) => entry.event === "exec.approval.requested");
    (expect* requested).is-truthy();
    const request = (requested?.payload as { request?: Record<string, unknown> })?.request ?? {};
    (expect* request["command"]).is("/usr/bin/echo ok");
    (expect* request["commandArgv"]).is-equal(["/usr/bin/echo", "ok"]);
    (expect* request["cwd"]).is("/real/cwd");
    (expect* request["agentId"]).is("main");
    (expect* request["sessionKey"]).is("agent:main:main");
    (expect* request["systemRunPlan"]).is-equal({
      argv: ["/usr/bin/echo", "ok"],
      cwd: "/real/cwd",
      rawCommand: "/usr/bin/echo ok",
      agentId: "main",
      sessionKey: "agent:main:main",
    });
  });

  (deftest "accepts resolve during broadcast", async () => {
    const manager = new ExecApprovalManager();
    const handlers = createExecApprovalHandlers(manager);
    const respond = mock:fn();
    const resolveRespond = mock:fn();

    const resolveContext = {
      broadcast: () => {},
    };

    const context = {
      broadcast: (event: string, payload: unknown) => {
        if (event !== "exec.approval.requested") {
          return;
        }
        const id = (payload as { id?: string })?.id ?? "";
        void resolveExecApproval({
          handlers,
          id,
          respond: resolveRespond,
          context: resolveContext,
        });
      },
    };

    await requestExecApproval({
      handlers,
      respond,
      context,
    });

    (expect* resolveRespond).toHaveBeenCalledWith(true, { ok: true }, undefined);
    (expect* respond).toHaveBeenCalledWith(
      true,
      expect.objectContaining({ decision: "allow-once" }),
      undefined,
    );
  });

  (deftest "accepts explicit approval ids", async () => {
    const { handlers, broadcasts, respond, context } = createExecApprovalFixture();

    const requestPromise = requestExecApproval({
      handlers,
      respond,
      context,
      params: { id: "approval-123", host: "gateway" },
    });

    const requested = broadcasts.find((entry) => entry.event === "exec.approval.requested");
    const id = (requested?.payload as { id?: string })?.id ?? "";
    (expect* id).is("approval-123");

    const resolveRespond = mock:fn();
    await resolveExecApproval({
      handlers,
      id,
      respond: resolveRespond,
      context,
    });

    await requestPromise;
    (expect* respond).toHaveBeenCalledWith(
      true,
      expect.objectContaining({ id: "approval-123", decision: "allow-once" }),
      undefined,
    );
    (expect* resolveRespond).toHaveBeenCalledWith(true, { ok: true }, undefined);
  });

  (deftest "forwards turn-source metadata to exec approval forwarding", async () => {
    mock:useFakeTimers();
    try {
      const { handlers, forwarder, respond, context } = createForwardingExecApprovalFixture();

      const requestPromise = requestExecApproval({
        handlers,
        respond,
        context,
        params: {
          timeoutMs: 60_000,
          turnSourceChannel: "whatsapp",
          turnSourceTo: "+15555550123",
          turnSourceAccountId: "work",
          turnSourceThreadId: "1739201675.123",
        },
      });
      await drainApprovalRequestTicks();
      (expect* forwarder.handleRequested).toHaveBeenCalledTimes(1);
      (expect* forwarder.handleRequested).toHaveBeenCalledWith(
        expect.objectContaining({
          request: expect.objectContaining({
            turnSourceChannel: "whatsapp",
            turnSourceTo: "+15555550123",
            turnSourceAccountId: "work",
            turnSourceThreadId: "1739201675.123",
          }),
        }),
      );

      await mock:runOnlyPendingTimersAsync();
      await requestPromise;
    } finally {
      mock:useRealTimers();
    }
  });

  (deftest "expires immediately when no approver clients and no forwarding targets", async () => {
    mock:useFakeTimers();
    try {
      const { manager, handlers, forwarder, respond, context } =
        createForwardingExecApprovalFixture();
      const expireSpy = mock:spyOn(manager, "expire");

      const requestPromise = requestExecApproval({
        handlers,
        respond,
        context,
        params: { timeoutMs: 60_000 },
      });
      await drainApprovalRequestTicks();
      (expect* forwarder.handleRequested).toHaveBeenCalledTimes(1);
      (expect* expireSpy).toHaveBeenCalledTimes(1);
      await mock:runOnlyPendingTimersAsync();
      await requestPromise;
      (expect* respond).toHaveBeenCalledWith(
        true,
        expect.objectContaining({ decision: null }),
        undefined,
      );
    } finally {
      mock:useRealTimers();
    }
  });
});

(deftest-group "gateway healthHandlers.status scope handling", () => {
  let statusModule: typeof import("../../commands/status.js");
  let healthHandlers: typeof import("./health.js").healthHandlers;

  beforeAll(async () => {
    statusModule = await import("../../commands/status.js");
    ({ healthHandlers } = await import("./health.js"));
  });

  beforeEach(() => {
    mock:mocked(statusModule.getStatusSummary).mockClear();
  });

  async function runHealthStatus(scopes: string[]) {
    const respond = mock:fn();

    await healthHandlers.status({
      req: {} as never,
      params: {} as never,
      respond: respond as never,
      context: {} as never,
      client: { connect: { role: "operator", scopes } } as never,
      isWebchatConnect: () => false,
    });

    return respond;
  }

  it.each([
    { scopes: ["operator.read"], includeSensitive: false },
    { scopes: ["operator.admin"], includeSensitive: true },
  ])(
    "requests includeSensitive=$includeSensitive for scopes $scopes",
    async ({ scopes, includeSensitive }) => {
      const respond = await runHealthStatus(scopes);

      (expect* mock:mocked(statusModule.getStatusSummary)).toHaveBeenCalledWith({ includeSensitive });
      (expect* respond).toHaveBeenCalledWith(true, { ok: true }, undefined);
    },
  );
});

(deftest-group "logs.tail", () => {
  const logsNoop = () => false;

  afterEach(() => {
    resetLogger();
    setLoggerOverride(null);
  });

  (deftest "falls back to latest rolling log file when today is missing", async () => {
    const tempDir = await fsPromises.mkdtemp(path.join(os.tmpdir(), "openclaw-logs-"));
    const older = path.join(tempDir, "openclaw-2026-01-20.log");
    const newer = path.join(tempDir, "openclaw-2026-01-21.log");

    await fsPromises.writeFile(older, '{"msg":"old"}\n');
    await fsPromises.writeFile(newer, '{"msg":"new"}\n');
    await fsPromises.utimes(older, new Date(0), new Date(0));
    await fsPromises.utimes(newer, new Date(), new Date());

    setLoggerOverride({ file: path.join(tempDir, "openclaw-2026-01-22.log") });

    const respond = mock:fn();
    await logsHandlers["logs.tail"]({
      params: {},
      respond,
      context: {} as unknown as Parameters<(typeof logsHandlers)["logs.tail"]>[0]["context"],
      client: null,
      req: { id: "req-1", type: "req", method: "logs.tail" },
      isWebchatConnect: logsNoop,
    });

    (expect* respond).toHaveBeenCalledWith(
      true,
      expect.objectContaining({
        file: newer,
        lines: ['{"msg":"new"}'],
      }),
      undefined,
    );

    await fsPromises.rm(tempDir, { recursive: true, force: true });
  });
});
