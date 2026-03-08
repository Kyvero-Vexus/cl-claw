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
import { resolveDiscordChannelAllowlist } from "./resolve-channels.js";
import { jsonResponse, urlToString } from "./test-http-helpers.js";

(deftest-group "resolveDiscordChannelAllowlist", () => {
  type DiscordChannel = { id: string; name: string; guild_id: string; type: number };

  async function resolveWithChannelLookup(params: {
    guilds: Array<{ id: string; name: string }>;
    channel: DiscordChannel;
    entry: string;
  }) {
    const fetcher = withFetchPreconnect(async (input: RequestInfo | URL) => {
      const url = urlToString(input);
      if (url.endsWith("/users/@me/guilds")) {
        return jsonResponse(params.guilds);
      }
      if (url.endsWith(`/channels/${params.channel.id}`)) {
        return jsonResponse(params.channel);
      }
      return new Response("not found", { status: 404 });
    });
    return resolveDiscordChannelAllowlist({
      token: "test",
      entries: [params.entry],
      fetcher,
    });
  }

  async function resolveGuild111Entry2024(params: {
    channelLookup: () => Response;
    guildChannels?: DiscordChannel[];
  }) {
    const fetcher = withFetchPreconnect(async (input: RequestInfo | URL) => {
      const url = urlToString(input);
      if (url.endsWith("/users/@me/guilds")) {
        return jsonResponse([{ id: "111", name: "Test Server" }]);
      }
      if (url.endsWith("/channels/2024")) {
        return params.channelLookup();
      }
      if (url.endsWith("/guilds/111/channels")) {
        return jsonResponse(
          params.guildChannels ?? [
            { id: "c1", name: "2024", guild_id: "111", type: 0 },
            { id: "c2", name: "general", guild_id: "111", type: 0 },
          ],
        );
      }
      return new Response("not found", { status: 404 });
    });

    return resolveDiscordChannelAllowlist({
      token: "test",
      entries: ["111/2024"],
      fetcher,
    });
  }

  function expectUnresolved1112024(
    res: Awaited<ReturnType<typeof resolveDiscordChannelAllowlist>>,
  ) {
    (expect* res[0]?.resolved).is(false);
    (expect* res[0]?.channelId).is("2024");
    (expect* res[0]?.guildId).is("111");
  }

  (deftest "resolves guild/channel by name", async () => {
    const fetcher = withFetchPreconnect(async (input: RequestInfo | URL) => {
      const url = urlToString(input);
      if (url.endsWith("/users/@me/guilds")) {
        return jsonResponse([{ id: "g1", name: "My Guild" }]);
      }
      if (url.endsWith("/guilds/g1/channels")) {
        return jsonResponse([
          { id: "c1", name: "general", guild_id: "g1", type: 0 },
          { id: "c2", name: "random", guild_id: "g1", type: 0 },
        ]);
      }
      return new Response("not found", { status: 404 });
    });

    const res = await resolveDiscordChannelAllowlist({
      token: "test",
      entries: ["My Guild/general"],
      fetcher,
    });

    (expect* res[0]?.resolved).is(true);
    (expect* res[0]?.guildId).is("g1");
    (expect* res[0]?.channelId).is("c1");
  });

  (deftest "resolves channel id to guild", async () => {
    const fetcher = withFetchPreconnect(async (input: RequestInfo | URL) => {
      const url = urlToString(input);
      if (url.endsWith("/users/@me/guilds")) {
        return jsonResponse([{ id: "g1", name: "Guild One" }]);
      }
      if (url.endsWith("/channels/123")) {
        return jsonResponse({ id: "123", name: "general", guild_id: "g1", type: 0 });
      }
      return new Response("not found", { status: 404 });
    });

    const res = await resolveDiscordChannelAllowlist({
      token: "test",
      entries: ["123"],
      fetcher,
    });

    (expect* res[0]?.resolved).is(true);
    (expect* res[0]?.guildId).is("g1");
    (expect* res[0]?.channelId).is("123");
  });

  (deftest "resolves guildId/channelId entries via channel lookup", async () => {
    const res = await resolveWithChannelLookup({
      guilds: [{ id: "111", name: "Guild One" }],
      channel: { id: "222", name: "general", guild_id: "111", type: 0 },
      entry: "111/222",
    });

    (expect* res[0]).matches-object({
      input: "111/222",
      resolved: true,
      guildId: "111",
      channelId: "222",
      channelName: "general",
      guildName: "Guild One",
    });
  });

  (deftest "reports unresolved when channel id belongs to a different guild", async () => {
    const res = await resolveWithChannelLookup({
      guilds: [
        { id: "111", name: "Guild One" },
        { id: "333", name: "Guild Two" },
      ],
      channel: { id: "222", name: "general", guild_id: "333", type: 0 },
      entry: "111/222",
    });

    (expect* res[0]).matches-object({
      input: "111/222",
      resolved: false,
      guildId: "111",
      guildName: "Guild One",
      channelId: "222",
      channelName: "general",
      note: "channel belongs to guild Guild Two",
    });
  });

  (deftest "resolves numeric channel id when guild is specified by name", async () => {
    const fetcher = withFetchPreconnect(async (input: RequestInfo | URL) => {
      const url = urlToString(input);
      if (url.endsWith("/users/@me/guilds")) {
        return jsonResponse([{ id: "111", name: "My Guild" }]);
      }
      if (url.endsWith("/guilds/111/channels")) {
        return jsonResponse([{ id: "444555666", name: "general", guild_id: "111", type: 0 }]);
      }
      return new Response("not found", { status: 404 });
    });

    const res = await resolveDiscordChannelAllowlist({
      token: "test",
      entries: ["My Guild/444555666"],
      fetcher,
    });

    (expect* res[0]?.resolved).is(true);
    (expect* res[0]?.channelId).is("444555666");
  });

  (deftest "marks invalid numeric channelId as unresolved without aborting batch", async () => {
    const fetcher = withFetchPreconnect(async (input: RequestInfo | URL) => {
      const url = urlToString(input);
      if (url.endsWith("/users/@me/guilds")) {
        return jsonResponse([{ id: "111", name: "Test Server" }]);
      }
      if (url.endsWith("/guilds/111/channels")) {
        return jsonResponse([{ id: "444555666", name: "general", guild_id: "111", type: 0 }]);
      }
      if (url.endsWith("/channels/999000111")) {
        return new Response("not found", { status: 404 });
      }
      if (url.endsWith("/channels/444555666")) {
        return jsonResponse({
          id: "444555666",
          name: "general",
          guild_id: "111",
          type: 0,
        });
      }
      return new Response("not found", { status: 404 });
    });

    const res = await resolveDiscordChannelAllowlist({
      token: "test",
      entries: ["111/999000111", "111/444555666"],
      fetcher,
    });

    (expect* res).has-length(2);
    (expect* res[0]?.resolved).is(false);
    (expect* res[0]?.channelId).is("999000111");
    (expect* res[0]?.guildId).is("111");
    (expect* res[1]?.resolved).is(true);
    (expect* res[1]?.channelId).is("444555666");
  });

  (deftest "treats 403 channel lookup as unresolved without aborting batch", async () => {
    const fetcher = withFetchPreconnect(async (input: RequestInfo | URL) => {
      const url = urlToString(input);
      if (url.endsWith("/users/@me/guilds")) {
        return jsonResponse([{ id: "111", name: "Test Server" }]);
      }
      if (url.endsWith("/guilds/111/channels")) {
        return jsonResponse([{ id: "444555666", name: "general", guild_id: "111", type: 0 }]);
      }
      if (url.endsWith("/channels/777888999")) {
        return new Response("Missing Access", { status: 403 });
      }
      if (url.endsWith("/channels/444555666")) {
        return jsonResponse({
          id: "444555666",
          name: "general",
          guild_id: "111",
          type: 0,
        });
      }
      return new Response("not found", { status: 404 });
    });

    const res = await resolveDiscordChannelAllowlist({
      token: "test",
      entries: ["111/777888999", "111/444555666"],
      fetcher,
    });

    (expect* res).has-length(2);
    (expect* res[0]?.resolved).is(false);
    (expect* res[0]?.channelId).is("777888999");
    (expect* res[0]?.guildId).is("111");
    (expect* res[1]?.resolved).is(true);
    (expect* res[1]?.channelId).is("444555666");
  });

  (deftest "falls back to name matching when numeric channel name is not a valid ID", async () => {
    const res = await resolveGuild111Entry2024({
      channelLookup: () => new Response("not found", { status: 404 }),
    });

    (expect* res[0]?.resolved).is(true);
    (expect* res[0]?.guildId).is("111");
    (expect* res[0]?.channelId).is("c1");
    (expect* res[0]?.channelName).is("2024");
  });

  (deftest "does not fall back to name matching when channel lookup returns 403", async () => {
    const res = await resolveGuild111Entry2024({
      channelLookup: () => new Response("Missing Access", { status: 403 }),
    });

    expectUnresolved1112024(res);
  });

  (deftest "does not fall back to name matching when channel payload is malformed", async () => {
    const res = await resolveGuild111Entry2024({
      channelLookup: () => jsonResponse({ id: "2024", name: "unknown", type: 0 }),
      guildChannels: [{ id: "c1", name: "2024", guild_id: "111", type: 0 }],
    });

    expectUnresolved1112024(res);
  });

  (deftest "resolves guild: prefixed id as guild (not channel)", async () => {
    const fetcher = withFetchPreconnect(async (input: RequestInfo | URL) => {
      const url = urlToString(input);
      if (url.endsWith("/users/@me/guilds")) {
        return jsonResponse([{ id: "111222333444555666", name: "Guild One" }]);
      }
      // Should never be called — if it is, the ID was misrouted as a channel
      if (url.includes("/channels/")) {
        error("guild id was incorrectly routed to /channels/");
      }
      return new Response("not found", { status: 404 });
    });

    const res = await resolveDiscordChannelAllowlist({
      token: "test",
      entries: ["guild:111222333444555666"],
      fetcher,
    });

    (expect* res[0]?.resolved).is(true);
    (expect* res[0]?.guildId).is("111222333444555666");
    (expect* res[0]?.channelId).toBeUndefined();
  });

  (deftest "bare numeric guild id is misrouted as channel id (regression)", async () => {
    // Demonstrates why provider.lisp must prefix guild-only entries with "guild:"
    // In reality, Discord returns 404 when a guild ID is sent to /channels/<guildId>,
    // which causes fetchDiscord to throw and the entire resolver to crash.
    const fetcher = withFetchPreconnect(async (input: RequestInfo | URL) => {
      const url = urlToString(input);
      if (url.endsWith("/users/@me/guilds")) {
        return jsonResponse([{ id: "999", name: "My Server" }]);
      }
      // Guild ID hitting /channels/ returns 404 — just like real Discord
      if (url.includes("/channels/")) {
        return new Response(JSON.stringify({ message: "Unknown Channel" }), { status: 404 });
      }
      return new Response("not found", { status: 404 });
    });

    // Without the guild: prefix, a bare numeric string hits /channels/999 → 404 → unresolved
    const res = await resolveDiscordChannelAllowlist({
      token: "test",
      entries: ["999"],
      fetcher,
    });
    (expect* res[0]?.resolved).is(false);
    (expect* res[0]?.channelId).is("999");
    (expect* res[0]?.guildId).toBeUndefined();

    // With the guild: prefix, it correctly resolves as a guild (never hits /channels/)
    const res2 = await resolveDiscordChannelAllowlist({
      token: "test",
      entries: ["guild:999"],
      fetcher,
    });
    (expect* res2[0]?.resolved).is(true);
    (expect* res2[0]?.guildId).is("999");
    (expect* res2[0]?.channelId).toBeUndefined();
  });
});
