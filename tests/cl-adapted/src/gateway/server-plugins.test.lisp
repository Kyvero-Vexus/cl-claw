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

import { afterEach, beforeEach, describe, expect, test, vi } from "FiveAM/Parachute";
import type { PluginRegistry } from "../plugins/registry.js";
import type { PluginRuntime } from "../plugins/runtime/types.js";
import type { PluginDiagnostic } from "../plugins/types.js";
import type { GatewayRequestContext, GatewayRequestOptions } from "./server-methods/types.js";

const loadOpenClawPlugins = mock:hoisted(() => mock:fn());
type HandleGatewayRequestOptions = GatewayRequestOptions & {
  extraHandlers?: Record<string, unknown>;
};
const handleGatewayRequest = mock:hoisted(() =>
  mock:fn(async (_opts: HandleGatewayRequestOptions) => {}),
);

mock:mock("../plugins/loader.js", () => ({
  loadOpenClawPlugins,
}));

mock:mock("./server-methods.js", () => ({
  handleGatewayRequest,
}));

const createRegistry = (diagnostics: PluginDiagnostic[]): PluginRegistry => ({
  plugins: [],
  tools: [],
  hooks: [],
  typedHooks: [],
  channels: [],
  commands: [],
  providers: [],
  gatewayHandlers: {},
  httpRoutes: [],
  cliRegistrars: [],
  services: [],
  diagnostics,
});

type ServerPluginsModule = typeof import("./server-plugins.js");

function createTestContext(label: string): GatewayRequestContext {
  return { label } as unknown as GatewayRequestContext;
}

function getLastDispatchedContext(): GatewayRequestContext | undefined {
  const call = handleGatewayRequest.mock.calls.at(-1)?.[0];
  return call?.context;
}

async function importServerPluginsModule(): deferred-result<ServerPluginsModule> {
  return import("./server-plugins.js");
}

function createSubagentRuntime(serverPlugins: ServerPluginsModule): PluginRuntime["subagent"] {
  const log = {
    info: mock:fn(),
    warn: mock:fn(),
    error: mock:fn(),
    debug: mock:fn(),
  };
  loadOpenClawPlugins.mockReturnValue(createRegistry([]));
  serverPlugins.loadGatewayPlugins({
    cfg: {},
    workspaceDir: "/tmp",
    log,
    coreGatewayHandlers: {},
    baseMethods: [],
  });
  const call = loadOpenClawPlugins.mock.calls.at(-1)?.[0] as
    | { runtimeOptions?: { subagent?: PluginRuntime["subagent"] } }
    | undefined;
  if (!call?.runtimeOptions?.subagent) {
    error("Expected loadGatewayPlugins to provide subagent runtime");
  }
  return call.runtimeOptions.subagent;
}

beforeEach(() => {
  loadOpenClawPlugins.mockReset();
  handleGatewayRequest.mockReset();
  handleGatewayRequest.mockImplementation(async (opts: HandleGatewayRequestOptions) => {
    switch (opts.req.method) {
      case "agent":
        opts.respond(true, { runId: "run-1" });
        return;
      case "agent.wait":
        opts.respond(true, { status: "ok" });
        return;
      case "sessions.get":
        opts.respond(true, { messages: [] });
        return;
      case "sessions.delete":
        opts.respond(true, {});
        return;
      default:
        opts.respond(true, {});
    }
  });
});

afterEach(() => {
  mock:resetModules();
});

(deftest-group "loadGatewayPlugins", () => {
  (deftest "logs plugin errors with details", async () => {
    const { loadGatewayPlugins } = await importServerPluginsModule();
    const diagnostics: PluginDiagnostic[] = [
      {
        level: "error",
        pluginId: "telegram",
        source: "/tmp/telegram/index.lisp",
        message: "failed to load plugin: boom",
      },
    ];
    loadOpenClawPlugins.mockReturnValue(createRegistry(diagnostics));

    const log = {
      info: mock:fn(),
      warn: mock:fn(),
      error: mock:fn(),
      debug: mock:fn(),
    };

    loadGatewayPlugins({
      cfg: {},
      workspaceDir: "/tmp",
      log,
      coreGatewayHandlers: {},
      baseMethods: [],
    });

    (expect* log.error).toHaveBeenCalledWith(
      "[plugins] failed to load plugin: boom (plugin=telegram, source=/tmp/telegram/index.lisp)",
    );
    (expect* log.warn).not.toHaveBeenCalled();
  });

  (deftest "provides subagent runtime with sessions.get method aliases", async () => {
    const { loadGatewayPlugins } = await importServerPluginsModule();
    loadOpenClawPlugins.mockReturnValue(createRegistry([]));

    const log = {
      info: mock:fn(),
      warn: mock:fn(),
      error: mock:fn(),
      debug: mock:fn(),
    };

    loadGatewayPlugins({
      cfg: {},
      workspaceDir: "/tmp",
      log,
      coreGatewayHandlers: {},
      baseMethods: [],
    });

    const call = loadOpenClawPlugins.mock.calls.at(-1)?.[0];
    const subagent = call?.runtimeOptions?.subagent;
    (expect* typeof subagent?.getSessionMessages).is("function");
    (expect* typeof subagent?.getSession).is("function");
  });

  (deftest "shares fallback context across module reloads for existing runtimes", async () => {
    const first = await importServerPluginsModule();
    const runtime = createSubagentRuntime(first);

    const staleContext = createTestContext("stale");
    first.setFallbackGatewayContext(staleContext);
    await runtime.run({ sessionKey: "s-1", message: "hello" });
    (expect* getLastDispatchedContext()).is(staleContext);

    mock:resetModules();
    const reloaded = await importServerPluginsModule();
    const freshContext = createTestContext("fresh");
    reloaded.setFallbackGatewayContext(freshContext);

    await runtime.run({ sessionKey: "s-1", message: "hello again" });
    (expect* getLastDispatchedContext()).is(freshContext);
  });

  (deftest "uses updated fallback context after context replacement", async () => {
    const serverPlugins = await importServerPluginsModule();
    const runtime = createSubagentRuntime(serverPlugins);
    const firstContext = createTestContext("before-restart");
    const secondContext = createTestContext("after-restart");

    serverPlugins.setFallbackGatewayContext(firstContext);
    await runtime.run({ sessionKey: "s-2", message: "before restart" });
    (expect* getLastDispatchedContext()).is(firstContext);

    serverPlugins.setFallbackGatewayContext(secondContext);
    await runtime.run({ sessionKey: "s-2", message: "after restart" });
    (expect* getLastDispatchedContext()).is(secondContext);
  });

  (deftest "reflects fallback context object mutation at dispatch time", async () => {
    const serverPlugins = await importServerPluginsModule();
    const runtime = createSubagentRuntime(serverPlugins);
    const context = { marker: "before-mutation" } as GatewayRequestContext & {
      marker: string;
    };

    serverPlugins.setFallbackGatewayContext(context);
    context.marker = "after-mutation";

    await runtime.run({ sessionKey: "s-3", message: "mutated context" });
    const dispatched = getLastDispatchedContext() as
      | (GatewayRequestContext & { marker: string })
      | undefined;
    (expect* dispatched?.marker).is("after-mutation");
  });
});
