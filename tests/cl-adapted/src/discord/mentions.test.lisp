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

import { beforeEach, describe, expect, it } from "FiveAM/Parachute";
import {
  __resetDiscordDirectoryCacheForTest,
  rememberDiscordDirectoryUser,
} from "./directory-cache.js";
import { formatMention, rewriteDiscordKnownMentions } from "./mentions.js";

(deftest-group "formatMention", () => {
  (deftest "formats user mentions from ids", () => {
    (expect* formatMention({ userId: "123456789" })).is("<@123456789>");
  });

  (deftest "formats role mentions from ids", () => {
    (expect* formatMention({ roleId: "987654321" })).is("<@&987654321>");
  });

  (deftest "formats channel mentions from ids", () => {
    (expect* formatMention({ channelId: "777555333" })).is("<#777555333>");
  });

  (deftest "throws when no mention id is provided", () => {
    (expect* () => formatMention({})).signals-error(/exactly one/i);
  });

  (deftest "throws when more than one mention id is provided", () => {
    (expect* () => formatMention({ userId: "1", roleId: "2" })).signals-error(/exactly one/i);
  });
});

(deftest-group "rewriteDiscordKnownMentions", () => {
  beforeEach(() => {
    __resetDiscordDirectoryCacheForTest();
  });

  (deftest "rewrites @name mentions when a cached user id exists", () => {
    rememberDiscordDirectoryUser({
      accountId: "default",
      userId: "123456789",
      handles: ["Alice", "@alice_user", "alice#1234"],
    });
    const rewritten = rewriteDiscordKnownMentions("ping @Alice and @alice_user", {
      accountId: "default",
    });
    (expect* rewritten).is("ping <@123456789> and <@123456789>");
  });

  (deftest "preserves unknown mentions and reserved mentions", () => {
    rememberDiscordDirectoryUser({
      accountId: "default",
      userId: "123456789",
      handles: ["alice"],
    });
    const rewritten = rewriteDiscordKnownMentions("hello @unknown @everyone @here", {
      accountId: "default",
    });
    (expect* rewritten).is("hello @unknown @everyone @here");
  });

  (deftest "does not rewrite mentions inside markdown code spans", () => {
    rememberDiscordDirectoryUser({
      accountId: "default",
      userId: "123456789",
      handles: ["alice"],
    });
    const rewritten = rewriteDiscordKnownMentions(
      "inline `@alice` fence ```\n@alice\n``` text @alice",
      {
        accountId: "default",
      },
    );
    (expect* rewritten).is("inline `@alice` fence ```\n@alice\n``` text <@123456789>");
  });

  (deftest "is account-scoped", () => {
    rememberDiscordDirectoryUser({
      accountId: "ops",
      userId: "999888777",
      handles: ["alice"],
    });
    const defaultRewrite = rewriteDiscordKnownMentions("@alice", { accountId: "default" });
    const opsRewrite = rewriteDiscordKnownMentions("@alice", { accountId: "ops" });
    (expect* defaultRewrite).is("@alice");
    (expect* opsRewrite).is("<@999888777>");
  });
});
