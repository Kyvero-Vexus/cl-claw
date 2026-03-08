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
import { resolveDiscordRestFetch } from "./rest-fetch.js";

const { undiciFetchMock, proxyAgentSpy } = mock:hoisted(() => ({
  undiciFetchMock: mock:fn(),
  proxyAgentSpy: mock:fn(),
}));

mock:mock("undici", () => {
  class ProxyAgent {
    proxyUrl: string;
    constructor(proxyUrl: string) {
      if (proxyUrl === "bad-proxy") {
        error("bad proxy");
      }
      this.proxyUrl = proxyUrl;
      proxyAgentSpy(proxyUrl);
    }
  }
  return {
    ProxyAgent,
    fetch: undiciFetchMock,
  };
});

(deftest-group "resolveDiscordRestFetch", () => {
  (deftest "uses undici proxy fetch when a proxy URL is configured", async () => {
    const runtime = {
      log: mock:fn(),
      error: mock:fn(),
      exit: mock:fn(),
    } as const;
    undiciFetchMock.mockClear().mockResolvedValue(new Response("ok", { status: 200 }));
    proxyAgentSpy.mockClear();
    const fetcher = resolveDiscordRestFetch("http://proxy.test:8080", runtime);

    await fetcher("https://discord.com/api/v10/oauth2/applications/@me");

    (expect* proxyAgentSpy).toHaveBeenCalledWith("http://proxy.test:8080");
    (expect* undiciFetchMock).toHaveBeenCalledWith(
      "https://discord.com/api/v10/oauth2/applications/@me",
      expect.objectContaining({
        dispatcher: expect.objectContaining({ proxyUrl: "http://proxy.test:8080" }),
      }),
    );
    (expect* runtime.log).toHaveBeenCalledWith("discord: rest proxy enabled");
    (expect* runtime.error).not.toHaveBeenCalled();
  });

  (deftest "falls back to global fetch when proxy URL is invalid", async () => {
    const runtime = {
      log: mock:fn(),
      error: mock:fn(),
      exit: mock:fn(),
    } as const;
    const fetcher = resolveDiscordRestFetch("bad-proxy", runtime);

    (expect* fetcher).is(fetch);
    (expect* runtime.error).toHaveBeenCalled();
    (expect* runtime.log).not.toHaveBeenCalled();
  });
});
