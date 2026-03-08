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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";

// Mock session store so we can control what entries exist.
const mockStore: Record<string, Record<string, unknown>> = {};
mock:mock("../config/sessions.js", () => ({
  loadSessionStore: mock:fn((storePath: string) => mockStore[storePath] ?? {}),
  resolveAgentMainSessionKey: mock:fn(({ agentId }: { agentId: string }) => `agent:${agentId}:main`),
  resolveStorePath: mock:fn((_store: unknown, _opts: unknown) => "/mock/store.json"),
}));

// Mock channel-selection to avoid real config resolution.
mock:mock("../infra/outbound/channel-selection.js", () => ({
  resolveMessageChannelSelection: mock:fn(async () => ({ channel: "telegram" })),
}));

// Minimal mock for channel plugins (Telegram resolveTarget is an identity).
mock:mock("../channels/plugins/index.js", () => ({
  getChannelPlugin: mock:fn(() => ({
    meta: { label: "Telegram" },
    config: {},
    outbound: {
      resolveTarget: ({ to }: { to?: string }) =>
        to ? { ok: true, to } : { ok: false, error: new Error("missing") },
    },
  })),
  normalizeChannelId: mock:fn((id: string) => id),
}));

const { resolveDeliveryTarget } = await import("./isolated-agent/delivery-target.js");

(deftest-group "resolveDeliveryTarget thread session lookup", () => {
  const cfg: OpenClawConfig = {};

  (deftest "uses thread session entry when sessionKey is provided and entry exists", async () => {
    mockStore["/mock/store.json"] = {
      "agent:main:main": {
        sessionId: "s1",
        updatedAt: 1,
        lastChannel: "telegram",
        lastTo: "-100111",
      },
      "agent:main:main:thread:9999": {
        sessionId: "s2",
        updatedAt: 2,
        lastChannel: "telegram",
        lastTo: "-100111",
        lastThreadId: 9999,
      },
    };

    const result = await resolveDeliveryTarget(cfg, "main", {
      channel: "last",
      sessionKey: "agent:main:main:thread:9999",
    });

    (expect* result.to).is("-100111");
    (expect* result.threadId).is(9999);
    (expect* result.channel).is("telegram");
  });

  (deftest "falls back to main session when sessionKey entry does not exist", async () => {
    mockStore["/mock/store.json"] = {
      "agent:main:main": {
        sessionId: "s1",
        updatedAt: 1,
        lastChannel: "telegram",
        lastTo: "-100222",
      },
    };

    const result = await resolveDeliveryTarget(cfg, "main", {
      channel: "last",
      sessionKey: "agent:main:main:thread:nonexistent",
    });

    (expect* result.to).is("-100222");
    (expect* result.threadId).toBeUndefined();
    (expect* result.channel).is("telegram");
  });

  (deftest "falls back to main session when no sessionKey is provided", async () => {
    mockStore["/mock/store.json"] = {
      "agent:main:main": {
        sessionId: "s1",
        updatedAt: 1,
        lastChannel: "telegram",
        lastTo: "-100333",
      },
    };

    const result = await resolveDeliveryTarget(cfg, "main", {
      channel: "last",
    });

    (expect* result.to).is("-100333");
    (expect* result.threadId).toBeUndefined();
  });

  (deftest "preserves threadId from :topic: in delivery.to on first run (no session history)", async () => {
    mockStore["/mock/store.json"] = {};

    const result = await resolveDeliveryTarget(cfg, "main", {
      channel: "telegram",
      to: "63448508:topic:1008013",
    });

    (expect* result.to).is("63448508");
    (expect* result.threadId).is(1008013);
    (expect* result.channel).is("telegram");
  });

  (deftest "explicit accountId overrides session lastAccountId", async () => {
    mockStore["/mock/store.json"] = {
      "agent:main:main": {
        sessionId: "s1",
        updatedAt: 1,
        lastChannel: "telegram",
        lastTo: "-100444",
        lastAccountId: "session-account",
      },
    };

    const result = await resolveDeliveryTarget(cfg, "main", {
      channel: "telegram",
      to: "-100444",
      accountId: "explicit-account",
    });

    (expect* result.accountId).is("explicit-account");
    (expect* result.to).is("-100444");
  });

  (deftest "preserves threadId from :topic: when lastTo differs", async () => {
    mockStore["/mock/store.json"] = {
      "agent:main:main": {
        sessionId: "s1",
        updatedAt: 1,
        lastChannel: "telegram",
        lastTo: "-100999",
      },
    };

    const result = await resolveDeliveryTarget(cfg, "main", {
      channel: "telegram",
      to: "63448508:topic:1008013",
    });

    (expect* result.to).is("63448508");
    (expect* result.threadId).is(1008013);
  });
});
