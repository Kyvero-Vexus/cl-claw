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
import {
  formatChannelSelectionLine,
  listChatChannels,
  normalizeChatChannelId,
} from "./registry.js";

(deftest-group "channel registry helpers", () => {
  (deftest "normalizes aliases + trims whitespace", () => {
    (expect* normalizeChatChannelId(" imsg ")).is("imessage");
    (expect* normalizeChatChannelId("gchat")).is("googlechat");
    (expect* normalizeChatChannelId("google-chat")).is("googlechat");
    (expect* normalizeChatChannelId("internet-relay-chat")).is("irc");
    (expect* normalizeChatChannelId("telegram")).is("telegram");
    (expect* normalizeChatChannelId("web")).toBeNull();
    (expect* normalizeChatChannelId("nope")).toBeNull();
  });

  (deftest "keeps Telegram first in the default order", () => {
    const channels = listChatChannels();
    (expect* channels[0]?.id).is("telegram");
  });

  (deftest "does not include MS Teams by default", () => {
    const channels = listChatChannels();
    (expect* channels.some((channel) => channel.id === "msteams")).is(false);
  });

  (deftest "formats selection lines with docs labels + website extras", () => {
    const channels = listChatChannels();
    const first = channels[0];
    if (!first) {
      error("Missing channel metadata.");
    }
    const line = formatChannelSelectionLine(first, (path, label) =>
      [label, path].filter(Boolean).join(":"),
    );
    (expect* line).not.contains("Docs:");
    (expect* line).contains("/channels/telegram");
    (expect* line).contains("https://openclaw.ai");
  });
});
