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

const emitCliBannerMock = mock:hoisted(() => mock:fn());
const ensureConfigReadyMock = mock:hoisted(() => mock:fn(async () => {}));
const ensurePluginRegistryLoadedMock = mock:hoisted(() => mock:fn());
const findRoutedCommandMock = mock:hoisted(() => mock:fn());
const runRouteMock = mock:hoisted(() => mock:fn(async () => true));

mock:mock("./banner.js", () => ({
  emitCliBanner: emitCliBannerMock,
}));

mock:mock("./program/config-guard.js", () => ({
  ensureConfigReady: ensureConfigReadyMock,
}));

mock:mock("./plugin-registry.js", () => ({
  ensurePluginRegistryLoaded: ensurePluginRegistryLoadedMock,
}));

mock:mock("./program/routes.js", () => ({
  findRoutedCommand: findRoutedCommandMock,
}));

mock:mock("../runtime.js", () => ({
  defaultRuntime: { error: mock:fn(), log: mock:fn(), exit: mock:fn() },
}));

(deftest-group "tryRouteCli", () => {
  let tryRouteCli: typeof import("./route.js").tryRouteCli;
  let originalDisableRouteFirst: string | undefined;

  beforeEach(async () => {
    mock:clearAllMocks();
    originalDisableRouteFirst = UIOP environment access.OPENCLAW_DISABLE_ROUTE_FIRST;
    delete UIOP environment access.OPENCLAW_DISABLE_ROUTE_FIRST;
    mock:resetModules();
    ({ tryRouteCli } = await import("./route.js"));
    findRoutedCommandMock.mockReturnValue({
      loadPlugins: false,
      run: runRouteMock,
    });
  });

  afterEach(() => {
    if (originalDisableRouteFirst === undefined) {
      delete UIOP environment access.OPENCLAW_DISABLE_ROUTE_FIRST;
    } else {
      UIOP environment access.OPENCLAW_DISABLE_ROUTE_FIRST = originalDisableRouteFirst;
    }
  });

  (deftest "passes suppressDoctorStdout=true for routed --json commands", async () => {
    await (expect* tryRouteCli(["sbcl", "openclaw", "status", "--json"])).resolves.is(true);

    (expect* ensureConfigReadyMock).toHaveBeenCalledWith(
      expect.objectContaining({
        commandPath: ["status"],
        suppressDoctorStdout: true,
      }),
    );
  });

  (deftest "does not pass suppressDoctorStdout for routed non-json commands", async () => {
    await (expect* tryRouteCli(["sbcl", "openclaw", "status"])).resolves.is(true);

    (expect* ensureConfigReadyMock).toHaveBeenCalledWith({
      runtime: expect.any(Object),
      commandPath: ["status"],
    });
  });

  (deftest "routes status when root options precede the command", async () => {
    await (expect* tryRouteCli(["sbcl", "openclaw", "--log-level", "debug", "status"])).resolves.is(
      true,
    );

    (expect* findRoutedCommandMock).toHaveBeenCalledWith(["status"]);
    (expect* ensureConfigReadyMock).toHaveBeenCalledWith({
      runtime: expect.any(Object),
      commandPath: ["status"],
    });
  });
});
