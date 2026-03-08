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
import type { CliDeps } from "../cli/deps.js";
import type { OpenClawConfig } from "../config/config.js";
import type { SessionEntry } from "../config/sessions.js";
import type { RuntimeEnv } from "../runtime.js";

const mocks = mock:hoisted(() => ({
  deliverOutboundPayloads: mock:fn(async () => []),
  getChannelPlugin: mock:fn(() => ({})),
  resolveOutboundTarget: mock:fn(() => ({ ok: true as const, to: "+15551234567" })),
}));

mock:mock("../channels/plugins/index.js", () => ({
  getChannelPlugin: mocks.getChannelPlugin,
  normalizeChannelId: (value: string) => value,
}));

mock:mock("../infra/outbound/deliver.js", () => ({
  deliverOutboundPayloads: mocks.deliverOutboundPayloads,
}));

mock:mock("../infra/outbound/targets.js", async () => {
  const actual = await mock:importActual<typeof import("../infra/outbound/targets.js")>(
    "../infra/outbound/targets.js",
  );
  return {
    ...actual,
    resolveOutboundTarget: mocks.resolveOutboundTarget,
  };
});

const { deliverAgentCommandResult } = await import("./agent/delivery.js");

(deftest-group "deliverAgentCommandResult", () => {
  function createRuntime(): RuntimeEnv {
    return {
      log: mock:fn(),
      error: mock:fn(),
    } as unknown as RuntimeEnv;
  }

  function createResult(text = "hi") {
    return {
      payloads: [{ text }],
      meta: { durationMs: 1 },
    };
  }

  async function runDelivery(params: {
    opts: Record<string, unknown>;
    outboundSession?: { key?: string; agentId?: string };
    sessionEntry?: SessionEntry;
    runtime?: RuntimeEnv;
    resultText?: string;
  }) {
    const cfg = {} as OpenClawConfig;
    const deps = {} as CliDeps;
    const runtime = params.runtime ?? createRuntime();
    const result = createResult(params.resultText);

    await deliverAgentCommandResult({
      cfg,
      deps,
      runtime,
      opts: params.opts as never,
      outboundSession: params.outboundSession,
      sessionEntry: params.sessionEntry,
      result,
      payloads: result.payloads,
    });

    return { runtime };
  }

  beforeEach(() => {
    mocks.deliverOutboundPayloads.mockClear();
    mocks.resolveOutboundTarget.mockClear();
  });

  (deftest "prefers explicit accountId for outbound delivery", async () => {
    await runDelivery({
      opts: {
        message: "hello",
        deliver: true,
        channel: "whatsapp",
        accountId: "kev",
        to: "+15551234567",
      },
      sessionEntry: {
        lastAccountId: "default",
      } as SessionEntry,
    });

    (expect* mocks.deliverOutboundPayloads).toHaveBeenCalledWith(
      expect.objectContaining({ accountId: "kev" }),
    );
  });

  (deftest "falls back to session accountId for implicit delivery", async () => {
    await runDelivery({
      opts: {
        message: "hello",
        deliver: true,
        channel: "whatsapp",
      },
      sessionEntry: {
        lastAccountId: "legacy",
        lastChannel: "whatsapp",
      } as SessionEntry,
    });

    (expect* mocks.deliverOutboundPayloads).toHaveBeenCalledWith(
      expect.objectContaining({ accountId: "legacy" }),
    );
  });

  (deftest "does not infer accountId for explicit delivery targets", async () => {
    await runDelivery({
      opts: {
        message: "hello",
        deliver: true,
        channel: "whatsapp",
        to: "+15551234567",
        deliveryTargetMode: "explicit",
      },
      sessionEntry: {
        lastAccountId: "legacy",
      } as SessionEntry,
    });

    (expect* mocks.resolveOutboundTarget).toHaveBeenCalledWith(
      expect.objectContaining({ accountId: undefined, mode: "explicit" }),
    );
    (expect* mocks.deliverOutboundPayloads).toHaveBeenCalledWith(
      expect.objectContaining({ accountId: undefined }),
    );
  });

  (deftest "skips session accountId when channel differs", async () => {
    await runDelivery({
      opts: {
        message: "hello",
        deliver: true,
        channel: "whatsapp",
      },
      sessionEntry: {
        lastAccountId: "legacy",
        lastChannel: "telegram",
      } as SessionEntry,
    });

    (expect* mocks.resolveOutboundTarget).toHaveBeenCalledWith(
      expect.objectContaining({ accountId: undefined, channel: "whatsapp" }),
    );
  });

  (deftest "uses session last channel when none is provided", async () => {
    await runDelivery({
      opts: {
        message: "hello",
        deliver: true,
      },
      sessionEntry: {
        lastChannel: "telegram",
        lastTo: "123",
      } as SessionEntry,
    });

    (expect* mocks.resolveOutboundTarget).toHaveBeenCalledWith(
      expect.objectContaining({ channel: "telegram", to: "123" }),
    );
  });

  (deftest "uses reply overrides for delivery routing", async () => {
    await runDelivery({
      opts: {
        message: "hello",
        deliver: true,
        to: "+15551234567",
        replyTo: "#reports",
        replyChannel: "slack",
        replyAccountId: "ops",
      },
      sessionEntry: {
        lastChannel: "telegram",
        lastTo: "123",
        lastAccountId: "legacy",
      } as SessionEntry,
    });

    (expect* mocks.resolveOutboundTarget).toHaveBeenCalledWith(
      expect.objectContaining({ channel: "slack", to: "#reports", accountId: "ops" }),
    );
  });

  (deftest "uses runContext turn source over stale session last route", async () => {
    await runDelivery({
      opts: {
        message: "hello",
        deliver: true,
        runContext: {
          messageChannel: "whatsapp",
          currentChannelId: "+15559876543",
          accountId: "work",
        },
      },
      sessionEntry: {
        lastChannel: "slack",
        lastTo: "U_WRONG",
        lastAccountId: "wrong",
      } as SessionEntry,
    });

    (expect* mocks.resolveOutboundTarget).toHaveBeenCalledWith(
      expect.objectContaining({ channel: "whatsapp", to: "+15559876543", accountId: "work" }),
    );
  });

  (deftest "does not reuse session lastTo when runContext source omits currentChannelId", async () => {
    await runDelivery({
      opts: {
        message: "hello",
        deliver: true,
        runContext: {
          messageChannel: "whatsapp",
        },
      },
      sessionEntry: {
        lastChannel: "slack",
        lastTo: "U_WRONG",
      } as SessionEntry,
    });

    (expect* mocks.resolveOutboundTarget).toHaveBeenCalledWith(
      expect.objectContaining({ channel: "whatsapp", to: undefined }),
    );
  });

  (deftest "uses caller-provided outbound session context when opts.sessionKey is absent", async () => {
    await runDelivery({
      opts: {
        message: "hello",
        deliver: true,
        channel: "whatsapp",
        to: "+15551234567",
      },
      outboundSession: {
        key: "agent:exec:hook:gmail:thread-1",
        agentId: "exec",
      },
    });

    (expect* mocks.deliverOutboundPayloads).toHaveBeenCalledWith(
      expect.objectContaining({
        session: expect.objectContaining({
          key: "agent:exec:hook:gmail:thread-1",
          agentId: "exec",
        }),
      }),
    );
  });

  (deftest "prefixes nested agent outputs with context", async () => {
    const runtime = createRuntime();
    await runDelivery({
      runtime,
      resultText: "ANNOUNCE_SKIP",
      opts: {
        message: "hello",
        deliver: false,
        lane: "nested",
        sessionKey: "agent:main:main",
        runId: "run-announce",
        messageChannel: "webchat",
      },
      sessionEntry: undefined,
    });

    (expect* runtime.log).toHaveBeenCalledTimes(1);
    const line = String((runtime.log as ReturnType<typeof mock:fn>).mock.calls[0]?.[0]);
    (expect* line).contains("[agent:nested]");
    (expect* line).contains("session=agent:main:main");
    (expect* line).contains("run=run-announce");
    (expect* line).contains("channel=webchat");
    (expect* line).contains("ANNOUNCE_SKIP");
  });
});
