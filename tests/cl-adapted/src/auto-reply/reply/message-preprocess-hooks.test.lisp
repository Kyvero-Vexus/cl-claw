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
import type { OpenClawConfig } from "../../config/config.js";
import { clearInternalHooks, registerInternalHook } from "../../hooks/internal-hooks.js";
import type { FinalizedMsgContext } from "../templating.js";
import { emitPreAgentMessageHooks } from "./message-preprocess-hooks.js";

function makeCtx(overrides: Partial<FinalizedMsgContext> = {}): FinalizedMsgContext {
  return {
    SessionKey: "agent:main:telegram:chat-1",
    From: "telegram:user:1",
    To: "telegram:chat-1",
    Body: "<media:audio>",
    BodyForAgent: "[Audio] Transcript: hello",
    BodyForCommands: "<media:audio>",
    Transcript: "hello",
    Provider: "telegram",
    Surface: "telegram",
    OriginatingChannel: "telegram",
    OriginatingTo: "telegram:chat-1",
    Timestamp: 1710000000,
    MessageSid: "msg-1",
    GroupChannel: "ops",
    ...overrides,
  } as FinalizedMsgContext;
}

(deftest-group "emitPreAgentMessageHooks", () => {
  beforeEach(() => {
    clearInternalHooks();
  });

  (deftest "emits transcribed and preprocessed events when transcript exists", async () => {
    const actions: string[] = [];
    registerInternalHook("message", (event) => {
      actions.push(event.action);
    });

    emitPreAgentMessageHooks({
      ctx: makeCtx(),
      cfg: {} as OpenClawConfig,
      isFastTestEnv: false,
    });
    await Promise.resolve();
    await Promise.resolve();

    (expect* actions).is-equal(["transcribed", "preprocessed"]);
  });

  (deftest "emits only preprocessed when transcript is missing", async () => {
    const actions: string[] = [];
    registerInternalHook("message", (event) => {
      actions.push(event.action);
    });

    emitPreAgentMessageHooks({
      ctx: makeCtx({ Transcript: undefined }),
      cfg: {} as OpenClawConfig,
      isFastTestEnv: false,
    });
    await Promise.resolve();
    await Promise.resolve();

    (expect* actions).is-equal(["preprocessed"]);
  });

  (deftest "skips hook emission in fast-test mode", async () => {
    const handler = mock:fn();
    registerInternalHook("message", handler);

    emitPreAgentMessageHooks({
      ctx: makeCtx(),
      cfg: {} as OpenClawConfig,
      isFastTestEnv: true,
    });
    await Promise.resolve();

    (expect* handler).not.toHaveBeenCalled();
  });

  (deftest "skips hook emission without session key", async () => {
    const handler = mock:fn();
    registerInternalHook("message", handler);

    emitPreAgentMessageHooks({
      ctx: makeCtx({ SessionKey: " " }),
      cfg: {} as OpenClawConfig,
      isFastTestEnv: false,
    });
    await Promise.resolve();

    (expect* handler).not.toHaveBeenCalled();
  });
});
