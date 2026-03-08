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

import "./reply.directive.directive-behavior.e2e-mocks.js";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { loadSessionStore } from "../config/sessions.js";
import {
  assertModelSelection,
  installDirectiveBehaviorE2EHooks,
  loadModelCatalog,
  makeEmbeddedTextResult,
  makeWhatsAppDirectiveConfig,
  mockEmbeddedTextResult,
  replyText,
  replyTexts,
  runEmbeddedPiAgent,
  sessionStorePath,
  withTempHome,
} from "./reply.directive.directive-behavior.e2e-harness.js";
import { runModelDirectiveText } from "./reply.directive.directive-behavior.model-directive-test-utils.js";
import { getReplyFromConfig } from "./reply.js";

function makeDefaultModelConfig(home: string) {
  return makeWhatsAppDirectiveConfig(home, {
    model: { primary: "anthropic/claude-opus-4-5" },
    models: {
      "anthropic/claude-opus-4-5": {},
      "openai/gpt-4.1-mini": {},
    },
  });
}

async function runReplyToCurrentCase(home: string, text: string) {
  mock:mocked(runEmbeddedPiAgent).mockResolvedValue(makeEmbeddedTextResult(text));

  const res = await getReplyFromConfig(
    {
      Body: "ping",
      From: "+1004",
      To: "+2000",
      MessageSid: "msg-123",
    },
    {},
    makeWhatsAppDirectiveConfig(home, { model: "anthropic/claude-opus-4-5" }),
  );

  return Array.isArray(res) ? res[0] : res;
}

async function expectThinkStatusForReasoningModel(params: {
  home: string;
  reasoning: boolean;
  expectedLevel: "low" | "off";
}): deferred-result<void> {
  mock:mocked(loadModelCatalog).mockResolvedValueOnce([
    {
      id: "claude-opus-4-5",
      name: "Opus 4.5",
      provider: "anthropic",
      reasoning: params.reasoning,
    },
  ]);

  const res = await getReplyFromConfig(
    { Body: "/think", From: "+1222", To: "+1222", CommandAuthorized: true },
    {},
    makeWhatsAppDirectiveConfig(params.home, { model: "anthropic/claude-opus-4-5" }),
  );

  const text = replyText(res);
  (expect* text).contains(`Current thinking level: ${params.expectedLevel}`);
  (expect* text).contains("Options: off, minimal, low, medium, high, adaptive.");
}

function mockReasoningCapableCatalog() {
  mock:mocked(loadModelCatalog).mockResolvedValueOnce([
    {
      id: "claude-opus-4-5",
      name: "Opus 4.5",
      provider: "anthropic",
      reasoning: true,
    },
  ]);
}

async function runReasoningDefaultCase(params: {
  home: string;
  expectedThinkLevel: "low" | "off";
  expectedReasoningLevel: "off" | "on";
  thinkingDefault?: "off" | "low" | "medium" | "high";
}) {
  mock:mocked(runEmbeddedPiAgent).mockClear();
  mockEmbeddedTextResult("done");
  mockReasoningCapableCatalog();

  await getReplyFromConfig(
    {
      Body: "hello",
      From: "+1004",
      To: "+2000",
    },
    {},
    makeWhatsAppDirectiveConfig(params.home, {
      model: { primary: "anthropic/claude-opus-4-5" },
      ...(params.thinkingDefault ? { thinkingDefault: params.thinkingDefault } : {}),
    }),
  );

  (expect* runEmbeddedPiAgent).toHaveBeenCalledOnce();
  const call = mock:mocked(runEmbeddedPiAgent).mock.calls[0]?.[0];
  (expect* call?.thinkLevel).is(params.expectedThinkLevel);
  (expect* call?.reasoningLevel).is(params.expectedReasoningLevel);
}

(deftest-group "directive behavior", () => {
  installDirectiveBehaviorE2EHooks();

  (deftest "covers /think status and reasoning defaults for reasoning and non-reasoning models", async () => {
    await withTempHome(async (home) => {
      await expectThinkStatusForReasoningModel({
        home,
        reasoning: true,
        expectedLevel: "low",
      });
      await expectThinkStatusForReasoningModel({
        home,
        reasoning: false,
        expectedLevel: "off",
      });
      (expect* runEmbeddedPiAgent).not.toHaveBeenCalled();

      mock:mocked(runEmbeddedPiAgent).mockClear();

      for (const scenario of [
        {
          expectedThinkLevel: "low" as const,
          expectedReasoningLevel: "off" as const,
        },
        {
          expectedThinkLevel: "off" as const,
          expectedReasoningLevel: "on" as const,
          thinkingDefault: "off" as const,
        },
      ]) {
        await runReasoningDefaultCase({
          home,
          ...scenario,
        });
      }
    });
  });
  (deftest "renders model list and status variants across catalog/config combinations", async () => {
    await withTempHome(async (home) => {
      const aliasText = await runModelDirectiveText(home, "/model list");
      (expect* aliasText).contains("Providers:");
      (expect* aliasText).contains("- anthropic");
      (expect* aliasText).contains("- openai");
      (expect* aliasText).contains("Use: /models <provider>");
      (expect* aliasText).contains("Switch: /model <provider/model>");

      mock:mocked(loadModelCatalog).mockResolvedValueOnce([]);
      const unavailableCatalogText = await runModelDirectiveText(home, "/model");
      (expect* unavailableCatalogText).contains("Current: anthropic/claude-opus-4-5");
      (expect* unavailableCatalogText).contains("Switch: /model <provider/model>");
      (expect* unavailableCatalogText).contains(
        "Browse: /models (providers) or /models <provider> (models)",
      );
      (expect* unavailableCatalogText).contains("More: /model status");

      const allowlistedStatusText = await runModelDirectiveText(home, "/model status", {
        includeSessionStore: false,
      });
      (expect* allowlistedStatusText).contains("anthropic/claude-opus-4-5");
      (expect* allowlistedStatusText).contains("openai/gpt-4.1-mini");
      (expect* allowlistedStatusText).not.contains("claude-sonnet-4-1");
      (expect* allowlistedStatusText).contains("auth:");

      mock:mocked(loadModelCatalog).mockResolvedValue([
        { id: "claude-opus-4-5", name: "Opus 4.5", provider: "anthropic" },
        { id: "gpt-4.1-mini", name: "GPT-4.1 Mini", provider: "openai" },
        { id: "grok-4", name: "Grok 4", provider: "xai" },
      ]);
      const noAllowlistText = await runModelDirectiveText(home, "/model list", {
        defaults: {
          model: {
            primary: "anthropic/claude-opus-4-5",
            fallbacks: ["openai/gpt-4.1-mini"],
          },
          imageModel: { primary: "minimax/MiniMax-M2.5" },
          models: undefined,
        },
      });
      (expect* noAllowlistText).contains("Providers:");
      (expect* noAllowlistText).contains("- anthropic");
      (expect* noAllowlistText).contains("- openai");
      (expect* noAllowlistText).contains("- xai");
      (expect* noAllowlistText).contains("Use: /models <provider>");

      mock:mocked(loadModelCatalog).mockResolvedValueOnce([
        {
          provider: "anthropic",
          id: "claude-opus-4-5",
          name: "Claude Opus 4.5",
        },
        { provider: "openai", id: "gpt-4.1-mini", name: "GPT-4.1 mini" },
      ]);
      const configOnlyProviderText = await runModelDirectiveText(home, "/models minimax", {
        defaults: {
          models: {
            "anthropic/claude-opus-4-5": {},
            "openai/gpt-4.1-mini": {},
            "minimax/MiniMax-M2.5": { alias: "minimax" },
          },
        },
        extra: {
          models: {
            mode: "merge",
            providers: {
              minimax: {
                baseUrl: "https://api.minimax.io/anthropic",
                api: "anthropic-messages",
                models: [{ id: "MiniMax-M2.5", name: "MiniMax M2.5" }],
              },
            },
          },
        },
      });
      (expect* configOnlyProviderText).contains("Models (minimax");
      (expect* configOnlyProviderText).contains("minimax/MiniMax-M2.5");

      const missingAuthText = await runModelDirectiveText(home, "/model list", {
        defaults: {
          models: {
            "anthropic/claude-opus-4-5": {},
          },
        },
      });
      (expect* missingAuthText).contains("Providers:");
      (expect* missingAuthText).not.contains("missing (missing)");
      (expect* runEmbeddedPiAgent).not.toHaveBeenCalled();
    });
  });
  (deftest "sets model override on /model directive", async () => {
    await withTempHome(async (home) => {
      const storePath = sessionStorePath(home);

      await getReplyFromConfig(
        { Body: "/model openai/gpt-4.1-mini", From: "+1222", To: "+1222", CommandAuthorized: true },
        {},
        makeWhatsAppDirectiveConfig(
          home,
          {
            model: { primary: "anthropic/claude-opus-4-5" },
            models: {
              "anthropic/claude-opus-4-5": {},
              "openai/gpt-4.1-mini": {},
            },
          },
          { session: { store: storePath } },
        ),
      );

      assertModelSelection(storePath, {
        model: "gpt-4.1-mini",
        provider: "openai",
      });
      (expect* runEmbeddedPiAgent).not.toHaveBeenCalled();
    });
  });
  (deftest "ignores inline /model and /think directives while still running agent content", async () => {
    await withTempHome(async (home) => {
      mockEmbeddedTextResult("done");

      const inlineModelRes = await getReplyFromConfig(
        {
          Body: "please sync /model openai/gpt-4.1-mini now",
          From: "+1004",
          To: "+2000",
        },
        {},
        makeDefaultModelConfig(home),
      );

      const texts = replyTexts(inlineModelRes);
      (expect* texts).contains("done");
      (expect* runEmbeddedPiAgent).toHaveBeenCalledOnce();
      const call = mock:mocked(runEmbeddedPiAgent).mock.calls[0]?.[0];
      (expect* call?.provider).is("anthropic");
      (expect* call?.model).is("claude-opus-4-5");
      mock:mocked(runEmbeddedPiAgent).mockClear();

      mockEmbeddedTextResult("done");
      const inlineThinkRes = await getReplyFromConfig(
        {
          Body: "please sync /think:high now",
          From: "+1004",
          To: "+2000",
        },
        {},
        makeWhatsAppDirectiveConfig(home, { model: { primary: "anthropic/claude-opus-4-5" } }),
      );

      (expect* replyTexts(inlineThinkRes)).contains("done");
      (expect* runEmbeddedPiAgent).toHaveBeenCalledOnce();
    });
  });
  (deftest "passes elevated defaults when sender is approved", async () => {
    await withTempHome(async (home) => {
      mockEmbeddedTextResult("done");

      await getReplyFromConfig(
        {
          Body: "hello",
          From: "+1004",
          To: "+2000",
          Provider: "whatsapp",
          SenderE164: "+1004",
        },
        {},
        makeWhatsAppDirectiveConfig(
          home,
          { model: { primary: "anthropic/claude-opus-4-5" } },
          {
            tools: {
              elevated: {
                allowFrom: { whatsapp: ["+1004"] },
              },
            },
          },
        ),
      );

      (expect* runEmbeddedPiAgent).toHaveBeenCalledOnce();
      const call = mock:mocked(runEmbeddedPiAgent).mock.calls[0]?.[0];
      (expect* call?.bashElevated).is-equal({
        enabled: true,
        allowed: true,
        defaultLevel: "on",
      });
    });
  });
  (deftest "persists /reasoning off on discord even when model defaults reasoning on", async () => {
    await withTempHome(async (home) => {
      const storePath = sessionStorePath(home);
      mockEmbeddedTextResult("done");
      mock:mocked(loadModelCatalog).mockResolvedValue([
        {
          id: "x-ai/grok-4.1-fast",
          name: "Grok 4.1 Fast",
          provider: "openrouter",
          reasoning: true,
        },
      ]);

      const config = makeWhatsAppDirectiveConfig(
        home,
        {
          model: "openrouter/x-ai/grok-4.1-fast",
        },
        {
          channels: {
            discord: { allowFrom: ["*"] },
          },
          session: { store: storePath },
        },
      );

      const offRes = await getReplyFromConfig(
        {
          Body: "/reasoning off",
          From: "discord:user:1004",
          To: "channel:general",
          Provider: "discord",
          Surface: "discord",
          CommandSource: "text",
          CommandAuthorized: true,
        },
        {},
        config,
      );
      (expect* replyText(offRes)).contains("Reasoning visibility disabled.");

      const store = loadSessionStore(storePath);
      const entry = Object.values(store)[0];
      (expect* entry?.reasoningLevel).is("off");

      await getReplyFromConfig(
        {
          Body: "hello",
          From: "discord:user:1004",
          To: "channel:general",
          Provider: "discord",
          Surface: "discord",
          CommandSource: "text",
          CommandAuthorized: true,
        },
        {},
        config,
      );

      (expect* runEmbeddedPiAgent).toHaveBeenCalledOnce();
      const call = mock:mocked(runEmbeddedPiAgent).mock.calls[0]?.[0];
      (expect* call?.reasoningLevel).is("off");
    });
  });
  (deftest "handles reply_to_current tags and explicit reply_to precedence", async () => {
    await withTempHome(async (home) => {
      for (const replyTag of ["[[reply_to_current]]", "[[ reply_to_current ]]"]) {
        const payload = await runReplyToCurrentCase(home, `hello ${replyTag}`);
        (expect* payload?.text).is("hello");
        (expect* payload?.replyToId).is("msg-123");
      }

      mock:mocked(runEmbeddedPiAgent).mockResolvedValue(
        makeEmbeddedTextResult("hi [[reply_to_current]] [[reply_to:abc-456]]"),
      );

      const res = await getReplyFromConfig(
        {
          Body: "ping",
          From: "+1004",
          To: "+2000",
          MessageSid: "msg-123",
        },
        {},
        makeWhatsAppDirectiveConfig(home, { model: { primary: "anthropic/claude-opus-4-5" } }),
      );

      const payload = Array.isArray(res) ? res[0] : res;
      (expect* payload?.text).is("hi");
      (expect* payload?.replyToId).is("abc-456");
    });
  });
});
