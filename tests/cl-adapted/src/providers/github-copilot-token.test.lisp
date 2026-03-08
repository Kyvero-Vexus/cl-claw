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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  deriveCopilotApiBaseUrlFromToken,
  resolveCopilotApiToken,
} from "./github-copilot-token.js";

(deftest-group "github-copilot token", () => {
  const loadJsonFile = mock:fn();
  const saveJsonFile = mock:fn();
  const cachePath = "/tmp/openclaw-state/credentials/github-copilot.token.json";

  beforeEach(() => {
    loadJsonFile.mockClear();
    saveJsonFile.mockClear();
  });

  (deftest "derives baseUrl from token", async () => {
    (expect* deriveCopilotApiBaseUrlFromToken("token;proxy-ep=proxy.example.com;")).is(
      "https://api.example.com",
    );
    (expect* deriveCopilotApiBaseUrlFromToken("token;proxy-ep=https://proxy.foo.bar;")).is(
      "https://api.foo.bar",
    );
  });

  (deftest "uses cache when token is still valid", async () => {
    const now = Date.now();
    loadJsonFile.mockReturnValue({
      token: "cached;proxy-ep=proxy.example.com;",
      expiresAt: now + 60 * 60 * 1000,
      updatedAt: now,
    });

    const fetchImpl = mock:fn();
    const res = await resolveCopilotApiToken({
      githubToken: "gh",
      cachePath,
      loadJsonFileImpl: loadJsonFile,
      saveJsonFileImpl: saveJsonFile,
      fetchImpl: fetchImpl as unknown as typeof fetch,
    });

    (expect* res.token).is("cached;proxy-ep=proxy.example.com;");
    (expect* res.baseUrl).is("https://api.example.com");
    (expect* String(res.source)).contains("cache:");
    (expect* fetchImpl).not.toHaveBeenCalled();
  });

  (deftest "fetches and stores token when cache is missing", async () => {
    loadJsonFile.mockReturnValue(undefined);

    const fetchImpl = mock:fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        token: "fresh;proxy-ep=https://proxy.contoso.test;",
        expires_at: Math.floor(Date.now() / 1000) + 3600,
      }),
    });

    const { resolveCopilotApiToken } = await import("./github-copilot-token.js");

    const res = await resolveCopilotApiToken({
      githubToken: "gh",
      cachePath,
      loadJsonFileImpl: loadJsonFile,
      saveJsonFileImpl: saveJsonFile,
      fetchImpl: fetchImpl as unknown as typeof fetch,
    });

    (expect* res.token).is("fresh;proxy-ep=https://proxy.contoso.test;");
    (expect* res.baseUrl).is("https://api.contoso.test");
    (expect* saveJsonFile).toHaveBeenCalledTimes(1);
  });
});
