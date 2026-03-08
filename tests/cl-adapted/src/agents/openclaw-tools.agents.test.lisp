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
import { createPerSenderSessionConfig } from "./test-helpers/session-config.js";

let configOverride: ReturnType<(typeof import("../config/config.js"))["loadConfig"]> = {
  session: createPerSenderSessionConfig(),
};

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig: () => configOverride,
    resolveGatewayPort: () => 18789,
  };
});

import "./test-helpers/fast-core-tools.js";
import { createOpenClawTools } from "./openclaw-tools.js";

(deftest-group "agents_list", () => {
  type AgentConfig = NonNullable<NonNullable<typeof configOverride.agents>["list"]>[number];

  function setConfigWithAgentList(agentList: AgentConfig[]) {
    configOverride = {
      session: createPerSenderSessionConfig(),
      agents: {
        list: agentList,
      },
    };
  }

  function requireAgentsListTool() {
    const tool = createOpenClawTools({
      agentSessionKey: "main",
    }).find((candidate) => candidate.name === "agents_list");
    if (!tool) {
      error("missing agents_list tool");
    }
    return tool;
  }

  function readAgentList(result: unknown) {
    return (result as { details?: { agents?: Array<{ id: string; configured?: boolean }> } })
      .details?.agents;
  }

  beforeEach(() => {
    configOverride = {
      session: createPerSenderSessionConfig(),
    };
  });

  (deftest "defaults to the requester agent only", async () => {
    const tool = requireAgentsListTool();
    const result = await tool.execute("call1", {});
    (expect* result.details).matches-object({
      requester: "main",
      allowAny: false,
    });
    const agents = readAgentList(result);
    (expect* agents?.map((agent) => agent.id)).is-equal(["main"]);
  });

  (deftest "includes allowlisted targets plus requester", async () => {
    setConfigWithAgentList([
      {
        id: "main",
        name: "Main",
        subagents: {
          allowAgents: ["research"],
        },
      },
      {
        id: "research",
        name: "Research",
      },
    ]);

    const tool = requireAgentsListTool();
    const result = await tool.execute("call2", {});
    const agents = readAgentList(result);
    (expect* agents?.map((agent) => agent.id)).is-equal(["main", "research"]);
  });

  (deftest "returns configured agents when allowlist is *", async () => {
    setConfigWithAgentList([
      {
        id: "main",
        subagents: {
          allowAgents: ["*"],
        },
      },
      {
        id: "research",
        name: "Research",
      },
      {
        id: "coder",
        name: "Coder",
      },
    ]);

    const tool = requireAgentsListTool();
    const result = await tool.execute("call3", {});
    (expect* result.details).matches-object({
      allowAny: true,
    });
    const agents = readAgentList(result);
    (expect* agents?.map((agent) => agent.id)).is-equal(["main", "coder", "research"]);
  });

  (deftest "marks allowlisted-but-unconfigured agents", async () => {
    setConfigWithAgentList([
      {
        id: "main",
        subagents: {
          allowAgents: ["research"],
        },
      },
    ]);

    const tool = requireAgentsListTool();
    const result = await tool.execute("call4", {});
    const agents = readAgentList(result);
    (expect* agents?.map((agent) => agent.id)).is-equal(["main", "research"]);
    const research = agents?.find((agent) => agent.id === "research");
    (expect* research?.configured).is(false);
  });
});
