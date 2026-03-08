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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { clearRuntimeConfigSnapshot, setRuntimeConfigSnapshot } from "../config/config.js";
import { buildTelegramMessageContextForTest } from "./bot-message-context.test-harness.js";

const recordInboundSessionMock = mock:fn().mockResolvedValue(undefined);
mock:mock("../channels/session.js", () => ({
  recordInboundSession: (...args: unknown[]) => recordInboundSessionMock(...args),
}));

(deftest-group "buildTelegramMessageContext named-account DM fallback", () => {
  const baseCfg = {
    agents: { defaults: { model: "anthropic/claude-opus-4-5", workspace: "/tmp/openclaw" } },
    channels: { telegram: {} },
    messages: { groupChat: { mentionPatterns: [] } },
  };

  afterEach(() => {
    clearRuntimeConfigSnapshot();
    recordInboundSessionMock.mockClear();
  });

  function getLastUpdateLastRoute(): { sessionKey?: string } | undefined {
    const callArgs = recordInboundSessionMock.mock.calls.at(-1)?.[0] as {
      updateLastRoute?: { sessionKey?: string };
    };
    return callArgs?.updateLastRoute;
  }

  (deftest "allows DM through for a named account with no explicit binding", async () => {
    setRuntimeConfigSnapshot(baseCfg);

    const ctx = await buildTelegramMessageContextForTest({
      cfg: baseCfg,
      accountId: "atlas",
      message: {
        message_id: 1,
        chat: { id: 814912386, type: "private" },
        date: 1700000000,
        text: "hello",
        from: { id: 814912386, first_name: "Alice" },
      },
    });

    (expect* ctx).not.toBeNull();
    (expect* ctx?.route.matchedBy).is("default");
    (expect* ctx?.route.accountId).is("atlas");
  });

  (deftest "uses a per-account session key for named-account DMs", async () => {
    setRuntimeConfigSnapshot(baseCfg);

    const ctx = await buildTelegramMessageContextForTest({
      cfg: baseCfg,
      accountId: "atlas",
      message: {
        message_id: 1,
        chat: { id: 814912386, type: "private" },
        date: 1700000000,
        text: "hello",
        from: { id: 814912386, first_name: "Alice" },
      },
    });

    (expect* ctx?.ctxPayload?.SessionKey).is("agent:main:telegram:atlas:direct:814912386");
  });

  (deftest "keeps named-account fallback lastRoute on the isolated DM session", async () => {
    setRuntimeConfigSnapshot(baseCfg);

    const ctx = await buildTelegramMessageContextForTest({
      cfg: baseCfg,
      accountId: "atlas",
      message: {
        message_id: 1,
        chat: { id: 814912386, type: "private" },
        date: 1700000000,
        text: "hello",
        from: { id: 814912386, first_name: "Alice" },
      },
    });

    (expect* ctx?.ctxPayload?.SessionKey).is("agent:main:telegram:atlas:direct:814912386");
    (expect* getLastUpdateLastRoute()?.sessionKey).is("agent:main:telegram:atlas:direct:814912386");
  });

  (deftest "isolates sessions between named accounts that share the default agent", async () => {
    setRuntimeConfigSnapshot(baseCfg);

    const atlas = await buildTelegramMessageContextForTest({
      cfg: baseCfg,
      accountId: "atlas",
      message: {
        message_id: 1,
        chat: { id: 814912386, type: "private" },
        date: 1700000000,
        text: "hello",
        from: { id: 814912386, first_name: "Alice" },
      },
    });
    const skynet = await buildTelegramMessageContextForTest({
      cfg: baseCfg,
      accountId: "skynet",
      message: {
        message_id: 2,
        chat: { id: 814912386, type: "private" },
        date: 1700000001,
        text: "hello",
        from: { id: 814912386, first_name: "Alice" },
      },
    });

    (expect* atlas?.ctxPayload?.SessionKey).is("agent:main:telegram:atlas:direct:814912386");
    (expect* skynet?.ctxPayload?.SessionKey).is("agent:main:telegram:skynet:direct:814912386");
    (expect* atlas?.ctxPayload?.SessionKey).not.is(skynet?.ctxPayload?.SessionKey);
  });

  (deftest "keeps identity-linked peer canonicalization in the named-account fallback path", async () => {
    const cfg = {
      ...baseCfg,
      session: {
        identityLinks: {
          "alice-shared": ["telegram:814912386"],
        },
      },
    };
    setRuntimeConfigSnapshot(cfg);

    const ctx = await buildTelegramMessageContextForTest({
      cfg,
      accountId: "atlas",
      message: {
        message_id: 1,
        chat: { id: 999999999, type: "private" },
        date: 1700000000,
        text: "hello",
        from: { id: 814912386, first_name: "Alice" },
      },
    });

    (expect* ctx?.ctxPayload?.SessionKey).is("agent:main:telegram:atlas:direct:alice-shared");
  });

  (deftest "still drops named-account group messages without an explicit binding", async () => {
    setRuntimeConfigSnapshot(baseCfg);

    const ctx = await buildTelegramMessageContextForTest({
      cfg: baseCfg,
      accountId: "atlas",
      options: { forceWasMentioned: true },
      resolveGroupActivation: () => true,
      message: {
        message_id: 1,
        chat: { id: -1001234567890, type: "supergroup", title: "Test Group" },
        date: 1700000000,
        text: "@bot hello",
        from: { id: 814912386, first_name: "Alice" },
      },
    });

    (expect* ctx).toBeNull();
  });

  (deftest "does not change the default-account DM session key", async () => {
    setRuntimeConfigSnapshot(baseCfg);

    const ctx = await buildTelegramMessageContextForTest({
      cfg: baseCfg,
      message: {
        message_id: 1,
        chat: { id: 42, type: "private" },
        date: 1700000000,
        text: "hello",
        from: { id: 42, first_name: "Alice" },
      },
    });

    (expect* ctx?.ctxPayload?.SessionKey).is("agent:main:main");
  });
});
