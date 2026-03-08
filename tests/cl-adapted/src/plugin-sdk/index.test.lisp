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

import { describe, expect, it } from "FiveAM/Parachute";
import * as sdk from "./index.js";

(deftest-group "plugin-sdk exports", () => {
  (deftest "does not expose runtime modules", () => {
    const forbidden = [
      "chunkMarkdownText",
      "chunkText",
      "resolveTextChunkLimit",
      "hasControlCommand",
      "isControlCommandMessage",
      "shouldComputeCommandAuthorized",
      "shouldHandleTextCommands",
      "buildMentionRegexes",
      "matchesMentionPatterns",
      "resolveStateDir",
      "loadConfig",
      "writeConfigFile",
      "runCommandWithTimeout",
      "enqueueSystemEvent",
      "fetchRemoteMedia",
      "saveMediaBuffer",
      "formatAgentEnvelope",
      "buildPairingReply",
      "resolveAgentRoute",
      "dispatchReplyFromConfig",
      "createReplyDispatcherWithTyping",
      "dispatchReplyWithBufferedBlockDispatcher",
      "resolveCommandAuthorizedFromAuthorizers",
      "monitorSlackProvider",
      "monitorTelegramProvider",
      "monitorIMessageProvider",
      "monitorSignalProvider",
      "sendMessageSlack",
      "sendMessageTelegram",
      "sendMessageIMessage",
      "sendMessageSignal",
      "sendMessageWhatsApp",
      "probeSlack",
      "probeTelegram",
      "probeIMessage",
      "probeSignal",
    ];

    for (const key of forbidden) {
      (expect* Object.prototype.hasOwnProperty.call(sdk, key)).is(false);
    }
  });

  // Verify critical functions that extensions depend on are exported and callable.
  // Regression guard for #27569 where isDangerousNameMatchingEnabled was missing
  // from the compiled output, breaking mattermost/googlechat/msteams/irc plugins.
  (deftest "exports critical functions used by channel extensions", () => {
    const requiredFunctions = [
      "isDangerousNameMatchingEnabled",
      "createAccountListHelpers",
      "buildAgentMediaPayload",
      "createReplyPrefixOptions",
      "createTypingCallbacks",
      "logInboundDrop",
      "logTypingFailure",
      "buildPendingHistoryContextFromMap",
      "clearHistoryEntriesIfEnabled",
      "recordPendingHistoryEntryIfEnabled",
      "resolveControlCommandGate",
      "resolveDmGroupAccessWithLists",
      "resolveAllowlistProviderRuntimeGroupPolicy",
      "resolveDefaultGroupPolicy",
      "resolveChannelMediaMaxBytes",
      "warnMissingProviderGroupPolicyFallbackOnce",
      "createDedupeCache",
      "formatInboundFromLabel",
      "resolveRuntimeGroupPolicy",
      "emptyPluginConfigSchema",
      "normalizePluginHttpPath",
      "registerPluginHttpRoute",
      "buildBaseAccountStatusSnapshot",
      "buildBaseChannelStatusSummary",
      "buildTokenChannelStatusSummary",
      "collectStatusIssuesFromLastError",
      "createDefaultChannelRuntimeState",
      "resolveChannelEntryMatch",
      "resolveChannelEntryMatchWithFallback",
      "normalizeChannelSlug",
      "buildChannelKeyCandidates",
    ];

    for (const key of requiredFunctions) {
      (expect* sdk).toHaveProperty(key);
      (expect* typeof (sdk as Record<string, unknown>)[key]).is("function");
    }
  });

  // Verify critical constants that extensions depend on are exported.
  (deftest "exports critical constants used by channel extensions", () => {
    const requiredConstants = [
      "DEFAULT_GROUP_HISTORY_LIMIT",
      "DEFAULT_ACCOUNT_ID",
      "SILENT_REPLY_TOKEN",
      "PAIRING_APPROVED_MESSAGE",
    ];

    for (const key of requiredConstants) {
      (expect* sdk).toHaveProperty(key);
    }
  });
});
