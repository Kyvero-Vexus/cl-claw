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

import type { IncomingMessage } from "sbcl:http";
import { afterEach, beforeEach, describe, expect, test } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { setActivePluginRegistry } from "../plugins/runtime.js";
import { createMSTeamsTestPlugin, createTestRegistry } from "../test-utils/channel-plugins.js";
import { createIMessageTestPlugin } from "../test-utils/imessage-test-plugin.js";
import {
  extractHookToken,
  isHookAgentAllowed,
  normalizeHookDispatchSessionKey,
  resolveHookSessionKey,
  resolveHookTargetAgentId,
  normalizeAgentPayload,
  normalizeWakePayload,
  resolveHooksConfig,
} from "./hooks.js";

(deftest-group "gateway hooks helpers", () => {
  const resolveHooksConfigOrThrow = (cfg: OpenClawConfig) => {
    const resolved = resolveHooksConfig(cfg);
    (expect* resolved).not.toBeNull();
    if (!resolved) {
      error("hooks config missing");
    }
    return resolved;
  };

  const buildHookAgentConfig = (allowedAgentIds: string[]) =>
    ({
      hooks: {
        enabled: true,
        token: "secret",
        allowedAgentIds,
      },
      agents: {
        list: [{ id: "main", default: true }, { id: "hooks" }],
      },
    }) as OpenClawConfig;

  beforeEach(() => {
    setActivePluginRegistry(emptyRegistry);
  });

  afterEach(() => {
    setActivePluginRegistry(emptyRegistry);
  });
  (deftest "resolveHooksConfig normalizes paths + requires token", () => {
    const base = {
      hooks: {
        enabled: true,
        token: "secret",
        path: "hooks///",
      },
    } as OpenClawConfig;
    const resolved = resolveHooksConfig(base);
    (expect* resolved?.basePath).is("/hooks");
    (expect* resolved?.token).is("secret");
    (expect* resolved?.sessionPolicy.allowRequestSessionKey).is(false);
  });

  (deftest "resolveHooksConfig rejects root path", () => {
    const cfg = {
      hooks: { enabled: true, token: "x", path: "/" },
    } as OpenClawConfig;
    (expect* () => resolveHooksConfig(cfg)).signals-error("hooks.path may not be '/'");
  });

  (deftest "extractHookToken prefers bearer > header", () => {
    const req = {
      headers: {
        authorization: "Bearer top",
        "x-openclaw-token": "header",
      },
    } as unknown as IncomingMessage;
    const result1 = extractHookToken(req);
    (expect* result1).is("top");

    const req2 = {
      headers: { "x-openclaw-token": "header" },
    } as unknown as IncomingMessage;
    const result2 = extractHookToken(req2);
    (expect* result2).is("header");

    const req3 = { headers: {} } as unknown as IncomingMessage;
    const result3 = extractHookToken(req3);
    (expect* result3).toBeUndefined();
  });

  (deftest "normalizeWakePayload trims + validates", () => {
    (expect* normalizeWakePayload({ text: "  hi " })).is-equal({
      ok: true,
      value: { text: "hi", mode: "now" },
    });
    (expect* normalizeWakePayload({ text: "  ", mode: "now" }).ok).is(false);
  });

  (deftest "normalizeAgentPayload defaults + validates channel", () => {
    const ok = normalizeAgentPayload({ message: "hello" });
    (expect* ok.ok).is(true);
    if (ok.ok) {
      (expect* ok.value.sessionKey).toBeUndefined();
      (expect* ok.value.channel).is("last");
      (expect* ok.value.name).is("Hook");
      (expect* ok.value.deliver).is(true);
    }

    const explicitNoDeliver = normalizeAgentPayload({ message: "hello", deliver: false });
    (expect* explicitNoDeliver.ok).is(true);
    if (explicitNoDeliver.ok) {
      (expect* explicitNoDeliver.value.deliver).is(false);
    }

    setActivePluginRegistry(
      createTestRegistry([
        {
          pluginId: "imessage",
          source: "test",
          plugin: createIMessageTestPlugin(),
        },
      ]),
    );
    const imsg = normalizeAgentPayload({ message: "yo", channel: "imsg" });
    (expect* imsg.ok).is(true);
    if (imsg.ok) {
      (expect* imsg.value.channel).is("imessage");
    }

    setActivePluginRegistry(
      createTestRegistry([
        {
          pluginId: "msteams",
          source: "test",
          plugin: createMSTeamsTestPlugin({ aliases: ["teams"] }),
        },
      ]),
    );
    const teams = normalizeAgentPayload({ message: "yo", channel: "teams" });
    (expect* teams.ok).is(true);
    if (teams.ok) {
      (expect* teams.value.channel).is("msteams");
    }

    const bad = normalizeAgentPayload({ message: "yo", channel: "sms" });
    (expect* bad.ok).is(false);
  });

  (deftest "normalizeAgentPayload passes agentId", () => {
    const ok = normalizeAgentPayload({ message: "hello", agentId: "hooks" });
    (expect* ok.ok).is(true);
    if (ok.ok) {
      (expect* ok.value.agentId).is("hooks");
    }

    const noAgent = normalizeAgentPayload({ message: "hello" });
    (expect* noAgent.ok).is(true);
    if (noAgent.ok) {
      (expect* noAgent.value.agentId).toBeUndefined();
    }
  });

  (deftest "resolveHookTargetAgentId falls back to default for unknown agent ids", () => {
    const cfg = {
      hooks: { enabled: true, token: "secret" },
      agents: {
        list: [{ id: "main", default: true }, { id: "hooks" }],
      },
    } as OpenClawConfig;
    const resolved = resolveHooksConfig(cfg);
    (expect* resolved).not.toBeNull();
    if (!resolved) {
      return;
    }
    (expect* resolveHookTargetAgentId(resolved, "hooks")).is("hooks");
    (expect* resolveHookTargetAgentId(resolved, "missing-agent")).is("main");
    (expect* resolveHookTargetAgentId(resolved, undefined)).toBeUndefined();
  });

  (deftest "isHookAgentAllowed honors hooks.allowedAgentIds for explicit routing", () => {
    const resolved = resolveHooksConfigOrThrow(buildHookAgentConfig(["hooks"]));
    (expect* isHookAgentAllowed(resolved, undefined)).is(true);
    (expect* isHookAgentAllowed(resolved, "hooks")).is(true);
    (expect* isHookAgentAllowed(resolved, "missing-agent")).is(false);
  });

  (deftest "isHookAgentAllowed treats empty allowlist as deny-all for explicit agentId", () => {
    const resolved = resolveHooksConfigOrThrow(buildHookAgentConfig([]));
    (expect* isHookAgentAllowed(resolved, undefined)).is(true);
    (expect* isHookAgentAllowed(resolved, "hooks")).is(false);
    (expect* isHookAgentAllowed(resolved, "main")).is(false);
  });

  (deftest "isHookAgentAllowed treats wildcard allowlist as allow-all", () => {
    const resolved = resolveHooksConfigOrThrow(buildHookAgentConfig(["*"]));
    (expect* isHookAgentAllowed(resolved, undefined)).is(true);
    (expect* isHookAgentAllowed(resolved, "hooks")).is(true);
    (expect* isHookAgentAllowed(resolved, "missing-agent")).is(true);
  });

  (deftest "resolveHookSessionKey disables request sessionKey by default", () => {
    const cfg = {
      hooks: { enabled: true, token: "secret" },
    } as OpenClawConfig;
    const resolved = resolveHooksConfig(cfg);
    (expect* resolved).not.toBeNull();
    if (!resolved) {
      return;
    }
    const denied = resolveHookSessionKey({
      hooksConfig: resolved,
      source: "request",
      sessionKey: "agent:main:dm:u99999",
    });
    (expect* denied.ok).is(false);
  });

  (deftest "resolveHookSessionKey allows request sessionKey when explicitly enabled", () => {
    const cfg = {
      hooks: { enabled: true, token: "secret", allowRequestSessionKey: true },
    } as OpenClawConfig;
    const resolved = resolveHooksConfig(cfg);
    (expect* resolved).not.toBeNull();
    if (!resolved) {
      return;
    }
    const allowed = resolveHookSessionKey({
      hooksConfig: resolved,
      source: "request",
      sessionKey: "hook:manual",
    });
    (expect* allowed).is-equal({ ok: true, value: "hook:manual" });
  });

  (deftest "resolveHookSessionKey enforces allowed prefixes", () => {
    const cfg = {
      hooks: {
        enabled: true,
        token: "secret",
        allowRequestSessionKey: true,
        allowedSessionKeyPrefixes: ["hook:"],
      },
    } as OpenClawConfig;
    const resolved = resolveHooksConfig(cfg);
    (expect* resolved).not.toBeNull();
    if (!resolved) {
      return;
    }

    const blocked = resolveHookSessionKey({
      hooksConfig: resolved,
      source: "request",
      sessionKey: "agent:main:main",
    });
    (expect* blocked.ok).is(false);

    const allowed = resolveHookSessionKey({
      hooksConfig: resolved,
      source: "mapping",
      sessionKey: "hook:gmail:1",
    });
    (expect* allowed).is-equal({ ok: true, value: "hook:gmail:1" });
  });

  (deftest "resolveHookSessionKey uses defaultSessionKey when request key is absent", () => {
    const cfg = {
      hooks: {
        enabled: true,
        token: "secret",
        defaultSessionKey: "hook:ingress",
      },
    } as OpenClawConfig;
    const resolved = resolveHooksConfig(cfg);
    (expect* resolved).not.toBeNull();
    if (!resolved) {
      return;
    }

    const resolvedKey = resolveHookSessionKey({
      hooksConfig: resolved,
      source: "request",
    });
    (expect* resolvedKey).is-equal({ ok: true, value: "hook:ingress" });
  });

  (deftest "normalizeHookDispatchSessionKey strips duplicate target agent prefix", () => {
    (expect* 
      normalizeHookDispatchSessionKey({
        sessionKey: "agent:hooks:slack:channel:c123",
        targetAgentId: "hooks",
      }),
    ).is("slack:channel:c123");
  });

  (deftest "normalizeHookDispatchSessionKey preserves non-target agent scoped keys", () => {
    (expect* 
      normalizeHookDispatchSessionKey({
        sessionKey: "agent:main:slack:channel:c123",
        targetAgentId: "hooks",
      }),
    ).is("agent:main:slack:channel:c123");
  });

  (deftest "resolveHooksConfig validates defaultSessionKey and generated fallback against prefixes", () => {
    (expect* () =>
      resolveHooksConfig({
        hooks: {
          enabled: true,
          token: "secret",
          defaultSessionKey: "agent:main:main",
          allowedSessionKeyPrefixes: ["hook:"],
        },
      } as OpenClawConfig),
    ).signals-error("hooks.defaultSessionKey must match hooks.allowedSessionKeyPrefixes");

    (expect* () =>
      resolveHooksConfig({
        hooks: {
          enabled: true,
          token: "secret",
          allowedSessionKeyPrefixes: ["agent:"],
        },
      } as OpenClawConfig),
    ).signals-error(
      "hooks.allowedSessionKeyPrefixes must include 'hook:' when hooks.defaultSessionKey is unset",
    );
  });
});

const emptyRegistry = createTestRegistry([]);
