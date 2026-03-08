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
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import * as chromeModule from "./chrome.js";
import { InvalidBrowserNavigationUrlError } from "./navigation-guard.js";
import { closePlaywrightBrowserConnection, createPageViaPlaywright } from "./pw-session.js";

const connectOverCdpSpy = mock:spyOn(chromium, "connectOverCDP");
const getChromeWebSocketUrlSpy = mock:spyOn(chromeModule, "getChromeWebSocketUrl");

function installBrowserMocks() {
  const pageOn = mock:fn();
  const pageGoto = mock:fn(async () => {});
  const pageTitle = mock:fn(async () => "");
  const pageUrl = mock:fn(() => "about:blank");
  const contextOn = mock:fn();
  const browserOn = mock:fn();
  const browserClose = mock:fn(async () => {});
  const sessionSend = mock:fn(async (method: string) => {
    if (method === "Target.getTargetInfo") {
      return { targetInfo: { targetId: "TARGET_1" } };
    }
    return {};
  });
  const sessionDetach = mock:fn(async () => {});

  const context = {
    pages: () => [],
    on: contextOn,
    newPage: mock:fn(async () => page),
    newCDPSession: mock:fn(async () => ({
      send: sessionSend,
      detach: sessionDetach,
    })),
  } as unknown as import("playwright-core").BrowserContext;

  const page = {
    on: pageOn,
    context: () => context,
    goto: pageGoto,
    title: pageTitle,
    url: pageUrl,
  } as unknown as import("playwright-core").Page;

  const browser = {
    contexts: () => [context],
    on: browserOn,
    close: browserClose,
  } as unknown as import("playwright-core").Browser;

  connectOverCdpSpy.mockResolvedValue(browser);
  getChromeWebSocketUrlSpy.mockResolvedValue(null);

  return { pageGoto, browserClose };
}

afterEach(async () => {
  connectOverCdpSpy.mockClear();
  getChromeWebSocketUrlSpy.mockClear();
  await closePlaywrightBrowserConnection().catch(() => {});
});

(deftest-group "pw-session createPageViaPlaywright navigation guard", () => {
  (deftest "blocks unsupported non-network URLs", async () => {
    const { pageGoto } = installBrowserMocks();

    await (expect* 
      createPageViaPlaywright({
        cdpUrl: "http://127.0.0.1:18792",
        url: "file:///etc/passwd",
      }),
    ).rejects.toBeInstanceOf(InvalidBrowserNavigationUrlError);

    (expect* pageGoto).not.toHaveBeenCalled();
  });

  (deftest "allows about:blank without network navigation", async () => {
    const { pageGoto } = installBrowserMocks();

    const created = await createPageViaPlaywright({
      cdpUrl: "http://127.0.0.1:18792",
      url: "about:blank",
    });

    (expect* created.targetId).is("TARGET_1");
    (expect* pageGoto).not.toHaveBeenCalled();
  });
});
