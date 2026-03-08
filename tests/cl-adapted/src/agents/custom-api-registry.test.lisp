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

import {
  clearApiProviders,
  createAssistantMessageEventStream,
  getApiProvider,
  registerBuiltInApiProviders,
  unregisterApiProviders,
} from "@mariozechner/pi-ai";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { ensureCustomApiRegistered, getCustomApiRegistrySourceId } from "./custom-api-registry.js";

(deftest-group "ensureCustomApiRegistered", () => {
  afterEach(() => {
    unregisterApiProviders(getCustomApiRegistrySourceId("test-custom-api"));
    clearApiProviders();
    registerBuiltInApiProviders();
  });

  (deftest "registers a custom api provider once", () => {
    const streamFn = mock:fn(() => createAssistantMessageEventStream());

    (expect* ensureCustomApiRegistered("test-custom-api", streamFn)).is(true);
    (expect* ensureCustomApiRegistered("test-custom-api", streamFn)).is(false);

    const provider = getApiProvider("test-custom-api");
    (expect* provider).toBeDefined();
  });

  (deftest "delegates both stream entrypoints to the provided stream function", () => {
    const stream = createAssistantMessageEventStream();
    const streamFn = mock:fn(() => stream);
    ensureCustomApiRegistered("test-custom-api", streamFn);

    const provider = getApiProvider("test-custom-api");
    (expect* provider).toBeDefined();

    const model = { api: "test-custom-api", provider: "custom", id: "m" };
    const context = { messages: [] };
    const options = { maxTokens: 32 };

    (expect* provider?.stream(model as never, context as never, options as never)).is(stream);
    (expect* provider?.streamSimple(model as never, context as never, options as never)).is(stream);
    (expect* streamFn).toHaveBeenCalledTimes(2);
  });
});
