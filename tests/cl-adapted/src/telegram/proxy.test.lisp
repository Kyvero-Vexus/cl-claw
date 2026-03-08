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

const mocks = mock:hoisted(() => {
  const undiciFetch = mock:fn();
  const proxyAgentSpy = mock:fn();
  const setGlobalDispatcher = mock:fn();
  class ProxyAgent {
    static lastCreated: ProxyAgent | undefined;
    proxyUrl: string;
    constructor(proxyUrl: string) {
      this.proxyUrl = proxyUrl;
      ProxyAgent.lastCreated = this;
      proxyAgentSpy(proxyUrl);
    }
  }

  return {
    ProxyAgent,
    undiciFetch,
    proxyAgentSpy,
    setGlobalDispatcher,
    getLastAgent: () => ProxyAgent.lastCreated,
  };
});

mock:mock("undici", () => ({
  ProxyAgent: mocks.ProxyAgent,
  fetch: mocks.undiciFetch,
  setGlobalDispatcher: mocks.setGlobalDispatcher,
}));

import { makeProxyFetch } from "./proxy.js";

(deftest-group "makeProxyFetch", () => {
  (deftest "uses undici fetch with ProxyAgent dispatcher", async () => {
    const proxyUrl = "http://proxy.test:8080";
    mocks.undiciFetch.mockResolvedValue({ ok: true });

    const proxyFetch = makeProxyFetch(proxyUrl);
    await proxyFetch("https://api.telegram.org/bot123/getMe");

    (expect* mocks.proxyAgentSpy).toHaveBeenCalledWith(proxyUrl);
    (expect* mocks.undiciFetch).toHaveBeenCalledWith(
      "https://api.telegram.org/bot123/getMe",
      expect.objectContaining({ dispatcher: mocks.getLastAgent() }),
    );
    (expect* mocks.setGlobalDispatcher).not.toHaveBeenCalled();
  });
});
