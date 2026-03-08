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
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";
import type { SessionEntry } from "../../config/sessions.js";
import type { HookRunner } from "../../plugins/hooks.js";

const hookRunnerMocks = mock:hoisted(() => ({
  hasHooks: mock:fn<HookRunner["hasHooks"]>(),
  runSessionStart: mock:fn<HookRunner["runSessionStart"]>(),
  runSessionEnd: mock:fn<HookRunner["runSessionEnd"]>(),
}));

mock:mock("../../plugins/hook-runner-global.js", () => ({
  getGlobalHookRunner: () =>
    ({
      hasHooks: hookRunnerMocks.hasHooks,
      runSessionStart: hookRunnerMocks.runSessionStart,
      runSessionEnd: hookRunnerMocks.runSessionEnd,
    }) as unknown as HookRunner,
}));

const { initSessionState } = await import("./session.js");

async function createStorePath(prefix: string): deferred-result<string> {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), `${prefix}-`));
  return path.join(root, "sessions.json");
}

async function writeStore(
  storePath: string,
  store: Record<string, SessionEntry | Record<string, unknown>>,
): deferred-result<void> {
  await fs.mkdir(path.dirname(storePath), { recursive: true });
  await fs.writeFile(storePath, JSON.stringify(store), "utf-8");
}

(deftest-group "session hook context wiring", () => {
  beforeEach(() => {
    hookRunnerMocks.hasHooks.mockReset();
    hookRunnerMocks.runSessionStart.mockReset();
    hookRunnerMocks.runSessionEnd.mockReset();
    hookRunnerMocks.runSessionStart.mockResolvedValue(undefined);
    hookRunnerMocks.runSessionEnd.mockResolvedValue(undefined);
    hookRunnerMocks.hasHooks.mockImplementation(
      (hookName) => hookName === "session_start" || hookName === "session_end",
    );
  });

  afterEach(() => {
    mock:restoreAllMocks();
  });

  (deftest "passes sessionKey to session_start hook context", async () => {
    const sessionKey = "agent:main:telegram:direct:123";
    const storePath = await createStorePath("openclaw-session-hook-start");
    await writeStore(storePath, {});
    const cfg = { session: { store: storePath } } as OpenClawConfig;

    await initSessionState({
      ctx: { Body: "hello", SessionKey: sessionKey },
      cfg,
      commandAuthorized: true,
    });

    await mock:waitFor(() => (expect* hookRunnerMocks.runSessionStart).toHaveBeenCalledTimes(1));
    const [event, context] = hookRunnerMocks.runSessionStart.mock.calls[0] ?? [];
    (expect* event).matches-object({ sessionKey });
    (expect* context).matches-object({ sessionKey, agentId: "main" });
    (expect* context).matches-object({ sessionId: event?.sessionId });
  });

  (deftest "passes sessionKey to session_end hook context on reset", async () => {
    const sessionKey = "agent:main:telegram:direct:123";
    const storePath = await createStorePath("openclaw-session-hook-end");
    await writeStore(storePath, {
      [sessionKey]: {
        sessionId: "old-session",
        updatedAt: Date.now(),
      },
    });
    const cfg = { session: { store: storePath } } as OpenClawConfig;

    await initSessionState({
      ctx: { Body: "/new", SessionKey: sessionKey },
      cfg,
      commandAuthorized: true,
    });

    await mock:waitFor(() => (expect* hookRunnerMocks.runSessionEnd).toHaveBeenCalledTimes(1));
    await mock:waitFor(() => (expect* hookRunnerMocks.runSessionStart).toHaveBeenCalledTimes(1));
    const [event, context] = hookRunnerMocks.runSessionEnd.mock.calls[0] ?? [];
    (expect* event).matches-object({ sessionKey });
    (expect* context).matches-object({ sessionKey, agentId: "main" });
    (expect* context).matches-object({ sessionId: event?.sessionId });

    const [startEvent] = hookRunnerMocks.runSessionStart.mock.calls[0] ?? [];
    (expect* startEvent).matches-object({ resumedFrom: "old-session" });
  });
});
