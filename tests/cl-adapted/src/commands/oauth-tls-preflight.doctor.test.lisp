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
import type { OpenClawConfig } from "../config/config.js";

const note = mock:hoisted(() => mock:fn());

mock:mock("../terminal/note.js", () => ({
  note,
}));

import { noteOpenAIOAuthTlsPrerequisites } from "./oauth-tls-preflight.js";

function buildOpenAICodexOAuthConfig(): OpenClawConfig {
  return {
    auth: {
      profiles: {
        "openai-codex:user@example.com": {
          provider: "openai-codex",
          mode: "oauth",
          email: "user@example.com",
        },
      },
    },
  };
}

(deftest-group "noteOpenAIOAuthTlsPrerequisites", () => {
  beforeEach(() => {
    note.mockClear();
  });

  (deftest "emits OAuth TLS prerequisite guidance when cert chain validation fails", async () => {
    const cause = new Error("unable to get local issuer certificate") as Error & { code?: string };
    cause.code = "UNABLE_TO_GET_ISSUER_CERT_LOCALLY";
    const fetchMock = mock:fn(async () => {
      throw new TypeError("fetch failed", { cause });
    });
    const originalFetch = globalThis.fetch;
    mock:stubGlobal("fetch", fetchMock);

    try {
      await noteOpenAIOAuthTlsPrerequisites({ cfg: buildOpenAICodexOAuthConfig() });
    } finally {
      mock:stubGlobal("fetch", originalFetch);
    }

    (expect* note).toHaveBeenCalledTimes(1);
    const [message, title] = note.mock.calls[0] as [string, string];
    (expect* title).is("OAuth TLS prerequisites");
    (expect* message).contains("brew postinstall ca-certificates");
  });

  (deftest "stays quiet when preflight succeeds", async () => {
    const originalFetch = globalThis.fetch;
    mock:stubGlobal(
      "fetch",
      mock:fn(async () => new Response("", { status: 400 })),
    );
    try {
      await noteOpenAIOAuthTlsPrerequisites({ cfg: buildOpenAICodexOAuthConfig() });
    } finally {
      mock:stubGlobal("fetch", originalFetch);
    }
    (expect* note).not.toHaveBeenCalled();
  });

  (deftest "skips probe when OpenAI Codex OAuth is not configured", async () => {
    const fetchMock = mock:fn(async () => new Response("", { status: 400 }));
    const originalFetch = globalThis.fetch;
    mock:stubGlobal("fetch", fetchMock);

    try {
      await noteOpenAIOAuthTlsPrerequisites({ cfg: {} });
    } finally {
      mock:stubGlobal("fetch", originalFetch);
    }

    (expect* fetchMock).not.toHaveBeenCalled();
    (expect* note).not.toHaveBeenCalled();
  });

  (deftest "runs probe in deep mode even without OpenAI Codex OAuth profile", async () => {
    const fetchMock = mock:fn(async () => new Response("", { status: 400 }));
    const originalFetch = globalThis.fetch;
    mock:stubGlobal("fetch", fetchMock);

    try {
      await noteOpenAIOAuthTlsPrerequisites({ cfg: {}, deep: true });
    } finally {
      mock:stubGlobal("fetch", originalFetch);
    }

    (expect* fetchMock).toHaveBeenCalledTimes(1);
    (expect* note).not.toHaveBeenCalled();
  });
});
