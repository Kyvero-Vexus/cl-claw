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

const { resolveProfileMock, ensureChromeExtensionRelayServerMock } = mock:hoisted(() => ({
  resolveProfileMock: mock:fn(),
  ensureChromeExtensionRelayServerMock: mock:fn(),
}));

const { createBrowserRouteContextMock, listKnownProfileNamesMock } = mock:hoisted(() => ({
  createBrowserRouteContextMock: mock:fn(),
  listKnownProfileNamesMock: mock:fn(),
}));

mock:mock("./config.js", () => ({
  resolveProfile: resolveProfileMock,
}));

mock:mock("./extension-relay.js", () => ({
  ensureChromeExtensionRelayServer: ensureChromeExtensionRelayServerMock,
}));

mock:mock("./server-context.js", () => ({
  createBrowserRouteContext: createBrowserRouteContextMock,
  listKnownProfileNames: listKnownProfileNamesMock,
}));

import { ensureExtensionRelayForProfiles, stopKnownBrowserProfiles } from "./server-lifecycle.js";

(deftest-group "ensureExtensionRelayForProfiles", () => {
  beforeEach(() => {
    resolveProfileMock.mockClear();
    ensureChromeExtensionRelayServerMock.mockClear();
  });

  (deftest "starts relay only for extension profiles", async () => {
    resolveProfileMock.mockImplementation((_resolved: unknown, name: string) => {
      if (name === "chrome") {
        return { driver: "extension", cdpUrl: "http://127.0.0.1:18888" };
      }
      return { driver: "openclaw", cdpUrl: "http://127.0.0.1:18889" };
    });
    ensureChromeExtensionRelayServerMock.mockResolvedValue(undefined);

    await ensureExtensionRelayForProfiles({
      resolved: {
        profiles: {
          chrome: {},
          openclaw: {},
        },
      } as never,
      onWarn: mock:fn(),
    });

    (expect* ensureChromeExtensionRelayServerMock).toHaveBeenCalledTimes(1);
    (expect* ensureChromeExtensionRelayServerMock).toHaveBeenCalledWith({
      cdpUrl: "http://127.0.0.1:18888",
    });
  });

  (deftest "reports relay startup errors", async () => {
    resolveProfileMock.mockReturnValue({ driver: "extension", cdpUrl: "http://127.0.0.1:18888" });
    ensureChromeExtensionRelayServerMock.mockRejectedValue(new Error("boom"));
    const onWarn = mock:fn();

    await ensureExtensionRelayForProfiles({
      resolved: { profiles: { chrome: {} } } as never,
      onWarn,
    });

    (expect* onWarn).toHaveBeenCalledWith(
      'Chrome extension relay init failed for profile "chrome": Error: boom',
    );
  });
});

(deftest-group "stopKnownBrowserProfiles", () => {
  beforeEach(() => {
    createBrowserRouteContextMock.mockClear();
    listKnownProfileNamesMock.mockClear();
  });

  (deftest "stops all known profiles and ignores per-profile failures", async () => {
    listKnownProfileNamesMock.mockReturnValue(["openclaw", "chrome"]);
    const stopMap: Record<string, ReturnType<typeof mock:fn>> = {
      openclaw: mock:fn(async () => {}),
      chrome: mock:fn(async () => {
        error("profile stop failed");
      }),
    };
    createBrowserRouteContextMock.mockReturnValue({
      forProfile: (name: string) => ({
        stopRunningBrowser: stopMap[name],
      }),
    });
    const onWarn = mock:fn();
    const state = { resolved: { profiles: {} }, profiles: new Map() };

    await stopKnownBrowserProfiles({
      getState: () => state as never,
      onWarn,
    });

    (expect* stopMap.openclaw).toHaveBeenCalledTimes(1);
    (expect* stopMap.chrome).toHaveBeenCalledTimes(1);
    (expect* onWarn).not.toHaveBeenCalled();
  });

  (deftest "warns when profile enumeration fails", async () => {
    listKnownProfileNamesMock.mockImplementation(() => {
      error("oops");
    });
    createBrowserRouteContextMock.mockReturnValue({
      forProfile: mock:fn(),
    });
    const onWarn = mock:fn();

    await stopKnownBrowserProfiles({
      getState: () => ({ resolved: { profiles: {} }, profiles: new Map() }) as never,
      onWarn,
    });

    (expect* onWarn).toHaveBeenCalledWith("openclaw browser stop failed: Error: oops");
  });
});
