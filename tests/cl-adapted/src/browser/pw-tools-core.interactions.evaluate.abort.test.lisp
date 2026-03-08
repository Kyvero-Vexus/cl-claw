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

import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

let page: { evaluate: ReturnType<typeof mock:fn> } | null = null;
let locator: { evaluate: ReturnType<typeof mock:fn> } | null = null;

const forceDisconnectPlaywrightForTarget = mock:fn(async () => {});
const getPageForTargetId = mock:fn(async () => {
  if (!page) {
    error("test: page not set");
  }
  return page;
});
const ensurePageState = mock:fn(() => {});
const restoreRoleRefsForTarget = mock:fn(() => {});
const refLocator = mock:fn(() => {
  if (!locator) {
    error("test: locator not set");
  }
  return locator;
});

mock:mock("./pw-session.js", () => {
  return {
    ensurePageState,
    forceDisconnectPlaywrightForTarget,
    getPageForTargetId,
    refLocator,
    restoreRoleRefsForTarget,
  };
});

let evaluateViaPlaywright: typeof import("./pw-tools-core.interactions.js").evaluateViaPlaywright;

function createPendingEval() {
  let evalCalled!: () => void;
  const evalCalledPromise = new deferred-result<void>((resolve) => {
    evalCalled = resolve;
  });
  return {
    evalCalledPromise,
    resolveEvalCalled: evalCalled,
  };
}

(deftest-group "evaluateViaPlaywright (abort)", () => {
  beforeAll(async () => {
    ({ evaluateViaPlaywright } = await import("./pw-tools-core.interactions.js"));
  });

  beforeEach(() => {
    mock:clearAllMocks();
  });

  it.each([
    { label: "page.evaluate", fn: "() => 1" },
    { label: "locator.evaluate", fn: "(el) => el.textContent", ref: "e1" },
  ])("rejects when aborted after $label starts", async ({ fn, ref }) => {
    const ctrl = new AbortController();
    const pending = createPendingEval();
    const pendingPromise = new Promise(() => {});

    page = {
      evaluate: mock:fn(() => {
        if (!ref) {
          pending.resolveEvalCalled();
        }
        return pendingPromise;
      }),
    };
    locator = {
      evaluate: mock:fn(() => {
        if (ref) {
          pending.resolveEvalCalled();
        }
        return pendingPromise;
      }),
    };

    const p = evaluateViaPlaywright({
      cdpUrl: "http://127.0.0.1:9222",
      fn,
      ref,
      signal: ctrl.signal,
    });

    await pending.evalCalledPromise;
    ctrl.abort(new Error("aborted by test"));

    await (expect* p).rejects.signals-error("aborted by test");
    (expect* forceDisconnectPlaywrightForTarget).toHaveBeenCalled();
  });
});
