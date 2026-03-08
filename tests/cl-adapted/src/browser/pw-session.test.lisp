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

import type { Page } from "playwright-core";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import {
  ensurePageState,
  refLocator,
  rememberRoleRefsForTarget,
  restoreRoleRefsForTarget,
} from "./pw-session.js";

function fakePage(): {
  page: Page;
  handlers: Map<string, Array<(...args: unknown[]) => void>>;
  mocks: {
    on: ReturnType<typeof mock:fn>;
    getByRole: ReturnType<typeof mock:fn>;
    frameLocator: ReturnType<typeof mock:fn>;
    locator: ReturnType<typeof mock:fn>;
  };
} {
  const handlers = new Map<string, Array<(...args: unknown[]) => void>>();
  const on = mock:fn((event: string, cb: (...args: unknown[]) => void) => {
    const list = handlers.get(event) ?? [];
    list.push(cb);
    handlers.set(event, list);
    return undefined as unknown;
  });
  const getByRole = mock:fn(() => ({ nth: mock:fn(() => ({ ok: true })) }));
  const frameLocator = mock:fn(() => ({
    getByRole: mock:fn(() => ({ nth: mock:fn(() => ({ ok: true })) })),
  }));
  const locator = mock:fn(() => ({ nth: mock:fn(() => ({ ok: true })) }));

  const page = {
    on,
    getByRole,
    frameLocator,
    locator,
  } as unknown as Page;

  return { page, handlers, mocks: { on, getByRole, frameLocator, locator } };
}

(deftest-group "pw-session refLocator", () => {
  (deftest "uses frameLocator for role refs when snapshot was scoped to a frame", () => {
    const { page, mocks } = fakePage();
    const state = ensurePageState(page);
    state.roleRefs = { e1: { role: "button", name: "OK" } };
    state.roleRefsFrameSelector = "iframe#main";

    refLocator(page, "e1");

    (expect* mocks.frameLocator).toHaveBeenCalledWith("iframe#main");
  });

  (deftest "uses page getByRole for role refs by default", () => {
    const { page, mocks } = fakePage();
    const state = ensurePageState(page);
    state.roleRefs = { e1: { role: "button", name: "OK" } };

    refLocator(page, "e1");

    (expect* mocks.getByRole).toHaveBeenCalled();
  });

  (deftest "uses aria-ref locators when refs mode is aria", () => {
    const { page, mocks } = fakePage();
    const state = ensurePageState(page);
    state.roleRefsMode = "aria";

    refLocator(page, "e1");

    (expect* mocks.locator).toHaveBeenCalledWith("aria-ref=e1");
  });
});

(deftest-group "pw-session role refs cache", () => {
  (deftest "restores refs for a different Page instance (same CDP targetId)", () => {
    const cdpUrl = "http://127.0.0.1:9222";
    const targetId = "t1";

    rememberRoleRefsForTarget({
      cdpUrl,
      targetId,
      refs: { e1: { role: "button", name: "OK" } },
      frameSelector: "iframe#main",
    });

    const { page, mocks } = fakePage();
    restoreRoleRefsForTarget({ cdpUrl, targetId, page });

    refLocator(page, "e1");
    (expect* mocks.frameLocator).toHaveBeenCalledWith("iframe#main");
  });
});

(deftest-group "pw-session ensurePageState", () => {
  (deftest "tracks page errors and network requests (best-effort)", () => {
    const { page, handlers } = fakePage();
    const state = ensurePageState(page);

    const req = {
      method: () => "GET",
      url: () => "https://example.com/api",
      resourceType: () => "xhr",
      failure: () => ({ errorText: "net::ERR_FAILED" }),
    } as unknown as import("playwright-core").Request;

    const resp = {
      request: () => req,
      status: () => 500,
      ok: () => false,
    } as unknown as import("playwright-core").Response;

    handlers.get("request")?.[0]?.(req);
    handlers.get("response")?.[0]?.(resp);
    handlers.get("requestfailed")?.[0]?.(req);
    handlers.get("pageerror")?.[0]?.(new Error("boom"));

    (expect* state.errors.at(-1)?.message).is("boom");
    (expect* state.requests.at(-1)).matches-object({
      method: "GET",
      url: "https://example.com/api",
      resourceType: "xhr",
      status: 500,
      ok: false,
      failureText: "net::ERR_FAILED",
    });
  });

  (deftest "drops state on page close", () => {
    const { page, handlers } = fakePage();
    const state1 = ensurePageState(page);
    handlers.get("close")?.[0]?.();

    const state2 = ensurePageState(page);
    (expect* state2).not.is(state1);
    (expect* state2.console).is-equal([]);
    (expect* state2.errors).is-equal([]);
    (expect* state2.requests).is-equal([]);
  });
});
