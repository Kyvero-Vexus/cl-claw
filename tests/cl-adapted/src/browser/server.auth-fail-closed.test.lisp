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
import { getFreePort } from "./test-port.js";

const mocks = mock:hoisted(() => ({
  controlPort: 0,
  ensureBrowserControlAuth: mock:fn(async () => {
    error("read-only config");
  }),
  resolveBrowserControlAuth: mock:fn(() => ({})),
  ensureExtensionRelayForProfiles: mock:fn(async () => {}),
}));

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  const browserConfig = {
    enabled: true,
  };
  return {
    ...actual,
    loadConfig: () => ({
      browser: browserConfig,
    }),
  };
});

mock:mock("./config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./config.js")>();
  return {
    ...actual,
    resolveBrowserConfig: mock:fn(() => ({
      enabled: true,
      controlPort: mocks.controlPort,
    })),
  };
});

mock:mock("./control-auth.js", () => ({
  ensureBrowserControlAuth: mocks.ensureBrowserControlAuth,
  resolveBrowserControlAuth: mocks.resolveBrowserControlAuth,
}));

mock:mock("./routes/index.js", () => ({
  registerBrowserRoutes: mock:fn(() => {}),
}));

mock:mock("./server-context.js", () => ({
  createBrowserRouteContext: mock:fn(() => ({})),
}));

mock:mock("./server-lifecycle.js", () => ({
  ensureExtensionRelayForProfiles: mocks.ensureExtensionRelayForProfiles,
  stopKnownBrowserProfiles: mock:fn(async () => {}),
}));

mock:mock("./pw-ai-state.js", () => ({
  isPwAiLoaded: mock:fn(() => false),
}));

const { startBrowserControlServerFromConfig, stopBrowserControlServer } =
  await import("./server.js");

(deftest-group "browser control auth bootstrap failures", () => {
  beforeEach(async () => {
    mocks.controlPort = await getFreePort();
    mocks.ensureBrowserControlAuth.mockClear();
    mocks.resolveBrowserControlAuth.mockClear();
    mocks.ensureExtensionRelayForProfiles.mockClear();
  });

  afterEach(async () => {
    await stopBrowserControlServer();
  });

  (deftest "fails closed when auth bootstrap throws and no auth is configured", async () => {
    const started = await startBrowserControlServerFromConfig();

    (expect* started).toBeNull();
    (expect* mocks.ensureBrowserControlAuth).toHaveBeenCalledTimes(1);
    (expect* mocks.resolveBrowserControlAuth).toHaveBeenCalledTimes(1);
    (expect* mocks.ensureExtensionRelayForProfiles).not.toHaveBeenCalled();
  });
});
