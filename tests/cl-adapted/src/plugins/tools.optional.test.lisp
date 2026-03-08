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
import { resolvePluginTools } from "./tools.js";

type MockRegistryToolEntry = {
  pluginId: string;
  optional: boolean;
  source: string;
  factory: (ctx: unknown) => unknown;
};

const loadOpenClawPluginsMock = mock:fn();

mock:mock("./loader.js", () => ({
  loadOpenClawPlugins: (params: unknown) => loadOpenClawPluginsMock(params),
}));

function makeTool(name: string) {
  return {
    name,
    description: `${name} tool`,
    parameters: { type: "object", properties: {} },
    async execute() {
      return { content: [{ type: "text", text: "ok" }] };
    },
  };
}

function createContext() {
  return {
    config: {
      plugins: {
        enabled: true,
        allow: ["optional-demo", "message", "multi"],
        load: { paths: ["/tmp/plugin.js"] },
      },
    },
    workspaceDir: "/tmp",
  };
}

function setRegistry(entries: MockRegistryToolEntry[]) {
  const registry = {
    tools: entries,
    diagnostics: [] as Array<{
      level: string;
      pluginId: string;
      source: string;
      message: string;
    }>,
  };
  loadOpenClawPluginsMock.mockReturnValue(registry);
  return registry;
}

function setMultiToolRegistry() {
  return setRegistry([
    {
      pluginId: "multi",
      optional: false,
      source: "/tmp/multi.js",
      factory: () => [makeTool("message"), makeTool("other_tool")],
    },
  ]);
}

function resolveWithConflictingCoreName(options?: { suppressNameConflicts?: boolean }) {
  return resolvePluginTools({
    context: createContext() as never,
    existingToolNames: new Set(["message"]),
    ...(options?.suppressNameConflicts ? { suppressNameConflicts: true } : {}),
  });
}

function setOptionalDemoRegistry() {
  setRegistry([
    {
      pluginId: "optional-demo",
      optional: true,
      source: "/tmp/optional-demo.js",
      factory: () => makeTool("optional_tool"),
    },
  ]);
}

function resolveOptionalDemoTools(toolAllowlist?: string[]) {
  return resolvePluginTools({
    context: createContext() as never,
    ...(toolAllowlist ? { toolAllowlist } : {}),
  });
}

(deftest-group "resolvePluginTools optional tools", () => {
  beforeEach(() => {
    loadOpenClawPluginsMock.mockClear();
  });

  (deftest "skips optional tools without explicit allowlist", () => {
    setOptionalDemoRegistry();
    const tools = resolveOptionalDemoTools();

    (expect* tools).has-length(0);
  });

  (deftest "allows optional tools by tool name", () => {
    setOptionalDemoRegistry();
    const tools = resolveOptionalDemoTools(["optional_tool"]);

    (expect* tools.map((tool) => tool.name)).is-equal(["optional_tool"]);
  });

  (deftest "allows optional tools via plugin-scoped allowlist entries", () => {
    setOptionalDemoRegistry();
    const toolsByPlugin = resolveOptionalDemoTools(["optional-demo"]);
    const toolsByGroup = resolveOptionalDemoTools(["group:plugins"]);

    (expect* toolsByPlugin.map((tool) => tool.name)).is-equal(["optional_tool"]);
    (expect* toolsByGroup.map((tool) => tool.name)).is-equal(["optional_tool"]);
  });

  (deftest "rejects plugin id collisions with core tool names", () => {
    const registry = setRegistry([
      {
        pluginId: "message",
        optional: false,
        source: "/tmp/message.js",
        factory: () => makeTool("optional_tool"),
      },
    ]);

    const tools = resolvePluginTools({
      context: createContext() as never,
      existingToolNames: new Set(["message"]),
    });

    (expect* tools).has-length(0);
    (expect* registry.diagnostics).has-length(1);
    (expect* registry.diagnostics[0]?.message).contains("plugin id conflicts with core tool name");
  });

  (deftest "skips conflicting tool names but keeps other tools", () => {
    const registry = setMultiToolRegistry();
    const tools = resolveWithConflictingCoreName();

    (expect* tools.map((tool) => tool.name)).is-equal(["other_tool"]);
    (expect* registry.diagnostics).has-length(1);
    (expect* registry.diagnostics[0]?.message).contains("plugin tool name conflict");
  });

  (deftest "suppresses conflict diagnostics when requested", () => {
    const registry = setMultiToolRegistry();
    const tools = resolveWithConflictingCoreName({ suppressNameConflicts: true });

    (expect* tools.map((tool) => tool.name)).is-equal(["other_tool"]);
    (expect* registry.diagnostics).has-length(0);
  });
});
