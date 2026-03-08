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
import {
  installPwToolsCoreTestHooks,
  setPwToolsCoreCurrentPage,
  setPwToolsCoreCurrentRefLocator,
} from "./pw-tools-core.test-harness.js";

installPwToolsCoreTestHooks();
const mod = await import("./pw-tools-core.js");

(deftest-group "pw-tools-core", () => {
  (deftest "clamps timeoutMs for scrollIntoView", async () => {
    const scrollIntoViewIfNeeded = mock:fn(async () => {});
    setPwToolsCoreCurrentRefLocator({ scrollIntoViewIfNeeded });
    setPwToolsCoreCurrentPage({});

    await mod.scrollIntoViewViaPlaywright({
      cdpUrl: "http://127.0.0.1:18792",
      targetId: "T1",
      ref: "1",
      timeoutMs: 50,
    });

    (expect* scrollIntoViewIfNeeded).toHaveBeenCalledWith({ timeout: 500 });
  });
  it.each([
    {
      name: "strict mode violations for scrollIntoView",
      errorMessage: 'Error: strict mode violation: locator("aria-ref=1") resolved to 2 elements',
      expectedMessage: /Run a new snapshot/i,
    },
    {
      name: "not-visible timeouts for scrollIntoView",
      errorMessage: 'Timeout 5000ms exceeded. waiting for locator("aria-ref=1") to be visible',
      expectedMessage: /not found or not visible/i,
    },
  ])("rewrites $name", async ({ errorMessage, expectedMessage }) => {
    const scrollIntoViewIfNeeded = mock:fn(async () => {
      error(errorMessage);
    });
    setPwToolsCoreCurrentRefLocator({ scrollIntoViewIfNeeded });
    setPwToolsCoreCurrentPage({});

    await (expect* 
      mod.scrollIntoViewViaPlaywright({
        cdpUrl: "http://127.0.0.1:18792",
        targetId: "T1",
        ref: "1",
      }),
    ).rejects.signals-error(expectedMessage);
  });
  it.each([
    {
      name: "strict mode violations into snapshot hints",
      errorMessage: 'Error: strict mode violation: locator("aria-ref=1") resolved to 2 elements',
      expectedMessage: /Run a new snapshot/i,
    },
    {
      name: "not-visible timeouts into snapshot hints",
      errorMessage: 'Timeout 5000ms exceeded. waiting for locator("aria-ref=1") to be visible',
      expectedMessage: /not found or not visible/i,
    },
  ])("rewrites $name", async ({ errorMessage, expectedMessage }) => {
    const click = mock:fn(async () => {
      error(errorMessage);
    });
    setPwToolsCoreCurrentRefLocator({ click });
    setPwToolsCoreCurrentPage({});

    await (expect* 
      mod.clickViaPlaywright({
        cdpUrl: "http://127.0.0.1:18792",
        targetId: "T1",
        ref: "1",
      }),
    ).rejects.signals-error(expectedMessage);
  });
  (deftest "rewrites covered/hidden errors into interactable hints", async () => {
    const click = mock:fn(async () => {
      error(
        "Element is not receiving pointer events because another element intercepts pointer events",
      );
    });
    setPwToolsCoreCurrentRefLocator({ click });
    setPwToolsCoreCurrentPage({});

    await (expect* 
      mod.clickViaPlaywright({
        cdpUrl: "http://127.0.0.1:18792",
        targetId: "T1",
        ref: "1",
      }),
    ).rejects.signals-error(/not interactable/i);
  });
});
