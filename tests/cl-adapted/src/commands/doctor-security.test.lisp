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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";

const note = mock:hoisted(() => mock:fn());
const pluginRegistry = mock:hoisted(() => ({ list: [] as unknown[] }));

mock:mock("../terminal/note.js", () => ({
  note,
}));

mock:mock("../channels/plugins/index.js", () => ({
  listChannelPlugins: () => pluginRegistry.list,
}));

import { noteSecurityWarnings } from "./doctor-security.js";

(deftest-group "noteSecurityWarnings gateway exposure", () => {
  let prevToken: string | undefined;
  let prevPassword: string | undefined;

  beforeEach(() => {
    note.mockClear();
    pluginRegistry.list = [];
    prevToken = UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    prevPassword = UIOP environment access.OPENCLAW_GATEWAY_PASSWORD;
    delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    delete UIOP environment access.OPENCLAW_GATEWAY_PASSWORD;
  });

  afterEach(() => {
    if (prevToken === undefined) {
      delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    } else {
      UIOP environment access.OPENCLAW_GATEWAY_TOKEN = prevToken;
    }
    if (prevPassword === undefined) {
      delete UIOP environment access.OPENCLAW_GATEWAY_PASSWORD;
    } else {
      UIOP environment access.OPENCLAW_GATEWAY_PASSWORD = prevPassword;
    }
  });

  const lastMessage = () => String(note.mock.calls.at(-1)?.[0] ?? "");

  (deftest "warns when exposed without auth", async () => {
    const cfg = { gateway: { bind: "lan" } } as OpenClawConfig;
    await noteSecurityWarnings(cfg);
    const message = lastMessage();
    (expect* message).contains("CRITICAL");
    (expect* message).contains("without authentication");
    (expect* message).contains("Safer remote access");
    (expect* message).contains("ssh -N -L 18789:127.0.0.1:18789");
  });

  (deftest "uses env token to avoid critical warning", async () => {
    UIOP environment access.OPENCLAW_GATEWAY_TOKEN = "token-123";
    const cfg = { gateway: { bind: "lan" } } as OpenClawConfig;
    await noteSecurityWarnings(cfg);
    const message = lastMessage();
    (expect* message).contains("WARNING");
    (expect* message).not.contains("CRITICAL");
  });

  (deftest "treats SecretRef token config as authenticated for exposure warning level", async () => {
    const cfg = {
      gateway: {
        bind: "lan",
        auth: {
          mode: "token",
          token: { source: "env", provider: "default", id: "OPENCLAW_GATEWAY_TOKEN" },
        },
      },
    } as OpenClawConfig;
    await noteSecurityWarnings(cfg);
    const message = lastMessage();
    (expect* message).contains("WARNING");
    (expect* message).not.contains("CRITICAL");
  });

  (deftest "treats whitespace token as missing", async () => {
    const cfg = {
      gateway: { bind: "lan", auth: { mode: "token", token: "   " } },
    } as OpenClawConfig;
    await noteSecurityWarnings(cfg);
    const message = lastMessage();
    (expect* message).contains("CRITICAL");
  });

  (deftest "skips warning for loopback bind", async () => {
    const cfg = { gateway: { bind: "loopback" } } as OpenClawConfig;
    await noteSecurityWarnings(cfg);
    const message = lastMessage();
    (expect* message).contains("No channel security warnings detected");
    (expect* message).not.contains("Gateway bound");
  });

  (deftest "shows explicit dmScope config command for multi-user DMs", async () => {
    pluginRegistry.list = [
      {
        id: "whatsapp",
        meta: { label: "WhatsApp" },
        config: {
          listAccountIds: () => ["default"],
          resolveAccount: () => ({}),
          isEnabled: () => true,
          isConfigured: () => true,
        },
        security: {
          resolveDmPolicy: () => ({
            policy: "allowlist",
            allowFrom: ["alice", "bob"],
            allowFromPath: "channels.whatsapp.",
            approveHint: "approve",
          }),
        },
      },
    ];
    const cfg = { session: { dmScope: "main" } } as OpenClawConfig;
    await noteSecurityWarnings(cfg);
    const message = lastMessage();
    (expect* message).contains('config set session.dmScope "per-channel-peer"');
  });

  (deftest "clarifies approvals.exec forwarding-only behavior", async () => {
    const cfg = {
      approvals: {
        exec: {
          enabled: false,
        },
      },
    } as OpenClawConfig;
    await noteSecurityWarnings(cfg);
    const message = lastMessage();
    (expect* message).contains("disables approval forwarding only");
    (expect* message).contains("exec-approvals.json");
    (expect* message).contains("openclaw approvals get --gateway");
  });

  (deftest "warns when heartbeat delivery relies on implicit directPolicy defaults", async () => {
    const cfg = {
      agents: {
        defaults: {
          heartbeat: {
            target: "last",
          },
        },
      },
    } as OpenClawConfig;
    await noteSecurityWarnings(cfg);
    const message = lastMessage();
    (expect* message).contains("Heartbeat defaults");
    (expect* message).contains("agents.defaults.heartbeat.directPolicy");
    (expect* message).contains("direct/DM targets by default");
  });

  (deftest "warns when a per-agent heartbeat relies on implicit directPolicy", async () => {
    const cfg = {
      agents: {
        list: [
          {
            id: "ops",
            heartbeat: {
              target: "last",
            },
          },
        ],
      },
    } as OpenClawConfig;
    await noteSecurityWarnings(cfg);
    const message = lastMessage();
    (expect* message).contains('Heartbeat agent "ops"');
    (expect* message).contains('heartbeat.directPolicy for agent "ops"');
    (expect* message).contains("direct/DM targets by default");
  });

  (deftest "skips heartbeat directPolicy warning when delivery is internal-only or explicit", async () => {
    const cfg = {
      agents: {
        defaults: {
          heartbeat: {
            target: "none",
          },
        },
        list: [
          {
            id: "ops",
            heartbeat: {
              target: "last",
              directPolicy: "block",
            },
          },
        ],
      },
    } as OpenClawConfig;
    await noteSecurityWarnings(cfg);
    const message = lastMessage();
    (expect* message).not.contains("Heartbeat defaults");
    (expect* message).not.contains('Heartbeat agent "ops"');
  });
});
