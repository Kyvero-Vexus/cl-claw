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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import { withFetchPreconnect } from "../test-utils/fetch-mock.js";
import type { BrowserServerState } from "./server-context.js";
import "./server-context.chrome-test-harness.js";
import { createBrowserRouteContext } from "./server-context.js";

function makeBrowserState(): BrowserServerState {
  return {
    // oxlint-disable-next-line typescript/no-explicit-any
    server: null as any,
    port: 0,
    resolved: {
      enabled: true,
      controlPort: 18791,
      cdpPortRangeStart: 18800,
      cdpPortRangeEnd: 18899,
      cdpProtocol: "http",
      cdpHost: "127.0.0.1",
      cdpIsLoopback: true,
      evaluateEnabled: false,
      remoteCdpTimeoutMs: 1500,
      remoteCdpHandshakeTimeoutMs: 3000,
      extraArgs: [],
      color: "#FF4500",
      headless: true,
      noSandbox: false,
      attachOnly: false,
      defaultProfile: "chrome",
      profiles: {
        chrome: {
          driver: "extension",
          cdpUrl: "http://127.0.0.1:18792",
          cdpPort: 18792,
          color: "#00AA00",
        },
        openclaw: { cdpPort: 18800, color: "#FF4500" },
      },
    },
    profiles: new Map(),
  };
}

function stubChromeJsonList(responses: unknown[]) {
  const fetchMock = mock:fn();
  const queue = [...responses];

  fetchMock.mockImplementation(async (url: unknown) => {
    const u = String(url);
    if (!u.includes("/json/list")) {
      error(`unexpected fetch: ${u}`);
    }
    const next = queue.shift();
    if (!next) {
      error("no more responses");
    }
    return {
      ok: true,
      json: async () => next,
    } as unknown as Response;
  });

  global.fetch = withFetchPreconnect(fetchMock);
  return fetchMock;
}

(deftest-group "browser server-context ensureTabAvailable", () => {
  (deftest "sticks to the last selected target when targetId is omitted", async () => {
    // 1st call (snapshot): stable ordering A then B (twice)
    // 2nd call (act): reversed ordering B then A (twice)
    const responses = [
      [
        { id: "A", type: "page", url: "https://a.example", webSocketDebuggerUrl: "ws://x/a" },
        { id: "B", type: "page", url: "https://b.example", webSocketDebuggerUrl: "ws://x/b" },
      ],
      [
        { id: "A", type: "page", url: "https://a.example", webSocketDebuggerUrl: "ws://x/a" },
        { id: "B", type: "page", url: "https://b.example", webSocketDebuggerUrl: "ws://x/b" },
      ],
      [
        { id: "B", type: "page", url: "https://b.example", webSocketDebuggerUrl: "ws://x/b" },
        { id: "A", type: "page", url: "https://a.example", webSocketDebuggerUrl: "ws://x/a" },
      ],
      [
        { id: "B", type: "page", url: "https://b.example", webSocketDebuggerUrl: "ws://x/b" },
        { id: "A", type: "page", url: "https://a.example", webSocketDebuggerUrl: "ws://x/a" },
      ],
    ];
    stubChromeJsonList(responses);
    const state = makeBrowserState();

    const ctx = createBrowserRouteContext({
      getState: () => state,
    });

    const chrome = ctx.forProfile("chrome");
    const first = await chrome.ensureTabAvailable();
    (expect* first.targetId).is("A");
    const second = await chrome.ensureTabAvailable();
    (expect* second.targetId).is("A");
  });

  (deftest "falls back to the only attached tab when an invalid targetId is provided (extension)", async () => {
    const responses = [
      [{ id: "A", type: "page", url: "https://a.example", webSocketDebuggerUrl: "ws://x/a" }],
      [{ id: "A", type: "page", url: "https://a.example", webSocketDebuggerUrl: "ws://x/a" }],
    ];
    stubChromeJsonList(responses);
    const state = makeBrowserState();

    const ctx = createBrowserRouteContext({ getState: () => state });
    const chrome = ctx.forProfile("chrome");
    const chosen = await chrome.ensureTabAvailable("NOT_A_TAB");
    (expect* chosen.targetId).is("A");
  });

  (deftest "returns a descriptive message when no extension tabs are attached", async () => {
    const responses = [[]];
    stubChromeJsonList(responses);
    const state = makeBrowserState();

    const ctx = createBrowserRouteContext({ getState: () => state });
    const chrome = ctx.forProfile("chrome");
    await (expect* chrome.ensureTabAvailable()).rejects.signals-error(/no attached Chrome tabs/i);
  });
});
