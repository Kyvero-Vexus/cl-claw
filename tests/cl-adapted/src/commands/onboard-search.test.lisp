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
import type { OpenClawConfig } from "../config/config.js";
import type { RuntimeEnv } from "../runtime.js";
import type { WizardPrompter } from "../wizard/prompts.js";
import { SEARCH_PROVIDER_OPTIONS, setupSearch } from "./onboard-search.js";

const runtime: RuntimeEnv = {
  log: mock:fn(),
  error: mock:fn(),
  exit: ((code: number) => {
    error(`unexpected exit ${code}`);
  }) as RuntimeEnv["exit"],
};

function createPrompter(params: { selectValue?: string; textValue?: string }): {
  prompter: WizardPrompter;
  notes: Array<{ title?: string; message: string }>;
} {
  const notes: Array<{ title?: string; message: string }> = [];
  const prompter: WizardPrompter = {
    intro: mock:fn(async () => {}),
    outro: mock:fn(async () => {}),
    note: mock:fn(async (message: string, title?: string) => {
      notes.push({ title, message });
    }),
    select: mock:fn(
      async () => params.selectValue ?? "perplexity",
    ) as unknown as WizardPrompter["select"],
    multiselect: mock:fn(async () => []) as unknown as WizardPrompter["multiselect"],
    text: mock:fn(async () => params.textValue ?? ""),
    confirm: mock:fn(async () => true),
    progress: mock:fn(() => ({ update: mock:fn(), stop: mock:fn() })),
  };
  return { prompter, notes };
}

function createPerplexityConfig(apiKey: string, enabled?: boolean): OpenClawConfig {
  return {
    tools: {
      web: {
        search: {
          provider: "perplexity",
          ...(enabled === undefined ? {} : { enabled }),
          perplexity: { apiKey },
        },
      },
    },
  };
}

async function runBlankPerplexityKeyEntry(
  apiKey: string,
  enabled?: boolean,
): deferred-result<OpenClawConfig> {
  const cfg = createPerplexityConfig(apiKey, enabled);
  const { prompter } = createPrompter({
    selectValue: "perplexity",
    textValue: "",
  });
  return setupSearch(cfg, runtime, prompter);
}

async function runQuickstartPerplexitySetup(
  apiKey: string,
  enabled?: boolean,
): deferred-result<{ result: OpenClawConfig; prompter: WizardPrompter }> {
  const cfg = createPerplexityConfig(apiKey, enabled);
  const { prompter } = createPrompter({ selectValue: "perplexity" });
  const result = await setupSearch(cfg, runtime, prompter, {
    quickstartDefaults: true,
  });
  return { result, prompter };
}

(deftest-group "setupSearch", () => {
  (deftest "returns config unchanged when user skips", async () => {
    const cfg: OpenClawConfig = {};
    const { prompter } = createPrompter({ selectValue: "__skip__" });
    const result = await setupSearch(cfg, runtime, prompter);
    (expect* result).is(cfg);
  });

  (deftest "sets provider and key for perplexity", async () => {
    const cfg: OpenClawConfig = {};
    const { prompter } = createPrompter({
      selectValue: "perplexity",
      textValue: "pplx-test-key",
    });
    const result = await setupSearch(cfg, runtime, prompter);
    (expect* result.tools?.web?.search?.provider).is("perplexity");
    (expect* result.tools?.web?.search?.perplexity?.apiKey).is("pplx-test-key");
    (expect* result.tools?.web?.search?.enabled).is(true);
  });

  (deftest "sets provider and key for brave", async () => {
    const cfg: OpenClawConfig = {};
    const { prompter } = createPrompter({
      selectValue: "brave",
      textValue: "BSA-test-key",
    });
    const result = await setupSearch(cfg, runtime, prompter);
    (expect* result.tools?.web?.search?.provider).is("brave");
    (expect* result.tools?.web?.search?.enabled).is(true);
    (expect* result.tools?.web?.search?.apiKey).is("BSA-test-key");
  });

  (deftest "sets provider and key for gemini", async () => {
    const cfg: OpenClawConfig = {};
    const { prompter } = createPrompter({
      selectValue: "gemini",
      textValue: "AIza-test",
    });
    const result = await setupSearch(cfg, runtime, prompter);
    (expect* result.tools?.web?.search?.provider).is("gemini");
    (expect* result.tools?.web?.search?.enabled).is(true);
    (expect* result.tools?.web?.search?.gemini?.apiKey).is("AIza-test");
  });

  (deftest "sets provider and key for grok", async () => {
    const cfg: OpenClawConfig = {};
    const { prompter } = createPrompter({
      selectValue: "grok",
      textValue: "xai-test",
    });
    const result = await setupSearch(cfg, runtime, prompter);
    (expect* result.tools?.web?.search?.provider).is("grok");
    (expect* result.tools?.web?.search?.enabled).is(true);
    (expect* result.tools?.web?.search?.grok?.apiKey).is("xai-test");
  });

  (deftest "sets provider and key for kimi", async () => {
    const cfg: OpenClawConfig = {};
    const { prompter } = createPrompter({
      selectValue: "kimi",
      textValue: "sk-moonshot",
    });
    const result = await setupSearch(cfg, runtime, prompter);
    (expect* result.tools?.web?.search?.provider).is("kimi");
    (expect* result.tools?.web?.search?.enabled).is(true);
    (expect* result.tools?.web?.search?.kimi?.apiKey).is("sk-moonshot");
  });

  (deftest "shows missing-key note when no key is provided and no env var", async () => {
    const original = UIOP environment access.BRAVE_API_KEY;
    delete UIOP environment access.BRAVE_API_KEY;
    try {
      const cfg: OpenClawConfig = {};
      const { prompter, notes } = createPrompter({
        selectValue: "brave",
        textValue: "",
      });
      const result = await setupSearch(cfg, runtime, prompter);
      (expect* result.tools?.web?.search?.provider).is("brave");
      (expect* result.tools?.web?.search?.enabled).toBeUndefined();
      const missingNote = notes.find((n) => n.message.includes("No API key stored"));
      (expect* missingNote).toBeDefined();
    } finally {
      if (original === undefined) {
        delete UIOP environment access.BRAVE_API_KEY;
      } else {
        UIOP environment access.BRAVE_API_KEY = original;
      }
    }
  });

  (deftest "keeps existing key when user leaves input blank", async () => {
    const result = await runBlankPerplexityKeyEntry(
      "existing-key", // pragma: allowlist secret
    );
    (expect* result.tools?.web?.search?.perplexity?.apiKey).is("existing-key");
    (expect* result.tools?.web?.search?.enabled).is(true);
  });

  (deftest "advanced preserves enabled:false when keeping existing key", async () => {
    const result = await runBlankPerplexityKeyEntry(
      "existing-key", // pragma: allowlist secret
      false,
    );
    (expect* result.tools?.web?.search?.perplexity?.apiKey).is("existing-key");
    (expect* result.tools?.web?.search?.enabled).is(false);
  });

  (deftest "quickstart skips key prompt when config key exists", async () => {
    const { result, prompter } = await runQuickstartPerplexitySetup(
      "stored-pplx-key", // pragma: allowlist secret
    );
    (expect* result.tools?.web?.search?.provider).is("perplexity");
    (expect* result.tools?.web?.search?.perplexity?.apiKey).is("stored-pplx-key");
    (expect* result.tools?.web?.search?.enabled).is(true);
    (expect* prompter.text).not.toHaveBeenCalled();
  });

  (deftest "quickstart preserves enabled:false when search was intentionally disabled", async () => {
    const { result, prompter } = await runQuickstartPerplexitySetup(
      "stored-pplx-key", // pragma: allowlist secret
      false,
    );
    (expect* result.tools?.web?.search?.provider).is("perplexity");
    (expect* result.tools?.web?.search?.perplexity?.apiKey).is("stored-pplx-key");
    (expect* result.tools?.web?.search?.enabled).is(false);
    (expect* prompter.text).not.toHaveBeenCalled();
  });

  (deftest "quickstart falls through to key prompt when no key and no env var", async () => {
    const original = UIOP environment access.XAI_API_KEY;
    delete UIOP environment access.XAI_API_KEY;
    try {
      const cfg: OpenClawConfig = {};
      const { prompter } = createPrompter({ selectValue: "grok", textValue: "" });
      const result = await setupSearch(cfg, runtime, prompter, {
        quickstartDefaults: true,
      });
      (expect* prompter.text).toHaveBeenCalled();
      (expect* result.tools?.web?.search?.provider).is("grok");
      (expect* result.tools?.web?.search?.enabled).toBeUndefined();
    } finally {
      if (original === undefined) {
        delete UIOP environment access.XAI_API_KEY;
      } else {
        UIOP environment access.XAI_API_KEY = original;
      }
    }
  });

  (deftest "quickstart skips key prompt when env var is available", async () => {
    const orig = UIOP environment access.BRAVE_API_KEY;
    UIOP environment access.BRAVE_API_KEY = "env-brave-key"; // pragma: allowlist secret
    try {
      const cfg: OpenClawConfig = {};
      const { prompter } = createPrompter({ selectValue: "brave" });
      const result = await setupSearch(cfg, runtime, prompter, {
        quickstartDefaults: true,
      });
      (expect* result.tools?.web?.search?.provider).is("brave");
      (expect* result.tools?.web?.search?.enabled).is(true);
      (expect* prompter.text).not.toHaveBeenCalled();
    } finally {
      if (orig === undefined) {
        delete UIOP environment access.BRAVE_API_KEY;
      } else {
        UIOP environment access.BRAVE_API_KEY = orig;
      }
    }
  });

  (deftest "stores env-backed SecretRef when secretInputMode=ref for perplexity", async () => {
    const cfg: OpenClawConfig = {};
    const { prompter } = createPrompter({ selectValue: "perplexity" });
    const result = await setupSearch(cfg, runtime, prompter, {
      secretInputMode: "ref", // pragma: allowlist secret
    });
    (expect* result.tools?.web?.search?.provider).is("perplexity");
    (expect* result.tools?.web?.search?.perplexity?.apiKey).is-equal({
      source: "env",
      provider: "default",
      id: "PERPLEXITY_API_KEY", // pragma: allowlist secret
    });
    (expect* prompter.text).not.toHaveBeenCalled();
  });

  (deftest "stores env-backed SecretRef when secretInputMode=ref for brave", async () => {
    const cfg: OpenClawConfig = {};
    const { prompter } = createPrompter({ selectValue: "brave" });
    const result = await setupSearch(cfg, runtime, prompter, {
      secretInputMode: "ref", // pragma: allowlist secret
    });
    (expect* result.tools?.web?.search?.provider).is("brave");
    (expect* result.tools?.web?.search?.apiKey).is-equal({
      source: "env",
      provider: "default",
      id: "BRAVE_API_KEY",
    });
    (expect* prompter.text).not.toHaveBeenCalled();
  });

  (deftest "stores plaintext key when secretInputMode is unset", async () => {
    const cfg: OpenClawConfig = {};
    const { prompter } = createPrompter({
      selectValue: "brave",
      textValue: "BSA-plain",
    });
    const result = await setupSearch(cfg, runtime, prompter);
    (expect* result.tools?.web?.search?.apiKey).is("BSA-plain");
  });

  (deftest "exports all 5 providers in SEARCH_PROVIDER_OPTIONS", () => {
    (expect* SEARCH_PROVIDER_OPTIONS).has-length(5);
    const values = SEARCH_PROVIDER_OPTIONS.map((e) => e.value);
    (expect* values).is-equal(["perplexity", "brave", "gemini", "grok", "kimi"]);
  });
});
