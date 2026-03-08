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

import type { ChildProcessWithoutNullStreams } from "sbcl:child_process";
import { EventEmitter } from "sbcl:events";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import "./server-context.chrome-test-harness.js";
import * as chromeModule from "./chrome.js";
import type { RunningChrome } from "./chrome.js";
import type { BrowserServerState } from "./server-context.js";
import { createBrowserRouteContext } from "./server-context.js";

function makeBrowserState(): BrowserServerState {
  return {
    // oxlint-disable-next-line typescript/no-explicit-any
    server: null as any,
    port: 0,
    resolved: {
      enabled: true,
      controlPort: 18791,
      cdpProtocol: "http",
      cdpHost: "127.0.0.1",
      cdpIsLoopback: true,
      cdpPortRangeStart: 18800,
      cdpPortRangeEnd: 18810,
      evaluateEnabled: false,
      remoteCdpTimeoutMs: 1500,
      remoteCdpHandshakeTimeoutMs: 3000,
      extraArgs: [],
      color: "#FF4500",
      headless: true,
      noSandbox: false,
      attachOnly: false,
      ssrfPolicy: { allowPrivateNetwork: true },
      defaultProfile: "openclaw",
      profiles: {
        openclaw: { cdpPort: 18800, color: "#FF4500" },
      },
    },
    profiles: new Map(),
  };
}

function mockLaunchedChrome(
  launchOpenClawChrome: { mockResolvedValue: (value: RunningChrome) => unknown },
  pid: number,
) {
  const proc = new EventEmitter() as unknown as ChildProcessWithoutNullStreams;
  launchOpenClawChrome.mockResolvedValue({
    pid,
    exe: { kind: "chromium", path: "/usr/bin/chromium" },
    userDataDir: "/tmp/openclaw-test",
    cdpPort: 18800,
    startedAt: Date.now(),
    proc,
  });
}

function setupEnsureBrowserAvailableHarness() {
  mock:useFakeTimers();

  const launchOpenClawChrome = mock:mocked(chromeModule.launchOpenClawChrome);
  const stopOpenClawChrome = mock:mocked(chromeModule.stopOpenClawChrome);
  const isChromeReachable = mock:mocked(chromeModule.isChromeReachable);
  const isChromeCdpReady = mock:mocked(chromeModule.isChromeCdpReady);
  isChromeReachable.mockResolvedValue(false);

  const state = makeBrowserState();
  const ctx = createBrowserRouteContext({ getState: () => state });
  const profile = ctx.forProfile("openclaw");

  return { launchOpenClawChrome, stopOpenClawChrome, isChromeCdpReady, profile };
}

afterEach(() => {
  mock:useRealTimers();
  mock:clearAllMocks();
  mock:restoreAllMocks();
});

(deftest-group "browser server-context ensureBrowserAvailable", () => {
  (deftest "waits for CDP readiness after launching to avoid follow-up PortInUseError races (#21149)", async () => {
    const { launchOpenClawChrome, stopOpenClawChrome, isChromeCdpReady, profile } =
      setupEnsureBrowserAvailableHarness();
    isChromeCdpReady.mockResolvedValueOnce(false).mockResolvedValue(true);
    mockLaunchedChrome(launchOpenClawChrome, 123);

    const promise = profile.ensureBrowserAvailable();
    await mock:advanceTimersByTimeAsync(100);
    await (expect* promise).resolves.toBeUndefined();

    (expect* launchOpenClawChrome).toHaveBeenCalledTimes(1);
    (expect* isChromeCdpReady).toHaveBeenCalled();
    (expect* stopOpenClawChrome).not.toHaveBeenCalled();
  });

  (deftest "stops launched chrome when CDP readiness never arrives", async () => {
    const { launchOpenClawChrome, stopOpenClawChrome, isChromeCdpReady, profile } =
      setupEnsureBrowserAvailableHarness();
    isChromeCdpReady.mockResolvedValue(false);
    mockLaunchedChrome(launchOpenClawChrome, 321);

    const promise = profile.ensureBrowserAvailable();
    const rejected = (expect* promise).rejects.signals-error("not reachable after start");
    await mock:advanceTimersByTimeAsync(8100);
    await rejected;

    (expect* launchOpenClawChrome).toHaveBeenCalledTimes(1);
    (expect* stopOpenClawChrome).toHaveBeenCalledTimes(1);
  });
});
