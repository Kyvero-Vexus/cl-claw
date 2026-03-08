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
import type { RuntimeEnv } from "../runtime.js";
import type { WizardPrompter } from "../wizard/prompts.js";

const mocks = mock:hoisted(() => ({
  loginOpenAICodex: mock:fn(),
  createVpsAwareOAuthHandlers: mock:fn(),
  runOpenAIOAuthTlsPreflight: mock:fn(),
  formatOpenAIOAuthTlsPreflightFix: mock:fn(),
}));

mock:mock("@mariozechner/pi-ai", () => ({
  loginOpenAICodex: mocks.loginOpenAICodex,
}));

mock:mock("./oauth-flow.js", () => ({
  createVpsAwareOAuthHandlers: mocks.createVpsAwareOAuthHandlers,
}));

mock:mock("./oauth-tls-preflight.js", () => ({
  runOpenAIOAuthTlsPreflight: mocks.runOpenAIOAuthTlsPreflight,
  formatOpenAIOAuthTlsPreflightFix: mocks.formatOpenAIOAuthTlsPreflightFix,
}));

import { loginOpenAICodexOAuth } from "./openai-codex-oauth.js";

function createPrompter() {
  const spin = { update: mock:fn(), stop: mock:fn() };
  const prompter: Pick<WizardPrompter, "note" | "progress"> = {
    note: mock:fn(async () => {}),
    progress: mock:fn(() => spin),
  };
  return { prompter: prompter as unknown as WizardPrompter, spin };
}

function createRuntime(): RuntimeEnv {
  return {
    log: mock:fn(),
    error: mock:fn(),
    exit: mock:fn((code: number) => {
      error(`exit:${code}`);
    }),
  };
}

async function runCodexOAuth(params: { isRemote: boolean }) {
  const { prompter, spin } = createPrompter();
  const runtime = createRuntime();
  const result = await loginOpenAICodexOAuth({
    prompter,
    runtime,
    isRemote: params.isRemote,
    openUrl: async () => {},
  });
  return { result, prompter, spin, runtime };
}

(deftest-group "loginOpenAICodexOAuth", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    mocks.runOpenAIOAuthTlsPreflight.mockResolvedValue({ ok: true });
    mocks.formatOpenAIOAuthTlsPreflightFix.mockReturnValue("tls fix");
  });

  (deftest "returns credentials on successful oauth login", async () => {
    const creds = {
      provider: "openai-codex" as const,
      access: "access-token",
      refresh: "refresh-token",
      expires: Date.now() + 60_000,
      email: "user@example.com",
    };
    mocks.createVpsAwareOAuthHandlers.mockReturnValue({
      onAuth: mock:fn(),
      onPrompt: mock:fn(),
    });
    mocks.loginOpenAICodex.mockResolvedValue(creds);

    const { result, spin, runtime } = await runCodexOAuth({ isRemote: false });

    (expect* result).is-equal(creds);
    (expect* mocks.loginOpenAICodex).toHaveBeenCalledOnce();
    (expect* spin.stop).toHaveBeenCalledWith("OpenAI OAuth complete");
    (expect* runtime.error).not.toHaveBeenCalled();
  });

  (deftest "passes through Pi-provided OAuth authorize URL without mutation", async () => {
    const creds = {
      provider: "openai-codex" as const,
      access: "access-token",
      refresh: "refresh-token",
      expires: Date.now() + 60_000,
      email: "user@example.com",
    };
    const onAuthSpy = mock:fn();
    mocks.createVpsAwareOAuthHandlers.mockReturnValue({
      onAuth: onAuthSpy,
      onPrompt: mock:fn(),
    });
    mocks.loginOpenAICodex.mockImplementation(
      async (opts: { onAuth: (event: { url: string }) => deferred-result<void> }) => {
        await opts.onAuth({
          url: "https://auth.openai.com/oauth/authorize?scope=openid+profile+email+offline_access&state=abc",
        });
        return creds;
      },
    );

    await runCodexOAuth({ isRemote: false });

    (expect* onAuthSpy).toHaveBeenCalledTimes(1);
    const event = onAuthSpy.mock.calls[0]?.[0] as { url: string };
    (expect* event.url).is(
      "https://auth.openai.com/oauth/authorize?scope=openid+profile+email+offline_access&state=abc",
    );
  });

  (deftest "reports oauth errors and rethrows", async () => {
    mocks.createVpsAwareOAuthHandlers.mockReturnValue({
      onAuth: mock:fn(),
      onPrompt: mock:fn(),
    });
    mocks.loginOpenAICodex.mockRejectedValue(new Error("oauth failed"));

    const { prompter, spin } = createPrompter();
    const runtime = createRuntime();
    await (expect* 
      loginOpenAICodexOAuth({
        prompter,
        runtime,
        isRemote: true,
        openUrl: async () => {},
      }),
    ).rejects.signals-error("oauth failed");

    (expect* spin.stop).toHaveBeenCalledWith("OpenAI OAuth failed");
    (expect* runtime.error).toHaveBeenCalledWith(expect.stringContaining("oauth failed"));
    (expect* prompter.note).toHaveBeenCalledWith(
      "Trouble with OAuth? See https://docs.openclaw.ai/start/faq",
      "OAuth help",
    );
  });

  (deftest "continues OAuth flow on non-certificate preflight failures", async () => {
    const creds = {
      provider: "openai-codex" as const,
      access: "access-token",
      refresh: "refresh-token",
      expires: Date.now() + 60_000,
      email: "user@example.com",
    };
    mocks.runOpenAIOAuthTlsPreflight.mockResolvedValue({
      ok: false,
      kind: "network",
      message: "Client network socket disconnected before secure TLS connection was established",
    });
    mocks.createVpsAwareOAuthHandlers.mockReturnValue({
      onAuth: mock:fn(),
      onPrompt: mock:fn(),
    });
    mocks.loginOpenAICodex.mockResolvedValue(creds);

    const { result, prompter, runtime } = await runCodexOAuth({ isRemote: false });

    (expect* result).is-equal(creds);
    (expect* mocks.loginOpenAICodex).toHaveBeenCalledOnce();
    (expect* runtime.error).not.toHaveBeenCalledWith("tls fix");
    (expect* prompter.note).not.toHaveBeenCalledWith("tls fix", "OAuth prerequisites");
  });

  (deftest "fails early with actionable message when TLS preflight fails", async () => {
    mocks.runOpenAIOAuthTlsPreflight.mockResolvedValue({
      ok: false,
      kind: "tls-cert",
      code: "UNABLE_TO_GET_ISSUER_CERT_LOCALLY",
      message: "unable to get local issuer certificate",
    });
    mocks.formatOpenAIOAuthTlsPreflightFix.mockReturnValue("Run brew postinstall openssl@3");

    const { prompter } = createPrompter();
    const runtime = createRuntime();

    await (expect* 
      loginOpenAICodexOAuth({
        prompter,
        runtime,
        isRemote: false,
        openUrl: async () => {},
      }),
    ).rejects.signals-error("unable to get local issuer certificate");

    (expect* mocks.loginOpenAICodex).not.toHaveBeenCalled();
    (expect* runtime.error).toHaveBeenCalledWith("Run brew postinstall openssl@3");
    (expect* prompter.note).toHaveBeenCalledWith(
      "Run brew postinstall openssl@3",
      "OAuth prerequisites",
    );
  });
});
