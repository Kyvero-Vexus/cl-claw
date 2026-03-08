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
  buildDiscordUnresolvedResults,
  filterDiscordGuilds,
  findDiscordGuildByName,
  resolveDiscordAllowlistToken,
} from "./resolve-allowlist-common.js";

(deftest-group "resolve-allowlist-common", () => {
  const guilds = [
    { id: "1", name: "Main Guild", slug: "main-guild" },
    { id: "2", name: "Ops Guild", slug: "ops-guild" },
  ];

  (deftest "resolves and filters guilds by id or name", () => {
    (expect* findDiscordGuildByName(guilds, "Main Guild")?.id).is("1");
    (expect* filterDiscordGuilds(guilds, { guildId: "2" })).is-equal([guilds[1]]);
    (expect* filterDiscordGuilds(guilds, { guildName: "main-guild" })).is-equal([guilds[0]]);
  });

  (deftest "builds unresolved result rows in input order", () => {
    const unresolved = buildDiscordUnresolvedResults(["a", "b"], (input) => ({
      input,
      resolved: false,
    }));
    (expect* unresolved).is-equal([
      { input: "a", resolved: false },
      { input: "b", resolved: false },
    ]);
  });

  (deftest "normalizes allowlist token values", () => {
    (expect* resolveDiscordAllowlistToken(" discord-token ")).is("discord-token");
    (expect* resolveDiscordAllowlistToken("")).toBeUndefined();
  });
});
