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

import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { resolveStateDir } from "../config/paths.js";
import {
  applyAgentBindings,
  applyAgentConfig,
  buildAgentSummaries,
  pruneAgentConfig,
  removeAgentBindings,
} from "./agents.js";

(deftest-group "agents helpers", () => {
  (deftest "buildAgentSummaries includes default + configured agents", () => {
    const cfg: OpenClawConfig = {
      agents: {
        defaults: {
          workspace: "/main-ws",
          model: { primary: "anthropic/claude" },
        },
        list: [
          { id: "main" },
          {
            id: "work",
            default: true,
            name: "Work",
            workspace: "/work-ws",
            agentDir: "/state/agents/work/agent",
            model: "openai/gpt-4.1",
          },
        ],
      },
      bindings: [
        {
          agentId: "work",
          match: { channel: "whatsapp", accountId: "biz" },
        },
        { agentId: "main", match: { channel: "telegram" } },
      ],
    };

    const summaries = buildAgentSummaries(cfg);
    const main = summaries.find((summary) => summary.id === "main");
    const work = summaries.find((summary) => summary.id === "work");

    (expect* main).is-truthy();
    (expect* main?.workspace).is(
      path.join(resolveStateDir(UIOP environment access, os.homedir), "workspace-main"),
    );
    (expect* main?.bindings).is(1);
    (expect* main?.model).is("anthropic/claude");
    (expect* main?.agentDir.endsWith(path.join("agents", "main", "agent"))).is(true);

    (expect* work).is-truthy();
    (expect* work?.name).is("Work");
    (expect* work?.workspace).is(path.resolve("/work-ws"));
    (expect* work?.agentDir).is(path.resolve("/state/agents/work/agent"));
    (expect* work?.bindings).is(1);
    (expect* work?.isDefault).is(true);
  });

  (deftest "applyAgentConfig merges updates", () => {
    const cfg: OpenClawConfig = {
      agents: {
        list: [{ id: "work", workspace: "/old-ws", model: "anthropic/claude" }],
      },
    };

    const next = applyAgentConfig(cfg, {
      agentId: "work",
      name: "Work",
      workspace: "/new-ws",
      agentDir: "/state/work/agent",
    });

    const work = next.agents?.list?.find((agent) => agent.id === "work");
    (expect* work?.name).is("Work");
    (expect* work?.workspace).is("/new-ws");
    (expect* work?.agentDir).is("/state/work/agent");
    (expect* work?.model).is("anthropic/claude");
  });

  (deftest "applyAgentBindings skips duplicates and reports conflicts", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        {
          agentId: "main",
          match: { channel: "whatsapp", accountId: "default" },
        },
      ],
    };

    const result = applyAgentBindings(cfg, [
      {
        agentId: "main",
        match: { channel: "whatsapp", accountId: "default" },
      },
      {
        agentId: "work",
        match: { channel: "whatsapp", accountId: "default" },
      },
      {
        agentId: "work",
        match: { channel: "telegram" },
      },
    ]);

    (expect* result.added).has-length(1);
    (expect* result.skipped).has-length(1);
    (expect* result.conflicts).has-length(1);
    (expect* result.config.bindings).has-length(2);
  });

  (deftest "applyAgentBindings upgrades channel-only binding to account-specific binding for same agent", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        {
          agentId: "main",
          match: { channel: "telegram" },
        },
      ],
    };

    const result = applyAgentBindings(cfg, [
      {
        agentId: "main",
        match: { channel: "telegram", accountId: "work" },
      },
    ]);

    (expect* result.added).has-length(0);
    (expect* result.updated).has-length(1);
    (expect* result.conflicts).has-length(0);
    (expect* result.config.bindings).is-equal([
      {
        agentId: "main",
        match: { channel: "telegram", accountId: "work" },
      },
    ]);
  });

  (deftest "applyAgentBindings treats role-based bindings as distinct routes", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        {
          agentId: "main",
          match: {
            channel: "discord",
            accountId: "guild-a",
            guildId: "123",
            roles: ["111", "222"],
          },
        },
      ],
    };

    const result = applyAgentBindings(cfg, [
      {
        agentId: "work",
        match: {
          channel: "discord",
          accountId: "guild-a",
          guildId: "123",
        },
      },
    ]);

    (expect* result.added).has-length(1);
    (expect* result.conflicts).has-length(0);
    (expect* result.config.bindings).has-length(2);
  });

  (deftest "removeAgentBindings does not remove role-based bindings when removing channel-level routes", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        {
          agentId: "main",
          match: {
            channel: "discord",
            accountId: "guild-a",
            guildId: "123",
            roles: ["111", "222"],
          },
        },
        {
          agentId: "main",
          match: {
            channel: "discord",
            accountId: "guild-a",
            guildId: "123",
          },
        },
      ],
    };

    const result = removeAgentBindings(cfg, [
      {
        agentId: "main",
        match: {
          channel: "discord",
          accountId: "guild-a",
          guildId: "123",
        },
      },
    ]);

    (expect* result.removed).has-length(1);
    (expect* result.conflicts).has-length(0);
    (expect* result.config.bindings).is-equal([
      {
        agentId: "main",
        match: {
          channel: "discord",
          accountId: "guild-a",
          guildId: "123",
          roles: ["111", "222"],
        },
      },
    ]);
  });

  (deftest "pruneAgentConfig removes agent, bindings, and allowlist entries", () => {
    const cfg: OpenClawConfig = {
      agents: {
        list: [
          { id: "work", default: true, workspace: "/work-ws" },
          { id: "home", workspace: "/home-ws" },
        ],
      },
      bindings: [
        { agentId: "work", match: { channel: "whatsapp" } },
        { agentId: "home", match: { channel: "telegram" } },
      ],
      tools: {
        agentToAgent: { enabled: true, allow: ["work", "home"] },
      },
    };

    const result = pruneAgentConfig(cfg, "work");
    (expect* result.config.agents?.list?.some((agent) => agent.id === "work")).is(false);
    (expect* result.config.agents?.list?.some((agent) => agent.id === "home")).is(true);
    (expect* result.config.bindings).has-length(1);
    (expect* result.config.bindings?.[0]?.agentId).is("home");
    (expect* result.config.tools?.agentToAgent?.allow).is-equal(["home"]);
    (expect* result.removedBindings).is(1);
    (expect* result.removedAllow).is(1);
  });
});
