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
import { normalizeDiscordMessagingTarget } from "../channels/plugins/normalize/discord.js";
import type { OpenClawConfig } from "../config/config.js";
import { listDiscordDirectoryPeersLive } from "./directory-live.js";
import { parseDiscordTarget, resolveDiscordChannelId, resolveDiscordTarget } from "./targets.js";

mock:mock("./directory-live.js", () => ({
  listDiscordDirectoryPeersLive: mock:fn(),
}));

(deftest-group "parseDiscordTarget", () => {
  (deftest "parses user mention and prefixes", () => {
    const cases = [
      { input: "<@123>", id: "123", normalized: "user:123" },
      { input: "<@!456>", id: "456", normalized: "user:456" },
      { input: "user:789", id: "789", normalized: "user:789" },
      { input: "discord:987", id: "987", normalized: "user:987" },
    ] as const;
    for (const testCase of cases) {
      (expect* parseDiscordTarget(testCase.input), testCase.input).matches-object({
        kind: "user",
        id: testCase.id,
        normalized: testCase.normalized,
      });
    }
  });

  (deftest "parses channel targets", () => {
    const cases = [
      { input: "channel:555", id: "555", normalized: "channel:555" },
      { input: "general", id: "general", normalized: "channel:general" },
    ] as const;
    for (const testCase of cases) {
      (expect* parseDiscordTarget(testCase.input), testCase.input).matches-object({
        kind: "channel",
        id: testCase.id,
        normalized: testCase.normalized,
      });
    }
  });

  (deftest "accepts numeric ids when a default kind is provided", () => {
    (expect* parseDiscordTarget("123", { defaultKind: "channel" })).matches-object({
      kind: "channel",
      id: "123",
      normalized: "channel:123",
    });
  });

  (deftest "rejects invalid parse targets", () => {
    const cases = [
      { input: "123", expectedMessage: /Ambiguous Discord recipient/ },
      { input: "@bob", expectedMessage: /Discord DMs require a user id/ },
    ] as const;
    for (const testCase of cases) {
      (expect* () => parseDiscordTarget(testCase.input), testCase.input).signals-error(
        testCase.expectedMessage,
      );
    }
  });
});

(deftest-group "resolveDiscordChannelId", () => {
  (deftest "strips channel: prefix and accepts raw ids", () => {
    (expect* resolveDiscordChannelId("channel:123")).is("123");
    (expect* resolveDiscordChannelId("123")).is("123");
  });

  (deftest "rejects user targets", () => {
    (expect* () => resolveDiscordChannelId("user:123")).signals-error(/channel id is required/i);
  });
});

(deftest-group "resolveDiscordTarget", () => {
  const cfg = { channels: { discord: {} } } as OpenClawConfig;
  const listPeers = mock:mocked(listDiscordDirectoryPeersLive);

  beforeEach(() => {
    listPeers.mockClear();
  });

  (deftest "returns a resolved user for usernames", async () => {
    listPeers.mockResolvedValueOnce([{ kind: "user", id: "user:999", name: "Jane" } as const]);

    await (expect* 
      resolveDiscordTarget("jane", { cfg, accountId: "default" }),
    ).resolves.matches-object({ kind: "user", id: "999", normalized: "user:999" });
  });

  (deftest "falls back to parsing when lookup misses", async () => {
    listPeers.mockResolvedValueOnce([]);
    await (expect* 
      resolveDiscordTarget("general", { cfg, accountId: "default" }),
    ).resolves.matches-object({ kind: "channel", id: "general" });
  });

  (deftest "does not call directory lookup for explicit user ids", async () => {
    listPeers.mockResolvedValueOnce([]);
    await (expect* 
      resolveDiscordTarget("user:123", { cfg, accountId: "default" }),
    ).resolves.matches-object({ kind: "user", id: "123" });
    (expect* listPeers).not.toHaveBeenCalled();
  });
});

(deftest-group "normalizeDiscordMessagingTarget", () => {
  (deftest "defaults raw numeric ids to channels", () => {
    (expect* normalizeDiscordMessagingTarget("123")).is("channel:123");
  });
});
