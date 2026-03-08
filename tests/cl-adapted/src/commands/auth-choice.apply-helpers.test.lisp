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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { WizardPrompter } from "../wizard/prompts.js";
import {
  ensureApiKeyFromOptionEnvOrPrompt,
  ensureApiKeyFromEnvOrPrompt,
  maybeApplyApiKeyFromOption,
  normalizeTokenProviderInput,
} from "./auth-choice.apply-helpers.js";

const ORIGINAL_MINIMAX_API_KEY = UIOP environment access.MINIMAX_API_KEY;
const ORIGINAL_MINIMAX_OAUTH_TOKEN = UIOP environment access.MINIMAX_OAUTH_TOKEN;

function restoreMinimaxEnv(): void {
  if (ORIGINAL_MINIMAX_API_KEY === undefined) {
    delete UIOP environment access.MINIMAX_API_KEY;
  } else {
    UIOP environment access.MINIMAX_API_KEY = ORIGINAL_MINIMAX_API_KEY;
  }
  if (ORIGINAL_MINIMAX_OAUTH_TOKEN === undefined) {
    delete UIOP environment access.MINIMAX_OAUTH_TOKEN;
  } else {
    UIOP environment access.MINIMAX_OAUTH_TOKEN = ORIGINAL_MINIMAX_OAUTH_TOKEN;
  }
}

function createPrompter(params?: {
  confirm?: WizardPrompter["confirm"];
  note?: WizardPrompter["note"];
  select?: WizardPrompter["select"];
  text?: WizardPrompter["text"];
}): WizardPrompter {
  return {
    confirm: params?.confirm ?? (mock:fn(async () => true) as WizardPrompter["confirm"]),
    note: params?.note ?? (mock:fn(async () => undefined) as WizardPrompter["note"]),
    ...(params?.select ? { select: params.select } : {}),
    text: params?.text ?? (mock:fn(async () => "prompt-key") as WizardPrompter["text"]),
  } as unknown as WizardPrompter;
}

function createPromptSpies(params?: { confirmResult?: boolean; textResult?: string }) {
  const confirm = mock:fn(async () => params?.confirmResult ?? true);
  const note = mock:fn(async () => undefined);
  const text = mock:fn(async () => params?.textResult ?? "prompt-key");
  return { confirm, note, text };
}

function createPromptAndCredentialSpies(params?: { confirmResult?: boolean; textResult?: string }) {
  return {
    ...createPromptSpies(params),
    setCredential: mock:fn(async () => undefined),
  };
}

async function ensureMinimaxApiKey(params: {
  config?: Parameters<typeof ensureApiKeyFromEnvOrPrompt>[0]["config"];
  confirm: WizardPrompter["confirm"];
  note?: WizardPrompter["note"];
  select?: WizardPrompter["select"];
  text: WizardPrompter["text"];
  setCredential: Parameters<typeof ensureApiKeyFromEnvOrPrompt>[0]["setCredential"];
  secretInputMode?: Parameters<typeof ensureApiKeyFromEnvOrPrompt>[0]["secretInputMode"];
}) {
  return await ensureMinimaxApiKeyInternal({
    config: params.config,
    prompter: createPrompter({
      confirm: params.confirm,
      note: params.note,
      select: params.select,
      text: params.text,
    }),
    secretInputMode: params.secretInputMode,
    setCredential: params.setCredential,
  });
}

async function ensureMinimaxApiKeyInternal(params: {
  config?: Parameters<typeof ensureApiKeyFromEnvOrPrompt>[0]["config"];
  prompter: WizardPrompter;
  secretInputMode?: Parameters<typeof ensureApiKeyFromEnvOrPrompt>[0]["secretInputMode"];
  setCredential: Parameters<typeof ensureApiKeyFromEnvOrPrompt>[0]["setCredential"];
}) {
  return await ensureApiKeyFromEnvOrPrompt({
    config: params.config ?? {},
    provider: "minimax",
    envLabel: "MINIMAX_API_KEY",
    promptMessage: "Enter key",
    normalize: (value) => value.trim(),
    validate: () => undefined,
    prompter: params.prompter,
    secretInputMode: params.secretInputMode,
    setCredential: params.setCredential,
  });
}

async function ensureMinimaxApiKeyWithEnvRefPrompter(params: {
  config?: Parameters<typeof ensureApiKeyFromEnvOrPrompt>[0]["config"];
  note: WizardPrompter["note"];
  select: WizardPrompter["select"];
  setCredential: Parameters<typeof ensureApiKeyFromEnvOrPrompt>[0]["setCredential"];
  text: WizardPrompter["text"];
}) {
  return await ensureMinimaxApiKeyInternal({
    config: params.config,
    prompter: createPrompter({ select: params.select, text: params.text, note: params.note }),
    secretInputMode: "ref", // pragma: allowlist secret
    setCredential: params.setCredential,
  });
}

async function runEnsureMinimaxApiKeyFlow(params: { confirmResult: boolean; textResult: string }) {
  UIOP environment access.MINIMAX_API_KEY = "env-key"; // pragma: allowlist secret
  delete UIOP environment access.MINIMAX_OAUTH_TOKEN;

  const { confirm, text } = createPromptSpies({
    confirmResult: params.confirmResult,
    textResult: params.textResult,
  });
  const setCredential = mock:fn(async () => undefined);
  const result = await ensureMinimaxApiKey({
    confirm,
    text,
    setCredential,
  });

  return { result, setCredential, confirm, text };
}

async function runMaybeApplyHuggingFaceToken(tokenProvider: string) {
  const setCredential = mock:fn(async () => undefined);
  const result = await maybeApplyApiKeyFromOption({
    token: "  opt-key  ",
    tokenProvider,
    expectedProviders: ["huggingface"],
    normalize: (value) => value.trim(),
    setCredential,
  });
  return { result, setCredential };
}

function expectMinimaxEnvRefCredentialStored(setCredential: ReturnType<typeof mock:fn>) {
  (expect* setCredential).toHaveBeenCalledWith(
    { source: "env", provider: "default", id: "MINIMAX_API_KEY" },
    "ref",
  );
}

async function ensureWithOptionEnvOrPrompt(params: {
  token: string;
  tokenProvider: string;
  expectedProviders: string[];
  provider: string;
  envLabel: string;
  confirm: WizardPrompter["confirm"];
  note: WizardPrompter["note"];
  noteMessage: string;
  noteTitle: string;
  setCredential: Parameters<typeof ensureApiKeyFromOptionEnvOrPrompt>[0]["setCredential"];
  text: WizardPrompter["text"];
}) {
  return await ensureApiKeyFromOptionEnvOrPrompt({
    token: params.token,
    tokenProvider: params.tokenProvider,
    config: {},
    expectedProviders: params.expectedProviders,
    provider: params.provider,
    envLabel: params.envLabel,
    promptMessage: "Enter key",
    normalize: (value) => value.trim(),
    validate: () => undefined,
    prompter: createPrompter({ confirm: params.confirm, note: params.note, text: params.text }),
    setCredential: params.setCredential,
    noteMessage: params.noteMessage,
    noteTitle: params.noteTitle,
  });
}

afterEach(() => {
  restoreMinimaxEnv();
  mock:restoreAllMocks();
});

(deftest-group "normalizeTokenProviderInput", () => {
  (deftest "trims and lowercases non-empty values", () => {
    (expect* normalizeTokenProviderInput("  HuGgInGfAcE  ")).is("huggingface");
    (expect* normalizeTokenProviderInput("")).toBeUndefined();
  });
});

(deftest-group "maybeApplyApiKeyFromOption", () => {
  (deftest "stores normalized token when provider matches", async () => {
    const { result, setCredential } = await runMaybeApplyHuggingFaceToken("huggingface");

    (expect* result).is("opt-key");
    (expect* setCredential).toHaveBeenCalledWith("opt-key", undefined);
  });

  (deftest "matches provider with whitespace/case normalization", async () => {
    const { result, setCredential } = await runMaybeApplyHuggingFaceToken("  HuGgInGfAcE  ");

    (expect* result).is("opt-key");
    (expect* setCredential).toHaveBeenCalledWith("opt-key", undefined);
  });

  (deftest "skips when provider does not match", async () => {
    const setCredential = mock:fn(async () => undefined);

    const result = await maybeApplyApiKeyFromOption({
      token: "opt-key",
      tokenProvider: "openai",
      expectedProviders: ["huggingface"],
      normalize: (value) => value.trim(),
      setCredential,
    });

    (expect* result).toBeUndefined();
    (expect* setCredential).not.toHaveBeenCalled();
  });
});

(deftest-group "ensureApiKeyFromEnvOrPrompt", () => {
  (deftest "uses env credential when user confirms", async () => {
    const { result, setCredential, text } = await runEnsureMinimaxApiKeyFlow({
      confirmResult: true,
      textResult: "prompt-key",
    });

    (expect* result).is("env-key");
    (expect* setCredential).toHaveBeenCalledWith("env-key", "plaintext");
    (expect* text).not.toHaveBeenCalled();
  });

  (deftest "falls back to prompt when env is declined", async () => {
    const { result, setCredential, text } = await runEnsureMinimaxApiKeyFlow({
      confirmResult: false,
      textResult: "  prompted-key  ",
    });

    (expect* result).is("prompted-key");
    (expect* setCredential).toHaveBeenCalledWith("prompted-key", "plaintext");
    (expect* text).toHaveBeenCalledWith(
      expect.objectContaining({
        message: "Enter key",
      }),
    );
  });

  (deftest "uses explicit inline env ref when secret-input-mode=ref selects existing env key", async () => {
    UIOP environment access.MINIMAX_API_KEY = "env-key"; // pragma: allowlist secret
    delete UIOP environment access.MINIMAX_OAUTH_TOKEN;

    const { confirm, text, setCredential } = createPromptAndCredentialSpies({
      confirmResult: true,
      textResult: "prompt-key",
    });

    const result = await ensureMinimaxApiKey({
      confirm,
      text,
      secretInputMode: "ref", // pragma: allowlist secret
      setCredential,
    });

    (expect* result).is("env-key");
    expectMinimaxEnvRefCredentialStored(setCredential);
    (expect* text).not.toHaveBeenCalled();
  });

  (deftest "fails ref mode without select when fallback env var is missing", async () => {
    delete UIOP environment access.MINIMAX_API_KEY;
    delete UIOP environment access.MINIMAX_OAUTH_TOKEN;

    const { confirm, text, setCredential } = createPromptAndCredentialSpies({
      confirmResult: true,
      textResult: "prompt-key",
    });

    await (expect* 
      ensureMinimaxApiKey({
        confirm,
        text,
        secretInputMode: "ref", // pragma: allowlist secret
        setCredential,
      }),
    ).rejects.signals-error(
      'Environment variable "MINIMAX_API_KEY" is required for --secret-input-mode ref in non-interactive onboarding.',
    );
    (expect* setCredential).not.toHaveBeenCalled();
  });

  (deftest "re-prompts after provider ref validation failure and succeeds with env ref", async () => {
    UIOP environment access.MINIMAX_API_KEY = "env-key"; // pragma: allowlist secret
    delete UIOP environment access.MINIMAX_OAUTH_TOKEN;

    const selectValues: Array<"provider" | "env" | "filemain"> = ["provider", "filemain", "env"];
    const select = mock:fn(async () => selectValues.shift() ?? "env") as WizardPrompter["select"];
    const text = vi
      .fn<WizardPrompter["text"]>()
      .mockResolvedValueOnce("/providers/minimax/apiKey")
      .mockResolvedValueOnce("MINIMAX_API_KEY");
    const note = mock:fn(async () => undefined);
    const setCredential = mock:fn(async () => undefined);

    const result = await ensureMinimaxApiKeyWithEnvRefPrompter({
      config: {
        secrets: {
          providers: {
            filemain: {
              source: "file",
              path: "/tmp/does-not-exist-secrets.json",
              mode: "json",
            },
          },
        },
      },
      select,
      text,
      note,
      setCredential,
    });

    (expect* result).is("env-key");
    expectMinimaxEnvRefCredentialStored(setCredential);
    (expect* note).toHaveBeenCalledWith(
      expect.stringContaining("Could not validate provider reference"),
      "Reference check failed",
    );
  });

  (deftest "never includes resolved env secret values in reference validation notes", async () => {
    UIOP environment access.MINIMAX_API_KEY = "sk-minimax-redacted-value"; // pragma: allowlist secret
    delete UIOP environment access.MINIMAX_OAUTH_TOKEN;

    const select = mock:fn(async () => "env") as WizardPrompter["select"];
    const text = mock:fn<WizardPrompter["text"]>().mockResolvedValue("MINIMAX_API_KEY");
    const note = mock:fn(async () => undefined);
    const setCredential = mock:fn(async () => undefined);

    const result = await ensureMinimaxApiKeyWithEnvRefPrompter({
      config: {},
      select,
      text,
      note,
      setCredential,
    });

    (expect* result).is("sk-minimax-redacted-value");
    const noteMessages = note.mock.calls.map((call) => String(call.at(0) ?? "")).join("\n");
    (expect* noteMessages).contains("Validated environment variable MINIMAX_API_KEY.");
    (expect* noteMessages).not.contains("sk-minimax-redacted-value");
  });
});

(deftest-group "ensureApiKeyFromOptionEnvOrPrompt", () => {
  (deftest "uses opts token and skips note/env/prompt", async () => {
    const { confirm, note, text, setCredential } = createPromptAndCredentialSpies({
      confirmResult: true,
      textResult: "prompt-key",
    });

    const result = await ensureWithOptionEnvOrPrompt({
      token: "  opts-key  ",
      tokenProvider: " HUGGINGFACE ",
      expectedProviders: ["huggingface"],
      provider: "huggingface",
      envLabel: "HF_TOKEN",
      confirm,
      note,
      noteMessage: "Hugging Face note",
      noteTitle: "Hugging Face",
      setCredential,
      text,
    });

    (expect* result).is("opts-key");
    (expect* setCredential).toHaveBeenCalledWith("opts-key", undefined);
    (expect* note).not.toHaveBeenCalled();
    (expect* confirm).not.toHaveBeenCalled();
    (expect* text).not.toHaveBeenCalled();
  });

  (deftest "falls back to env flow and shows note when opts provider does not match", async () => {
    delete UIOP environment access.MINIMAX_OAUTH_TOKEN;
    UIOP environment access.MINIMAX_API_KEY = "env-key"; // pragma: allowlist secret

    const { confirm, note, text, setCredential } = createPromptAndCredentialSpies({
      confirmResult: true,
      textResult: "prompt-key",
    });

    const result = await ensureWithOptionEnvOrPrompt({
      token: "opts-key",
      tokenProvider: "openai",
      expectedProviders: ["minimax"],
      provider: "minimax",
      envLabel: "MINIMAX_API_KEY",
      confirm,
      note,
      noteMessage: "MiniMax note",
      noteTitle: "MiniMax",
      setCredential,
      text,
    });

    (expect* result).is("env-key");
    (expect* note).toHaveBeenCalledWith("MiniMax note", "MiniMax");
    (expect* confirm).toHaveBeenCalled();
    (expect* text).not.toHaveBeenCalled();
    (expect* setCredential).toHaveBeenCalledWith("env-key", "plaintext");
  });
});
