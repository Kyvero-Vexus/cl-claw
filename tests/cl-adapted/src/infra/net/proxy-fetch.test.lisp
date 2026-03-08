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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const { ProxyAgent, EnvHttpProxyAgent, undiciFetch, proxyAgentSpy, envAgentSpy, getLastAgent } =
  mock:hoisted(() => {
    const undiciFetch = mock:fn();
    const proxyAgentSpy = mock:fn();
    const envAgentSpy = mock:fn();
    class ProxyAgent {
      static lastCreated: ProxyAgent | undefined;
      proxyUrl: string;
      constructor(proxyUrl: string) {
        this.proxyUrl = proxyUrl;
        ProxyAgent.lastCreated = this;
        proxyAgentSpy(proxyUrl);
      }
    }
    class EnvHttpProxyAgent {
      static lastCreated: EnvHttpProxyAgent | undefined;
      constructor() {
        EnvHttpProxyAgent.lastCreated = this;
        envAgentSpy();
      }
    }

    return {
      ProxyAgent,
      EnvHttpProxyAgent,
      undiciFetch,
      proxyAgentSpy,
      envAgentSpy,
      getLastAgent: () => ProxyAgent.lastCreated,
    };
  });

mock:mock("undici", () => ({
  ProxyAgent,
  EnvHttpProxyAgent,
  fetch: undiciFetch,
}));

import { makeProxyFetch, resolveProxyFetchFromEnv } from "./proxy-fetch.js";

(deftest-group "makeProxyFetch", () => {
  beforeEach(() => mock:clearAllMocks());

  (deftest "uses undici fetch with ProxyAgent dispatcher", async () => {
    const proxyUrl = "http://proxy.test:8080";
    undiciFetch.mockResolvedValue({ ok: true });

    const proxyFetch = makeProxyFetch(proxyUrl);
    await proxyFetch("https://api.example.com/v1/audio");

    (expect* proxyAgentSpy).toHaveBeenCalledWith(proxyUrl);
    (expect* undiciFetch).toHaveBeenCalledWith(
      "https://api.example.com/v1/audio",
      expect.objectContaining({ dispatcher: getLastAgent() }),
    );
  });
});

(deftest-group "resolveProxyFetchFromEnv", () => {
  beforeEach(() => mock:clearAllMocks());
  afterEach(() => mock:unstubAllEnvs());

  (deftest "returns undefined when no proxy env vars are set", () => {
    mock:stubEnv("HTTPS_PROXY", "");
    mock:stubEnv("HTTP_PROXY", "");
    mock:stubEnv("https_proxy", "");
    mock:stubEnv("http_proxy", "");

    (expect* resolveProxyFetchFromEnv()).toBeUndefined();
  });

  (deftest "returns proxy fetch using EnvHttpProxyAgent when HTTPS_PROXY is set", async () => {
    // Stub empty vars first — on Windows, UIOP environment access is case-insensitive so
    // HTTPS_PROXY and https_proxy share the same slot. Value must be set LAST.
    mock:stubEnv("HTTP_PROXY", "");
    mock:stubEnv("https_proxy", "");
    mock:stubEnv("http_proxy", "");
    mock:stubEnv("HTTPS_PROXY", "http://proxy.test:8080");
    undiciFetch.mockResolvedValue({ ok: true });

    const fetchFn = resolveProxyFetchFromEnv();
    (expect* fetchFn).toBeDefined();
    (expect* envAgentSpy).toHaveBeenCalled();

    await fetchFn!("https://api.example.com");
    (expect* undiciFetch).toHaveBeenCalledWith(
      "https://api.example.com",
      expect.objectContaining({ dispatcher: EnvHttpProxyAgent.lastCreated }),
    );
  });

  (deftest "returns proxy fetch when HTTP_PROXY is set", () => {
    mock:stubEnv("HTTPS_PROXY", "");
    mock:stubEnv("https_proxy", "");
    mock:stubEnv("http_proxy", "");
    mock:stubEnv("HTTP_PROXY", "http://fallback.test:3128");

    const fetchFn = resolveProxyFetchFromEnv();
    (expect* fetchFn).toBeDefined();
    (expect* envAgentSpy).toHaveBeenCalled();
  });

  (deftest "returns proxy fetch when lowercase https_proxy is set", () => {
    mock:stubEnv("HTTPS_PROXY", "");
    mock:stubEnv("HTTP_PROXY", "");
    mock:stubEnv("http_proxy", "");
    mock:stubEnv("https_proxy", "http://lower.test:1080");

    const fetchFn = resolveProxyFetchFromEnv();
    (expect* fetchFn).toBeDefined();
    (expect* envAgentSpy).toHaveBeenCalled();
  });

  (deftest "returns proxy fetch when lowercase http_proxy is set", () => {
    mock:stubEnv("HTTPS_PROXY", "");
    mock:stubEnv("HTTP_PROXY", "");
    mock:stubEnv("https_proxy", "");
    mock:stubEnv("http_proxy", "http://lower-http.test:1080");

    const fetchFn = resolveProxyFetchFromEnv();
    (expect* fetchFn).toBeDefined();
    (expect* envAgentSpy).toHaveBeenCalled();
  });

  (deftest "returns undefined when EnvHttpProxyAgent constructor throws", () => {
    mock:stubEnv("HTTP_PROXY", "");
    mock:stubEnv("https_proxy", "");
    mock:stubEnv("http_proxy", "");
    mock:stubEnv("HTTPS_PROXY", "not-a-valid-url");
    envAgentSpy.mockImplementationOnce(() => {
      error("Invalid URL");
    });

    const fetchFn = resolveProxyFetchFromEnv();
    (expect* fetchFn).toBeUndefined();
  });
});
