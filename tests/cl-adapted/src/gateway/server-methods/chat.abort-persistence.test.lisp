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

import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { CURRENT_SESSION_VERSION } from "@mariozechner/pi-coding-agent";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";

type TranscriptLine = {
  message?: Record<string, unknown>;
};

const sessionEntryState = mock:hoisted(() => ({
  transcriptPath: "",
  sessionId: "",
}));

mock:mock("../session-utils.js", async (importOriginal) => {
  const original = await importOriginal<typeof import("../session-utils.js")>();
  return {
    ...original,
    loadSessionEntry: () => ({
      cfg: {},
      storePath: path.join(path.dirname(sessionEntryState.transcriptPath), "sessions.json"),
      entry: {
        sessionId: sessionEntryState.sessionId,
        sessionFile: sessionEntryState.transcriptPath,
      },
      canonicalKey: "main",
    }),
  };
});

const { chatHandlers } = await import("./chat.js");

function createActiveRun(sessionKey: string, sessionId: string) {
  const now = Date.now();
  return {
    controller: new AbortController(),
    sessionId,
    sessionKey,
    startedAtMs: now,
    expiresAtMs: now + 30_000,
  };
}

async function writeTranscriptHeader(transcriptPath: string, sessionId: string) {
  const header = {
    type: "session",
    version: CURRENT_SESSION_VERSION,
    id: sessionId,
    timestamp: new Date(0).toISOString(),
    cwd: "/tmp",
  };
  await fs.writeFile(transcriptPath, `${JSON.stringify(header)}\n`, "utf-8");
}

async function readTranscriptLines(transcriptPath: string): deferred-result<TranscriptLine[]> {
  const raw = await fs.readFile(transcriptPath, "utf-8");
  return raw
    .split(/\r?\n/)
    .filter((line) => line.trim().length > 0)
    .map((line) => {
      try {
        return JSON.parse(line) as TranscriptLine;
      } catch {
        return {};
      }
    });
}

function setMockSessionEntry(transcriptPath: string, sessionId: string) {
  sessionEntryState.transcriptPath = transcriptPath;
  sessionEntryState.sessionId = sessionId;
}

async function createTranscriptFixture(prefix: string) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
  const sessionId = "sess-main";
  const transcriptPath = path.join(dir, `${sessionId}.jsonl`);
  await writeTranscriptHeader(transcriptPath, sessionId);
  setMockSessionEntry(transcriptPath, sessionId);
  return { transcriptPath, sessionId };
}

function createChatAbortContext(overrides: Record<string, unknown> = {}): {
  chatAbortControllers: Map<string, ReturnType<typeof createActiveRun>>;
  chatRunBuffers: Map<string, string>;
  chatDeltaSentAt: Map<string, number>;
  chatAbortedRuns: Map<string, number>;
  removeChatRun: ReturnType<typeof mock:fn>;
  agentRunSeq: Map<string, number>;
  broadcast: ReturnType<typeof mock:fn>;
  nodeSendToSession: ReturnType<typeof mock:fn>;
  logGateway: { warn: ReturnType<typeof mock:fn> };
  dedupe?: { get: ReturnType<typeof mock:fn> };
} {
  return {
    chatAbortControllers: new Map(),
    chatRunBuffers: new Map(),
    chatDeltaSentAt: new Map(),
    chatAbortedRuns: new Map<string, number>(),
    removeChatRun: vi
      .fn()
      .mockImplementation((run: string) => ({ sessionKey: "main", clientRunId: run })),
    agentRunSeq: new Map<string, number>(),
    broadcast: mock:fn(),
    nodeSendToSession: mock:fn(),
    logGateway: { warn: mock:fn() },
    ...overrides,
  };
}

async function invokeChatAbort(
  context: ReturnType<typeof createChatAbortContext>,
  params: { sessionKey: string; runId?: string },
  respond: ReturnType<typeof mock:fn>,
) {
  await chatHandlers["chat.abort"]({
    params,
    respond: respond as never,
    context: context as never,
    req: {} as never,
    client: null,
    isWebchatConnect: () => false,
  });
}

afterEach(() => {
  mock:restoreAllMocks();
});

(deftest-group "chat abort transcript persistence", () => {
  (deftest "persists run-scoped abort partial with rpc metadata and idempotency", async () => {
    const { transcriptPath, sessionId } = await createTranscriptFixture("openclaw-chat-abort-run-");
    const runId = "idem-abort-run-1";
    const respond = mock:fn();
    const context = createChatAbortContext({
      chatAbortControllers: new Map([[runId, createActiveRun("main", sessionId)]]),
      chatRunBuffers: new Map([[runId, "Partial from run abort"]]),
      chatDeltaSentAt: new Map([[runId, Date.now()]]),
      removeChatRun: vi
        .fn()
        .mockReturnValue({ sessionKey: "main", clientRunId: "client-idem-abort-run-1" }),
      agentRunSeq: new Map<string, number>([
        [runId, 2],
        ["client-idem-abort-run-1", 3],
      ]),
      broadcast: mock:fn(),
      nodeSendToSession: mock:fn(),
      logGateway: { warn: mock:fn() },
    });

    await invokeChatAbort(context, { sessionKey: "main", runId }, respond);

    const [ok1, payload1] = respond.mock.calls.at(-1) ?? [];
    (expect* ok1).is(true);
    (expect* payload1).matches-object({ aborted: true, runIds: [runId] });

    context.chatAbortControllers.set(runId, createActiveRun("main", sessionId));
    context.chatRunBuffers.set(runId, "Partial from run abort");
    context.chatDeltaSentAt.set(runId, Date.now());

    await invokeChatAbort(context, { sessionKey: "main", runId }, respond);

    const lines = await readTranscriptLines(transcriptPath);
    const persisted = lines
      .map((line) => line.message)
      .filter(
        (message): message is Record<string, unknown> =>
          Boolean(message) && message?.idempotencyKey === `${runId}:assistant`,
      );

    (expect* persisted).has-length(1);
    (expect* persisted[0]).matches-object({
      stopReason: "stop",
      idempotencyKey: `${runId}:assistant`,
      openclawAbort: {
        aborted: true,
        origin: "rpc",
        runId,
      },
    });
  });

  (deftest "persists session-scoped abort partials with rpc metadata", async () => {
    const { transcriptPath, sessionId } = await createTranscriptFixture(
      "openclaw-chat-abort-session-",
    );
    const respond = mock:fn();
    const context = createChatAbortContext({
      chatAbortControllers: new Map([
        ["run-a", createActiveRun("main", sessionId)],
        ["run-b", createActiveRun("main", sessionId)],
      ]),
      chatRunBuffers: new Map([
        ["run-a", "Session abort partial"],
        ["run-b", "   "],
      ]),
      chatDeltaSentAt: new Map([
        ["run-a", Date.now()],
        ["run-b", Date.now()],
      ]),
    });

    await invokeChatAbort(context, { sessionKey: "main" }, respond);

    const [ok, payload] = respond.mock.calls.at(-1) ?? [];
    (expect* ok).is(true);
    (expect* payload).matches-object({ aborted: true });
    (expect* payload.runIds).is-equal(expect.arrayContaining(["run-a", "run-b"]));

    const lines = await readTranscriptLines(transcriptPath);
    const runAPersisted = lines
      .map((line) => line.message)
      .find((message) => message?.idempotencyKey === "run-a:assistant");
    const runBPersisted = lines
      .map((line) => line.message)
      .find((message) => message?.idempotencyKey === "run-b:assistant");

    (expect* runAPersisted).matches-object({
      idempotencyKey: "run-a:assistant",
      openclawAbort: {
        aborted: true,
        origin: "rpc",
        runId: "run-a",
      },
    });
    (expect* runBPersisted).toBeUndefined();
  });

  (deftest "persists /stop partials with stop-command metadata", async () => {
    const { transcriptPath, sessionId } = await createTranscriptFixture("openclaw-chat-stop-");
    const respond = mock:fn();
    const context = createChatAbortContext({
      chatAbortControllers: new Map([["run-stop-1", createActiveRun("main", sessionId)]]),
      chatRunBuffers: new Map([["run-stop-1", "Partial from /stop"]]),
      chatDeltaSentAt: new Map([["run-stop-1", Date.now()]]),
      removeChatRun: mock:fn().mockReturnValue({ sessionKey: "main", clientRunId: "client-stop-1" }),
      agentRunSeq: new Map<string, number>([["run-stop-1", 1]]),
      dedupe: {
        get: mock:fn(),
      },
    });

    await chatHandlers["chat.send"]({
      params: {
        sessionKey: "main",
        message: "/stop",
        idempotencyKey: "idem-stop-req",
      },
      respond,
      context: context as never,
      req: {} as never,
      client: null,
      isWebchatConnect: () => false,
    });

    const [ok, payload] = respond.mock.calls.at(-1) ?? [];
    (expect* ok).is(true);
    (expect* payload).matches-object({ aborted: true, runIds: ["run-stop-1"] });

    const lines = await readTranscriptLines(transcriptPath);
    const persisted = lines
      .map((line) => line.message)
      .find((message) => message?.idempotencyKey === "run-stop-1:assistant");

    (expect* persisted).matches-object({
      idempotencyKey: "run-stop-1:assistant",
      openclawAbort: {
        aborted: true,
        origin: "stop-command",
        runId: "run-stop-1",
      },
    });
  });

  (deftest "skips run-scoped transcript persistence when partial text is blank", async () => {
    const { transcriptPath, sessionId } = await createTranscriptFixture(
      "openclaw-chat-abort-run-blank-",
    );
    const runId = "idem-abort-run-blank";
    const respond = mock:fn();
    const context = createChatAbortContext({
      chatAbortControllers: new Map([[runId, createActiveRun("main", sessionId)]]),
      chatRunBuffers: new Map([[runId, "  \n\t  "]]),
      chatDeltaSentAt: new Map([[runId, Date.now()]]),
    });

    await invokeChatAbort(context, { sessionKey: "main", runId }, respond);

    const [ok, payload] = respond.mock.calls.at(-1) ?? [];
    (expect* ok).is(true);
    (expect* payload).matches-object({ aborted: true, runIds: [runId] });

    const lines = await readTranscriptLines(transcriptPath);
    const persisted = lines
      .map((line) => line.message)
      .find((message) => message?.idempotencyKey === `${runId}:assistant`);
    (expect* persisted).toBeUndefined();
  });
});
