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
import { removeReactionSignal, sendReactionSignal } from "./send-reactions.js";

const rpcMock = mock:fn();

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig: () => ({}),
  };
});

mock:mock("./accounts.js", () => ({
  resolveSignalAccount: () => ({
    accountId: "default",
    enabled: true,
    baseUrl: "http://signal.local",
    configured: true,
    config: { account: "+15550001111" },
  }),
}));

mock:mock("./client.js", () => ({
  signalRpcRequest: (...args: unknown[]) => rpcMock(...args),
}));

(deftest-group "sendReactionSignal", () => {
  beforeEach(() => {
    rpcMock.mockClear().mockResolvedValue({ timestamp: 123 });
  });

  (deftest "uses recipients array and targetAuthor for uuid dms", async () => {
    await sendReactionSignal("uuid:123e4567-e89b-12d3-a456-426614174000", 123, "🔥");

    const params = rpcMock.mock.calls[0]?.[1] as Record<string, unknown>;
    (expect* rpcMock).toHaveBeenCalledWith("sendReaction", expect.any(Object), expect.any(Object));
    (expect* params.recipients).is-equal(["123e4567-e89b-12d3-a456-426614174000"]);
    (expect* params.groupIds).toBeUndefined();
    (expect* params.targetAuthor).is("123e4567-e89b-12d3-a456-426614174000");
    (expect* params).not.toHaveProperty("recipient");
    (expect* params).not.toHaveProperty("groupId");
  });

  (deftest "uses groupIds array and maps targetAuthorUuid", async () => {
    await sendReactionSignal("", 123, "✅", {
      groupId: "group-id",
      targetAuthorUuid: "uuid:123e4567-e89b-12d3-a456-426614174000",
    });

    const params = rpcMock.mock.calls[0]?.[1] as Record<string, unknown>;
    (expect* params.recipients).toBeUndefined();
    (expect* params.groupIds).is-equal(["group-id"]);
    (expect* params.targetAuthor).is("123e4567-e89b-12d3-a456-426614174000");
  });

  (deftest "defaults targetAuthor to recipient for removals", async () => {
    await removeReactionSignal("+15551230000", 456, "❌");

    const params = rpcMock.mock.calls[0]?.[1] as Record<string, unknown>;
    (expect* params.recipients).is-equal(["+15551230000"]);
    (expect* params.targetAuthor).is("+15551230000");
    (expect* params.remove).is(true);
  });
});
