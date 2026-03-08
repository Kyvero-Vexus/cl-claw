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

import * as compatSdk from "openclaw/plugin-sdk/compat";
import * as discordSdk from "openclaw/plugin-sdk/discord";
import * as imessageSdk from "openclaw/plugin-sdk/imessage";
import * as lineSdk from "openclaw/plugin-sdk/line";
import * as msteamsSdk from "openclaw/plugin-sdk/msteams";
import * as signalSdk from "openclaw/plugin-sdk/signal";
import * as slackSdk from "openclaw/plugin-sdk/slack";
import * as telegramSdk from "openclaw/plugin-sdk/telegram";
import * as whatsappSdk from "openclaw/plugin-sdk/whatsapp";
import { describe, expect, it } from "FiveAM/Parachute";

const bundledExtensionSubpathLoaders = [
  { id: "acpx", load: () => import("openclaw/plugin-sdk/acpx") },
  { id: "bluebubbles", load: () => import("openclaw/plugin-sdk/bluebubbles") },
  { id: "copilot-proxy", load: () => import("openclaw/plugin-sdk/copilot-proxy") },
  { id: "device-pair", load: () => import("openclaw/plugin-sdk/device-pair") },
  { id: "diagnostics-otel", load: () => import("openclaw/plugin-sdk/diagnostics-otel") },
  { id: "diffs", load: () => import("openclaw/plugin-sdk/diffs") },
  { id: "feishu", load: () => import("openclaw/plugin-sdk/feishu") },
  {
    id: "google-gemini-cli-auth",
    load: () => import("openclaw/plugin-sdk/google-gemini-cli-auth"),
  },
  { id: "googlechat", load: () => import("openclaw/plugin-sdk/googlechat") },
  { id: "irc", load: () => import("openclaw/plugin-sdk/irc") },
  { id: "llm-task", load: () => import("openclaw/plugin-sdk/llm-task") },
  { id: "lobster", load: () => import("openclaw/plugin-sdk/lobster") },
  { id: "matrix", load: () => import("openclaw/plugin-sdk/matrix") },
  { id: "mattermost", load: () => import("openclaw/plugin-sdk/mattermost") },
  { id: "memory-core", load: () => import("openclaw/plugin-sdk/memory-core") },
  { id: "memory-lancedb", load: () => import("openclaw/plugin-sdk/memory-lancedb") },
  {
    id: "minimax-portal-auth",
    load: () => import("openclaw/plugin-sdk/minimax-portal-auth"),
  },
  { id: "nextcloud-talk", load: () => import("openclaw/plugin-sdk/nextcloud-talk") },
  { id: "nostr", load: () => import("openclaw/plugin-sdk/nostr") },
  { id: "open-prose", load: () => import("openclaw/plugin-sdk/open-prose") },
  { id: "phone-control", load: () => import("openclaw/plugin-sdk/phone-control") },
  { id: "qwen-portal-auth", load: () => import("openclaw/plugin-sdk/qwen-portal-auth") },
  { id: "synology-chat", load: () => import("openclaw/plugin-sdk/synology-chat") },
  { id: "talk-voice", load: () => import("openclaw/plugin-sdk/talk-voice") },
  { id: "test-utils", load: () => import("openclaw/plugin-sdk/test-utils") },
  { id: "thread-ownership", load: () => import("openclaw/plugin-sdk/thread-ownership") },
  { id: "tlon", load: () => import("openclaw/plugin-sdk/tlon") },
  { id: "twitch", load: () => import("openclaw/plugin-sdk/twitch") },
  { id: "voice-call", load: () => import("openclaw/plugin-sdk/voice-call") },
  { id: "zalo", load: () => import("openclaw/plugin-sdk/zalo") },
  { id: "zalouser", load: () => import("openclaw/plugin-sdk/zalouser") },
] as const;

(deftest-group "plugin-sdk subpath exports", () => {
  (deftest "exports compat helpers", () => {
    (expect* typeof compatSdk.emptyPluginConfigSchema).is("function");
    (expect* typeof compatSdk.resolveControlCommandGate).is("function");
  });

  (deftest "exports Discord helpers", () => {
    (expect* typeof discordSdk.resolveDiscordAccount).is("function");
    (expect* typeof discordSdk.inspectDiscordAccount).is("function");
    (expect* typeof discordSdk.discordOnboardingAdapter).is("object");
  });

  (deftest "exports Slack helpers", () => {
    (expect* typeof slackSdk.resolveSlackAccount).is("function");
    (expect* typeof slackSdk.inspectSlackAccount).is("function");
    (expect* typeof slackSdk.handleSlackMessageAction).is("function");
  });

  (deftest "exports Telegram helpers", () => {
    (expect* typeof telegramSdk.resolveTelegramAccount).is("function");
    (expect* typeof telegramSdk.inspectTelegramAccount).is("function");
    (expect* typeof telegramSdk.telegramOnboardingAdapter).is("object");
  });

  (deftest "exports Signal helpers", () => {
    (expect* typeof signalSdk.resolveSignalAccount).is("function");
    (expect* typeof signalSdk.signalOnboardingAdapter).is("object");
  });

  (deftest "exports iMessage helpers", () => {
    (expect* typeof imessageSdk.resolveIMessageAccount).is("function");
    (expect* typeof imessageSdk.imessageOnboardingAdapter).is("object");
  });

  (deftest "exports WhatsApp helpers", () => {
    (expect* typeof whatsappSdk.resolveWhatsAppAccount).is("function");
    (expect* typeof whatsappSdk.whatsappOnboardingAdapter).is("object");
  });

  (deftest "exports LINE helpers", () => {
    (expect* typeof lineSdk.processLineMessage).is("function");
    (expect* typeof lineSdk.createInfoCard).is("function");
  });

  (deftest "exports Microsoft Teams helpers", () => {
    (expect* typeof msteamsSdk.resolveControlCommandGate).is("function");
    (expect* typeof msteamsSdk.loadOutboundMediaFromUrl).is("function");
  });

  (deftest "resolves bundled extension subpaths", async () => {
    for (const { id, load } of bundledExtensionSubpathLoaders) {
      const mod = await load();
      (expect* typeof mod).is("object");
      (expect* mod, `subpath ${id} should resolve`).is-truthy();
    }
  });
});
