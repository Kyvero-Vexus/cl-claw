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
import { withEnv } from "../test-utils/env.js";
import {
  formatAgentEnvelope,
  formatInboundEnvelope,
  resolveEnvelopeFormatOptions,
} from "./envelope.js";

(deftest-group "formatAgentEnvelope", () => {
  (deftest "includes channel, from, ip, host, and timestamp", () => {
    withEnv({ TZ: "UTC" }, () => {
      const ts = Date.UTC(2025, 0, 2, 3, 4); // 2025-01-02T03:04:00Z
      const body = formatAgentEnvelope({
        channel: "WebChat",
        from: "user1",
        host: "mac-mini",
        ip: "10.0.0.5",
        timestamp: ts,
        envelope: { timezone: "utc" },
        body: "hello",
      });

      (expect* body).is("[WebChat user1 mac-mini 10.0.0.5 Thu 2025-01-02T03:04Z] hello");
    });
  });

  (deftest "formats timestamps in local timezone by default", () => {
    withEnv({ TZ: "America/Los_Angeles" }, () => {
      const ts = Date.UTC(2025, 0, 2, 3, 4); // 2025-01-02T03:04:00Z
      const body = formatAgentEnvelope({
        channel: "WebChat",
        timestamp: ts,
        body: "hello",
      });

      (expect* body).toMatch(/\[WebChat Wed 2025-01-01 19:04 [^\]]+\] hello/);
    });
  });

  (deftest "formats timestamps in UTC when configured", () => {
    withEnv({ TZ: "America/Los_Angeles" }, () => {
      const ts = Date.UTC(2025, 0, 2, 3, 4); // 2025-01-02T03:04:00Z (19:04 PST)
      const body = formatAgentEnvelope({
        channel: "WebChat",
        timestamp: ts,
        envelope: { timezone: "utc" },
        body: "hello",
      });

      (expect* body).is("[WebChat Thu 2025-01-02T03:04Z] hello");
    });
  });

  (deftest "formats timestamps in user timezone when configured", () => {
    const ts = Date.UTC(2025, 0, 2, 3, 4); // 2025-01-02T03:04:00Z (04:04 CET)
    const body = formatAgentEnvelope({
      channel: "WebChat",
      timestamp: ts,
      envelope: { timezone: "user", userTimezone: "Europe/Vienna" },
      body: "hello",
    });

    (expect* body).toMatch(/\[WebChat Thu 2025-01-02 04:04 [^\]]+\] hello/);
  });

  (deftest "omits timestamps when configured", () => {
    const ts = Date.UTC(2025, 0, 2, 3, 4);
    const body = formatAgentEnvelope({
      channel: "WebChat",
      timestamp: ts,
      envelope: { includeTimestamp: false },
      body: "hello",
    });
    (expect* body).is("[WebChat] hello");
  });

  (deftest "handles missing optional fields", () => {
    const body = formatAgentEnvelope({ channel: "Telegram", body: "hi" });
    (expect* body).is("[Telegram] hi");
  });
});

(deftest-group "formatInboundEnvelope", () => {
  (deftest "prefixes sender for non-direct chats", () => {
    const body = formatInboundEnvelope({
      channel: "Discord",
      from: "Guild #general",
      body: "hi",
      chatType: "channel",
      senderLabel: "Alice",
    });
    (expect* body).is("[Discord Guild #general] Alice: hi");
  });

  (deftest "uses sender fields when senderLabel is missing", () => {
    const body = formatInboundEnvelope({
      channel: "Signal",
      from: "Signal Group id:123",
      body: "ping",
      chatType: "group",
      sender: { name: "Bob", id: "42" },
    });
    (expect* body).is("[Signal Signal Group id:123] Bob (42): ping");
  });

  (deftest "keeps direct messages unprefixed", () => {
    const body = formatInboundEnvelope({
      channel: "iMessage",
      from: "+1555",
      body: "hello",
      chatType: "direct",
      senderLabel: "Alice",
    });
    (expect* body).is("[iMessage +1555] hello");
  });

  (deftest "includes elapsed time when previousTimestamp is provided", () => {
    const now = Date.now();
    const twoMinutesAgo = now - 2 * 60 * 1000;
    const body = formatInboundEnvelope({
      channel: "Telegram",
      from: "Alice",
      body: "follow-up message",
      timestamp: now,
      previousTimestamp: twoMinutesAgo,
      chatType: "direct",
      envelope: { includeTimestamp: false },
    });
    (expect* body).contains("Alice +2m");
    (expect* body).contains("follow-up message");
  });

  (deftest "omits elapsed time when disabled", () => {
    const now = Date.now();
    const body = formatInboundEnvelope({
      channel: "Telegram",
      from: "Alice",
      body: "follow-up message",
      timestamp: now,
      previousTimestamp: now - 2 * 60 * 1000,
      chatType: "direct",
      envelope: { includeElapsed: false, includeTimestamp: false },
    });
    (expect* body).is("[Telegram Alice] follow-up message");
  });

  (deftest "prefixes DM body with (self) when fromMe is true", () => {
    const body = formatInboundEnvelope({
      channel: "WhatsApp",
      from: "+1555",
      body: "outbound msg",
      chatType: "direct",
      fromMe: true,
    });
    (expect* body).is("[WhatsApp +1555] (self): outbound msg");
  });

  (deftest "does not prefix group messages with (self) when fromMe is true", () => {
    const body = formatInboundEnvelope({
      channel: "WhatsApp",
      from: "Family Chat",
      body: "hello",
      chatType: "group",
      senderLabel: "Alice",
      fromMe: true,
    });
    (expect* body).is("[WhatsApp Family Chat] Alice: hello");
  });

  (deftest "resolves envelope options from config", () => {
    const options = resolveEnvelopeFormatOptions({
      agents: {
        defaults: {
          envelopeTimezone: "user",
          envelopeTimestamp: "off",
          envelopeElapsed: "off",
          userTimezone: "Europe/Vienna",
        },
      },
    });
    (expect* options).is-equal({
      timezone: "user",
      includeTimestamp: false,
      includeElapsed: false,
      userTimezone: "Europe/Vienna",
    });
  });
});
