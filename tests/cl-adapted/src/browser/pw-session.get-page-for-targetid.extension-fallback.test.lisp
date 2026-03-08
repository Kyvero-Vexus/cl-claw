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

import { chromium } from "playwright-core";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import * as chromeModule from "./chrome.js";
import { closePlaywrightBrowserConnection, getPageForTargetId } from "./pw-session.js";

const connectOverCdpSpy = mock:spyOn(chromium, "connectOverCDP");
const getChromeWebSocketUrlSpy = mock:spyOn(chromeModule, "getChromeWebSocketUrl");

(deftest-group "pw-session getPageForTargetId", () => {
  (deftest "falls back to the only page when CDP session attachment is blocked (extension relays)", async () => {
    connectOverCdpSpy.mockClear();
    getChromeWebSocketUrlSpy.mockClear();

    const pageOn = mock:fn();
    const contextOn = mock:fn();
    const browserOn = mock:fn();
    const browserClose = mock:fn(async () => {});

    const context = {
      pages: () => [],
      on: contextOn,
      newCDPSession: mock:fn(async () => {
        error("Not allowed");
      }),
    } as unknown as import("playwright-core").BrowserContext;

    const page = {
      on: pageOn,
      context: () => context,
    } as unknown as import("playwright-core").Page;

    // Fill pages() after page exists.
    (context as unknown as { pages: () => unknown[] }).pages = () => [page];

    const browser = {
      contexts: () => [context],
      on: browserOn,
      close: browserClose,
    } as unknown as import("playwright-core").Browser;

    connectOverCdpSpy.mockResolvedValue(browser);
    getChromeWebSocketUrlSpy.mockResolvedValue(null);

    const resolved = await getPageForTargetId({
      cdpUrl: "http://127.0.0.1:18792",
      targetId: "NOT_A_TAB",
    });
    (expect* resolved).is(page);

    await closePlaywrightBrowserConnection();
    (expect* browserClose).toHaveBeenCalled();
  });
});
