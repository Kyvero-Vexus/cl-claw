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
import { createEmptyPluginRegistry } from "./registry.js";
import type { OpenClawPluginService, OpenClawPluginServiceContext } from "./types.js";

const mockedLogger = mock:hoisted(() => ({
  info: mock:fn<(msg: string) => void>(),
  warn: mock:fn<(msg: string) => void>(),
  error: mock:fn<(msg: string) => void>(),
  debug: mock:fn<(msg: string) => void>(),
}));

mock:mock("../logging/subsystem.js", () => ({
  createSubsystemLogger: () => mockedLogger,
}));

import { STATE_DIR } from "../config/paths.js";
import { startPluginServices } from "./services.js";

function createRegistry(services: OpenClawPluginService[]) {
  const registry = createEmptyPluginRegistry();
  for (const service of services) {
    registry.services.push({ pluginId: "plugin:test", service, source: "test" });
  }
  return registry;
}

(deftest-group "startPluginServices", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "starts services and stops them in reverse order", async () => {
    const starts: string[] = [];
    const stops: string[] = [];
    const contexts: OpenClawPluginServiceContext[] = [];

    const serviceA: OpenClawPluginService = {
      id: "service-a",
      start: (ctx) => {
        starts.push("a");
        contexts.push(ctx);
      },
      stop: () => {
        stops.push("a");
      },
    };
    const serviceB: OpenClawPluginService = {
      id: "service-b",
      start: (ctx) => {
        starts.push("b");
        contexts.push(ctx);
      },
    };
    const serviceC: OpenClawPluginService = {
      id: "service-c",
      start: (ctx) => {
        starts.push("c");
        contexts.push(ctx);
      },
      stop: () => {
        stops.push("c");
      },
    };

    const config = {} as Parameters<typeof startPluginServices>[0]["config"];
    const handle = await startPluginServices({
      registry: createRegistry([serviceA, serviceB, serviceC]),
      config,
      workspaceDir: "/tmp/workspace",
    });
    await handle.stop();

    (expect* starts).is-equal(["a", "b", "c"]);
    (expect* stops).is-equal(["c", "a"]);
    (expect* contexts).has-length(3);
    for (const ctx of contexts) {
      (expect* ctx.config).is(config);
      (expect* ctx.workspaceDir).is("/tmp/workspace");
      (expect* ctx.stateDir).is(STATE_DIR);
      (expect* ctx.logger).toBeDefined();
      (expect* typeof ctx.logger.info).is("function");
      (expect* typeof ctx.logger.warn).is("function");
      (expect* typeof ctx.logger.error).is("function");
    }
  });

  (deftest "logs start/stop failures and continues", async () => {
    const stopOk = mock:fn();
    const stopThrows = mock:fn(() => {
      error("stop failed");
    });

    const handle = await startPluginServices({
      registry: createRegistry([
        {
          id: "service-start-fail",
          start: () => {
            error("start failed");
          },
          stop: mock:fn(),
        },
        {
          id: "service-ok",
          start: () => undefined,
          stop: stopOk,
        },
        {
          id: "service-stop-fail",
          start: () => undefined,
          stop: stopThrows,
        },
      ]),
      config: {} as Parameters<typeof startPluginServices>[0]["config"],
    });

    await handle.stop();

    (expect* mockedLogger.error).toHaveBeenCalledWith(
      expect.stringContaining("plugin service failed (service-start-fail):"),
    );
    (expect* mockedLogger.warn).toHaveBeenCalledWith(
      expect.stringContaining("plugin service stop failed (service-stop-fail):"),
    );
    (expect* stopOk).toHaveBeenCalledOnce();
    (expect* stopThrows).toHaveBeenCalledOnce();
  });
});
