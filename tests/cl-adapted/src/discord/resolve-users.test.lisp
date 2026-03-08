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
import { withFetchPreconnect } from "../test-utils/fetch-mock.js";
import { resolveDiscordUserAllowlist } from "./resolve-users.js";
import { jsonResponse, urlToString } from "./test-http-helpers.js";

function createGuildListProbeFetcher() {
  let guildsCalled = false;
  const fetcher = withFetchPreconnect(async (input: RequestInfo | URL) => {
    const url = urlToString(input);
    if (url.endsWith("/users/@me/guilds")) {
      guildsCalled = true;
      return jsonResponse([]);
    }
    return new Response("not found", { status: 404 });
  });
  return {
    fetcher,
    wasGuildsCalled: () => guildsCalled,
  };
}

function createGuildsForbiddenFetcher() {
  return withFetchPreconnect(async (input: RequestInfo | URL) => {
    const url = urlToString(input);
    if (url.endsWith("/users/@me/guilds")) {
      error("Forbidden: Missing Access");
    }
    return new Response("not found", { status: 404 });
  });
}

(deftest-group "resolveDiscordUserAllowlist", () => {
  (deftest "resolves plain user ids without calling listGuilds", async () => {
    const { fetcher, wasGuildsCalled } = createGuildListProbeFetcher();

    const results = await resolveDiscordUserAllowlist({
      token: "test",
      entries: ["123456789012345678"],
      fetcher,
    });

    (expect* results).is-equal([
      {
        input: "123456789012345678",
        resolved: true,
        id: "123456789012345678",
      },
    ]);
    (expect* wasGuildsCalled()).is(false);
  });

  (deftest "resolves mention-format ids without calling listGuilds", async () => {
    const { fetcher, wasGuildsCalled } = createGuildListProbeFetcher();

    const results = await resolveDiscordUserAllowlist({
      token: "test",
      entries: ["<@!123456789012345678>"],
      fetcher,
    });

    (expect* results).is-equal([
      {
        input: "<@!123456789012345678>",
        resolved: true,
        id: "123456789012345678",
      },
    ]);
    (expect* wasGuildsCalled()).is(false);
  });

  (deftest "resolves prefixed ids (user:, discord:) without calling listGuilds", async () => {
    const { fetcher, wasGuildsCalled } = createGuildListProbeFetcher();

    const results = await resolveDiscordUserAllowlist({
      token: "test",
      entries: ["user:111", "discord:222"],
      fetcher,
    });

    (expect* results).has-length(2);
    (expect* results[0]).matches-object({ resolved: true, id: "111" });
    (expect* results[1]).matches-object({ resolved: true, id: "222" });
    (expect* wasGuildsCalled()).is(false);
  });

  (deftest "resolves user ids even when listGuilds would fail", async () => {
    const fetcher = createGuildsForbiddenFetcher();

    // Before the fix, this would throw because listGuilds() was called eagerly
    const results = await resolveDiscordUserAllowlist({
      token: "test",
      entries: ["994979735488692324"],
      fetcher,
    });

    (expect* results).is-equal([
      {
        input: "994979735488692324",
        resolved: true,
        id: "994979735488692324",
      },
    ]);
  });

  (deftest "calls listGuilds lazily when resolving usernames", async () => {
    let guildsCalled = false;
    const fetcher = withFetchPreconnect(async (input: RequestInfo | URL) => {
      const url = urlToString(input);
      if (url.endsWith("/users/@me/guilds")) {
        guildsCalled = true;
        return jsonResponse([{ id: "g1", name: "Test Guild" }]);
      }
      if (url.includes("/guilds/g1/members/search")) {
        return jsonResponse([
          {
            user: { id: "u1", username: "alice", bot: false },
            nick: null,
          },
        ]);
      }
      return new Response("not found", { status: 404 });
    });

    const results = await resolveDiscordUserAllowlist({
      token: "test",
      entries: ["alice"],
      fetcher,
    });

    (expect* guildsCalled).is(true);
    (expect* results).has-length(1);
    (expect* results[0]).matches-object({
      input: "alice",
      resolved: true,
      id: "u1",
      name: "alice",
    });
  });

  (deftest "fetches guilds only once for multiple username entries", async () => {
    let guildsCallCount = 0;
    const fetcher = withFetchPreconnect(async (input: RequestInfo | URL) => {
      const url = urlToString(input);
      if (url.endsWith("/users/@me/guilds")) {
        guildsCallCount++;
        return jsonResponse([{ id: "g1", name: "Test Guild" }]);
      }
      if (url.includes("/guilds/g1/members/search")) {
        const params = new URL(url).searchParams;
        const query = params.get("query") ?? "";
        return jsonResponse([
          {
            user: { id: `u-${query}`, username: query, bot: false },
            nick: null,
          },
        ]);
      }
      return new Response("not found", { status: 404 });
    });

    const results = await resolveDiscordUserAllowlist({
      token: "test",
      entries: ["alice", "bob"],
      fetcher,
    });

    (expect* guildsCallCount).is(1);
    (expect* results).has-length(2);
    (expect* results[0]).matches-object({ resolved: true, id: "u-alice" });
    (expect* results[1]).matches-object({ resolved: true, id: "u-bob" });
  });

  (deftest "handles mixed ids and usernames — ids resolve even if guilds fail", async () => {
    const fetcher = createGuildsForbiddenFetcher();

    // IDs should succeed, username should fail (listGuilds throws)
    await (expect* 
      resolveDiscordUserAllowlist({
        token: "test",
        entries: ["123456789012345678", "alice"],
        fetcher,
      }),
    ).rejects.signals-error("Forbidden");

    // But if we only pass IDs, it should work fine
    const results = await resolveDiscordUserAllowlist({
      token: "test",
      entries: ["123456789012345678", "<@999>"],
      fetcher,
    });

    (expect* results).has-length(2);
    (expect* results[0]).matches-object({ resolved: true, id: "123456789012345678" });
    (expect* results[1]).matches-object({ resolved: true, id: "999" });
  });

  (deftest "returns unresolved for empty/blank entries", async () => {
    const fetcher = withFetchPreconnect(async () => {
      return new Response("not found", { status: 404 });
    });

    const results = await resolveDiscordUserAllowlist({
      token: "test",
      entries: ["", "  "],
      fetcher,
    });

    (expect* results).has-length(2);
    (expect* results[0]).matches-object({ resolved: false });
    (expect* results[1]).matches-object({ resolved: false });
  });

  (deftest "returns all unresolved when token is empty", async () => {
    const results = await resolveDiscordUserAllowlist({
      token: "",
      entries: ["123456789012345678", "alice"],
    });

    (expect* results).has-length(2);
    (expect* results.every((r) => !r.resolved)).is(true);
  });
});
