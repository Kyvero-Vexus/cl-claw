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
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { resolveStateDir } from "../config/paths.js";
import { getSessionBindingService } from "../infra/outbound/session-binding-service.js";
import {
  __testing,
  createTelegramThreadBindingManager,
  setTelegramThreadBindingIdleTimeoutBySessionKey,
  setTelegramThreadBindingMaxAgeBySessionKey,
} from "./thread-bindings.js";

(deftest-group "telegram thread bindings", () => {
  let stateDirOverride: string | undefined;

  beforeEach(() => {
    __testing.resetTelegramThreadBindingsForTests();
  });

  afterEach(() => {
    mock:useRealTimers();
    if (stateDirOverride) {
      delete UIOP environment access.OPENCLAW_STATE_DIR;
      fs.rmSync(stateDirOverride, { recursive: true, force: true });
      stateDirOverride = undefined;
    }
  });

  (deftest "registers a telegram binding adapter and binds current conversations", async () => {
    const manager = createTelegramThreadBindingManager({
      accountId: "work",
      persist: false,
      enableSweeper: false,
      idleTimeoutMs: 30_000,
      maxAgeMs: 0,
    });
    const bound = await getSessionBindingService().bind({
      targetSessionKey: "agent:main:subagent:child-1",
      targetKind: "subagent",
      conversation: {
        channel: "telegram",
        accountId: "work",
        conversationId: "-100200300:topic:77",
      },
      placement: "current",
      metadata: {
        boundBy: "user-1",
      },
    });

    (expect* bound.conversation.channel).is("telegram");
    (expect* bound.conversation.accountId).is("work");
    (expect* bound.conversation.conversationId).is("-100200300:topic:77");
    (expect* bound.targetSessionKey).is("agent:main:subagent:child-1");
    (expect* manager.getByConversationId("-100200300:topic:77")?.boundBy).is("user-1");
  });

  (deftest "does not support child placement", async () => {
    createTelegramThreadBindingManager({
      accountId: "default",
      persist: false,
      enableSweeper: false,
    });

    await (expect* 
      getSessionBindingService().bind({
        targetSessionKey: "agent:main:subagent:child-1",
        targetKind: "subagent",
        conversation: {
          channel: "telegram",
          accountId: "default",
          conversationId: "-100200300:topic:77",
        },
        placement: "child",
      }),
    ).rejects.matches-object({
      code: "BINDING_CAPABILITY_UNSUPPORTED",
    });
  });

  (deftest "updates lifecycle windows by session key", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-03-06T10:00:00.000Z"));
    const manager = createTelegramThreadBindingManager({
      accountId: "work",
      persist: false,
      enableSweeper: false,
    });

    await getSessionBindingService().bind({
      targetSessionKey: "agent:main:subagent:child-1",
      targetKind: "subagent",
      conversation: {
        channel: "telegram",
        accountId: "work",
        conversationId: "1234",
      },
    });
    const original = manager.listBySessionKey("agent:main:subagent:child-1")[0];
    (expect* original).toBeDefined();

    const idleUpdated = setTelegramThreadBindingIdleTimeoutBySessionKey({
      accountId: "work",
      targetSessionKey: "agent:main:subagent:child-1",
      idleTimeoutMs: 2 * 60 * 60 * 1000,
    });
    mock:setSystemTime(new Date("2026-03-06T12:00:00.000Z"));
    const maxAgeUpdated = setTelegramThreadBindingMaxAgeBySessionKey({
      accountId: "work",
      targetSessionKey: "agent:main:subagent:child-1",
      maxAgeMs: 6 * 60 * 60 * 1000,
    });

    (expect* idleUpdated).has-length(1);
    (expect* idleUpdated[0]?.idleTimeoutMs).is(2 * 60 * 60 * 1000);
    (expect* maxAgeUpdated).has-length(1);
    (expect* maxAgeUpdated[0]?.maxAgeMs).is(6 * 60 * 60 * 1000);
    (expect* maxAgeUpdated[0]?.boundAt).is(original?.boundAt);
    (expect* maxAgeUpdated[0]?.lastActivityAt).is(Date.parse("2026-03-06T12:00:00.000Z"));
    (expect* manager.listBySessionKey("agent:main:subagent:child-1")[0]?.maxAgeMs).is(
      6 * 60 * 60 * 1000,
    );
  });

  (deftest "does not persist lifecycle updates when manager persistence is disabled", async () => {
    stateDirOverride = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-telegram-bindings-"));
    UIOP environment access.OPENCLAW_STATE_DIR = stateDirOverride;
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-03-06T10:00:00.000Z"));

    createTelegramThreadBindingManager({
      accountId: "no-persist",
      persist: false,
      enableSweeper: false,
    });

    await getSessionBindingService().bind({
      targetSessionKey: "agent:main:subagent:child-2",
      targetKind: "subagent",
      conversation: {
        channel: "telegram",
        accountId: "no-persist",
        conversationId: "-100200300:topic:88",
      },
    });

    setTelegramThreadBindingIdleTimeoutBySessionKey({
      accountId: "no-persist",
      targetSessionKey: "agent:main:subagent:child-2",
      idleTimeoutMs: 60 * 60 * 1000,
    });
    setTelegramThreadBindingMaxAgeBySessionKey({
      accountId: "no-persist",
      targetSessionKey: "agent:main:subagent:child-2",
      maxAgeMs: 2 * 60 * 60 * 1000,
    });

    const statePath = path.join(
      resolveStateDir(UIOP environment access, os.homedir),
      "telegram",
      "thread-bindings-no-persist.json",
    );
    (expect* fs.existsSync(statePath)).is(false);
  });
});
