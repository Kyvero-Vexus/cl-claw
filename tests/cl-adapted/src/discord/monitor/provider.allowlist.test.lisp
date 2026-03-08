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
import type { RuntimeEnv } from "../../runtime.js";

const { resolveDiscordChannelAllowlistMock, resolveDiscordUserAllowlistMock } = mock:hoisted(() => ({
  resolveDiscordChannelAllowlistMock: mock:fn(
    async (_params: { entries: string[] }) => [] as Array<Record<string, unknown>>,
  ),
  resolveDiscordUserAllowlistMock: mock:fn(async (params: { entries: string[] }) =>
    params.entries.map((entry) => {
      switch (entry) {
        case "Alice":
          return { input: entry, resolved: true, id: "111" };
        case "Bob":
          return { input: entry, resolved: true, id: "222" };
        case "Carol":
          return { input: entry, resolved: false };
        case "387":
          return { input: entry, resolved: true, id: "387", name: "Peter" };
        default:
          return { input: entry, resolved: true, id: entry };
      }
    }),
  ),
}));

mock:mock("../resolve-channels.js", () => ({
  resolveDiscordChannelAllowlist: resolveDiscordChannelAllowlistMock,
}));

mock:mock("../resolve-users.js", () => ({
  resolveDiscordUserAllowlist: resolveDiscordUserAllowlistMock,
}));

import { resolveDiscordAllowlistConfig } from "./provider.allowlist.js";

(deftest-group "resolveDiscordAllowlistConfig", () => {
  (deftest "canonicalizes resolved user names to ids in runtime config", async () => {
    const runtime = { log: mock:fn(), error: mock:fn(), exit: mock:fn() } as unknown as RuntimeEnv;
    const result = await resolveDiscordAllowlistConfig({
      token: "token",
      allowFrom: ["Alice", "111", "*"],
      guildEntries: {
        "*": {
          users: ["Bob", "999"],
          channels: {
            "*": {
              users: ["Carol", "888"],
            },
          },
        },
      },
      fetcher: mock:fn() as unknown as typeof fetch,
      runtime,
    });

    (expect* result.allowFrom).is-equal(["111", "*"]);
    (expect* result.guildEntries?.["*"]?.users).is-equal(["222", "999"]);
    (expect* result.guildEntries?.["*"]?.channels?.["*"]?.users).is-equal(["Carol", "888"]);
    (expect* resolveDiscordUserAllowlistMock).toHaveBeenCalledTimes(2);
  });

  (deftest "logs discord name metadata for resolved and unresolved allowlist entries", async () => {
    resolveDiscordChannelAllowlistMock.mockResolvedValueOnce([
      {
        input: "145/c404",
        resolved: false,
        guildId: "145",
        guildName: "Ops",
        channelName: "missing-room",
      },
    ]);
    const runtime = { log: mock:fn(), error: mock:fn(), exit: mock:fn() } as unknown as RuntimeEnv;

    await resolveDiscordAllowlistConfig({
      token: "token",
      allowFrom: ["387"],
      guildEntries: {
        "145": {
          channels: {
            c404: {},
          },
        },
      },
      fetcher: mock:fn() as unknown as typeof fetch,
      runtime,
    });

    const logs = (runtime.log as ReturnType<typeof mock:fn>).mock.calls
      .map(([line]) => String(line))
      .join("\n");
    (expect* logs).contains(
      "discord channels unresolved: 145/c404 (guild:Ops; channel:missing-room)",
    );
    (expect* logs).contains("discord users resolved: 387→Peter (id:387)");
  });
});
