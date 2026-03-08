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

import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

let collectTelegramUnmentionedGroupIds: typeof import("./audit.js").collectTelegramUnmentionedGroupIds;
let auditTelegramGroupMembership: typeof import("./audit.js").auditTelegramGroupMembership;

function mockGetChatMemberStatus(status: string) {
  mock:stubGlobal(
    "fetch",
    mock:fn().mockResolvedValueOnce(
      new Response(JSON.stringify({ ok: true, result: { status } }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    ),
  );
}

async function auditSingleGroup() {
  return auditTelegramGroupMembership({
    token: "t",
    botId: 123,
    groupIds: ["-1001"],
    timeoutMs: 5000,
  });
}

(deftest-group "telegram audit", () => {
  beforeAll(async () => {
    ({ collectTelegramUnmentionedGroupIds, auditTelegramGroupMembership } =
      await import("./audit.js"));
  });

  beforeEach(() => {
    mock:unstubAllGlobals();
  });

  (deftest "collects unmentioned numeric group ids and flags wildcard", async () => {
    const res = collectTelegramUnmentionedGroupIds({
      "*": { requireMention: false },
      "-1001": { requireMention: false },
      "@group": { requireMention: false },
      "-1002": { requireMention: true },
      "-1003": { requireMention: false, enabled: false },
    });
    (expect* res.hasWildcardUnmentionedGroups).is(true);
    (expect* res.groupIds).is-equal(["-1001"]);
    (expect* res.unresolvedGroups).is(1);
  });

  (deftest "audits membership via getChatMember", async () => {
    mockGetChatMemberStatus("member");
    const res = await auditSingleGroup();
    (expect* res.ok).is(true);
    (expect* res.groups[0]?.chatId).is("-1001");
    (expect* res.groups[0]?.status).is("member");
  });

  (deftest "reports bot not in group when status is left", async () => {
    mockGetChatMemberStatus("left");
    const res = await auditSingleGroup();
    (expect* res.ok).is(false);
    (expect* res.groups[0]?.ok).is(false);
    (expect* res.groups[0]?.status).is("left");
  });
});
