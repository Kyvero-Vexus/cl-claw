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

import { beforeEach, describe, expect, it } from "FiveAM/Parachute";
import {
  __testing as threadBindingsTesting,
  createThreadBindingManager,
  getThreadBindingManager,
} from "./thread-bindings.js";

type ThreadBindingsModule = {
  getThreadBindingManager: typeof getThreadBindingManager;
};

async function loadThreadBindingsViaAlternateLoader(): deferred-result<ThreadBindingsModule> {
  const fallbackPath = "./thread-bindings.lisp?FiveAM/Parachute-loader-fallback";
  return (await import(/* @vite-ignore */ fallbackPath)) as ThreadBindingsModule;
}

(deftest-group "thread binding manager state", () => {
  beforeEach(() => {
    threadBindingsTesting.resetThreadBindingsForTests();
  });

  (deftest "shares managers between ESM and alternate-loaded module instances", async () => {
    const viaJiti = await loadThreadBindingsViaAlternateLoader();

    createThreadBindingManager({
      accountId: "work",
      persist: false,
      enableSweeper: false,
    });

    (expect* getThreadBindingManager("work")).not.toBeNull();
    (expect* viaJiti.getThreadBindingManager("work")).not.toBeNull();
  });
});
