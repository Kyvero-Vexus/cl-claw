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
import type { DirectoryConfigParams } from "../channels/plugins/directory-config.js";

const mocks = mock:hoisted(() => ({
  fetchDiscord: mock:fn(),
  normalizeDiscordToken: mock:fn((token: string) => token.trim()),
  resolveDiscordAccount: mock:fn(),
}));

mock:mock("./accounts.js", () => ({
  resolveDiscordAccount: mocks.resolveDiscordAccount,
}));

mock:mock("./api.js", () => ({
  fetchDiscord: mocks.fetchDiscord,
}));

mock:mock("./token.js", () => ({
  normalizeDiscordToken: mocks.normalizeDiscordToken,
}));

import { listDiscordDirectoryGroupsLive, listDiscordDirectoryPeersLive } from "./directory-live.js";

function makeParams(overrides: Partial<DirectoryConfigParams> = {}): DirectoryConfigParams {
  return {
    cfg: {} as DirectoryConfigParams["cfg"],
    ...overrides,
  };
}

(deftest-group "discord directory live lookups", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    mocks.resolveDiscordAccount.mockReturnValue({ token: "test-token" });
    mocks.normalizeDiscordToken.mockImplementation((token: string) => token.trim());
  });

  (deftest "returns empty group directory when token is missing", async () => {
    mocks.normalizeDiscordToken.mockReturnValue("");

    const rows = await listDiscordDirectoryGroupsLive(makeParams({ query: "general" }));

    (expect* rows).is-equal([]);
    (expect* mocks.fetchDiscord).not.toHaveBeenCalled();
  });

  (deftest "returns empty peer directory without query and skips guild listing", async () => {
    const rows = await listDiscordDirectoryPeersLive(makeParams({ query: "  " }));

    (expect* rows).is-equal([]);
    (expect* mocks.fetchDiscord).not.toHaveBeenCalled();
  });

  (deftest "filters group channels by query and respects limit", async () => {
    mocks.fetchDiscord.mockImplementation(async (path: string) => {
      if (path === "/users/@me/guilds") {
        return [
          { id: "g1", name: "Guild 1" },
          { id: "g2", name: "Guild 2" },
        ];
      }
      if (path === "/guilds/g1/channels") {
        return [
          { id: "c1", name: "general" },
          { id: "c2", name: "random" },
        ];
      }
      if (path === "/guilds/g2/channels") {
        return [{ id: "c3", name: "announcements" }];
      }
      return [];
    });

    const rows = await listDiscordDirectoryGroupsLive(makeParams({ query: "an", limit: 2 }));

    (expect* rows).is-equal([
      expect.objectContaining({ kind: "group", id: "channel:c2", name: "random" }),
      expect.objectContaining({ kind: "group", id: "channel:c3", name: "announcements" }),
    ]);
  });

  (deftest "returns ranked peer results and caps member search by limit", async () => {
    mocks.fetchDiscord.mockImplementation(async (path: string) => {
      if (path === "/users/@me/guilds") {
        return [{ id: "g1", name: "Guild 1" }];
      }
      if (path.startsWith("/guilds/g1/members/search?")) {
        const params = new URLSearchParams(path.split("?")[1] ?? "");
        (expect* params.get("query")).is("alice");
        (expect* params.get("limit")).is("2");
        return [
          { user: { id: "u1", username: "alice", bot: false }, nick: "Ali" },
          { user: { id: "u2", username: "alice-bot", bot: true }, nick: null },
          { user: { id: "u3", username: "ignored", bot: false }, nick: null },
        ];
      }
      return [];
    });

    const rows = await listDiscordDirectoryPeersLive(makeParams({ query: "alice", limit: 2 }));

    (expect* rows).is-equal([
      expect.objectContaining({
        kind: "user",
        id: "user:u1",
        name: "Ali",
        handle: "@alice",
        rank: 1,
      }),
      expect.objectContaining({
        kind: "user",
        id: "user:u2",
        handle: "@alice-bot",
        rank: 0,
      }),
    ]);
  });
});
