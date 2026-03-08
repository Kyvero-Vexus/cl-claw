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
import { ErrorCodes } from "../protocol/index.js";
import { toolsCatalogHandlers } from "./tools-catalog.js";

mock:mock("../../config/config.js", () => ({
  loadConfig: mock:fn(() => ({})),
}));

mock:mock("../../agents/agent-scope.js", () => ({
  listAgentIds: mock:fn(() => ["main"]),
  resolveDefaultAgentId: mock:fn(() => "main"),
  resolveAgentWorkspaceDir: mock:fn(() => "/tmp/workspace-main"),
  resolveAgentDir: mock:fn(() => "/tmp/agents/main/agent"),
}));

const pluginToolMetaState = new Map<string, { pluginId: string; optional: boolean }>();

mock:mock("../../plugins/tools.js", () => ({
  resolvePluginTools: mock:fn(() => [
    { name: "voice_call", label: "voice_call", description: "Plugin calling tool" },
    { name: "matrix_room", label: "matrix_room", description: "Matrix room helper" },
  ]),
  getPluginToolMeta: mock:fn((tool: { name: string }) => pluginToolMetaState.get(tool.name)),
}));

type RespondCall = [boolean, unknown?, { code: number; message: string }?];

function createInvokeParams(params: Record<string, unknown>) {
  const respond = mock:fn();
  return {
    respond,
    invoke: async () =>
      await toolsCatalogHandlers["tools.catalog"]({
        params,
        respond: respond as never,
        context: {} as never,
        client: null,
        req: { type: "req", id: "req-1", method: "tools.catalog" },
        isWebchatConnect: () => false,
      }),
  };
}

(deftest-group "tools.catalog handler", () => {
  beforeEach(() => {
    pluginToolMetaState.clear();
    pluginToolMetaState.set("voice_call", { pluginId: "voice-call", optional: true });
    pluginToolMetaState.set("matrix_room", { pluginId: "matrix", optional: false });
  });

  (deftest "rejects invalid params", async () => {
    const { respond, invoke } = createInvokeParams({ extra: true });
    await invoke();
    const call = respond.mock.calls[0] as RespondCall | undefined;
    (expect* call?.[0]).is(false);
    (expect* call?.[2]?.code).is(ErrorCodes.INVALID_REQUEST);
    (expect* call?.[2]?.message).contains("invalid tools.catalog params");
  });

  (deftest "rejects unknown agent ids", async () => {
    const { respond, invoke } = createInvokeParams({ agentId: "unknown-agent" });
    await invoke();
    const call = respond.mock.calls[0] as RespondCall | undefined;
    (expect* call?.[0]).is(false);
    (expect* call?.[2]?.code).is(ErrorCodes.INVALID_REQUEST);
    (expect* call?.[2]?.message).contains("unknown agent id");
  });

  (deftest "returns core groups including tts and excludes plugins when includePlugins=false", async () => {
    const { respond, invoke } = createInvokeParams({ includePlugins: false });
    await invoke();
    const call = respond.mock.calls[0] as RespondCall | undefined;
    (expect* call?.[0]).is(true);
    const payload = call?.[1] as
      | {
          agentId: string;
          groups: Array<{
            id: string;
            source: "core" | "plugin";
            tools: Array<{ id: string; source: "core" | "plugin" }>;
          }>;
        }
      | undefined;
    (expect* payload?.agentId).is("main");
    (expect* payload?.groups.some((group) => group.source === "plugin")).is(false);
    const media = payload?.groups.find((group) => group.id === "media");
    (expect* media?.tools.some((tool) => tool.id === "tts" && tool.source === "core")).is(true);
  });

  (deftest "includes plugin groups with plugin metadata", async () => {
    const { respond, invoke } = createInvokeParams({});
    await invoke();
    const call = respond.mock.calls[0] as RespondCall | undefined;
    (expect* call?.[0]).is(true);
    const payload = call?.[1] as
      | {
          groups: Array<{
            source: "core" | "plugin";
            pluginId?: string;
            tools: Array<{
              id: string;
              source: "core" | "plugin";
              pluginId?: string;
              optional?: boolean;
            }>;
          }>;
        }
      | undefined;
    const pluginGroups = (payload?.groups ?? []).filter((group) => group.source === "plugin");
    (expect* pluginGroups.length).toBeGreaterThan(0);
    const voiceCall = pluginGroups
      .flatMap((group) => group.tools)
      .find((tool) => tool.id === "voice_call");
    (expect* voiceCall).matches-object({
      source: "plugin",
      pluginId: "voice-call",
      optional: true,
    });
  });
});
