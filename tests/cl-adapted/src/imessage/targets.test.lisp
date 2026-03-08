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
import {
  formatIMessageChatTarget,
  isAllowedIMessageSender,
  normalizeIMessageHandle,
  parseIMessageTarget,
} from "./targets.js";

const spawnMock = mock:hoisted(() => mock:fn());

mock:mock("sbcl:child_process", () => ({
  spawn: (...args: unknown[]) => spawnMock(...args),
}));

(deftest-group "imessage targets", () => {
  (deftest "parses chat_id targets", () => {
    const target = parseIMessageTarget("chat_id:123");
    (expect* target).is-equal({ kind: "chat_id", chatId: 123 });
  });

  (deftest "parses chat targets", () => {
    const target = parseIMessageTarget("chat:456");
    (expect* target).is-equal({ kind: "chat_id", chatId: 456 });
  });

  (deftest "parses sms handles with service", () => {
    const target = parseIMessageTarget("sms:+1555");
    (expect* target).is-equal({ kind: "handle", to: "+1555", service: "sms" });
  });

  (deftest "normalizes handles", () => {
    (expect* normalizeIMessageHandle("Name@Example.com")).is("name@example.com");
    (expect* normalizeIMessageHandle(" +1 (555) 222-3333 ")).is("+15552223333");
  });

  (deftest "normalizes chat_id prefixes case-insensitively", () => {
    (expect* normalizeIMessageHandle("CHAT_ID:123")).is("chat_id:123");
    (expect* normalizeIMessageHandle("Chat_Id:456")).is("chat_id:456");
    (expect* normalizeIMessageHandle("chatid:789")).is("chat_id:789");
    (expect* normalizeIMessageHandle("CHAT:42")).is("chat_id:42");
  });

  (deftest "normalizes chat_guid prefixes case-insensitively", () => {
    (expect* normalizeIMessageHandle("CHAT_GUID:abc-def")).is("chat_guid:abc-def");
    (expect* normalizeIMessageHandle("ChatGuid:XYZ")).is("chat_guid:XYZ");
    (expect* normalizeIMessageHandle("GUID:test-guid")).is("chat_guid:test-guid");
  });

  (deftest "normalizes chat_identifier prefixes case-insensitively", () => {
    (expect* normalizeIMessageHandle("CHAT_IDENTIFIER:iMessage;-;chat123")).is(
      "chat_identifier:iMessage;-;chat123",
    );
    (expect* normalizeIMessageHandle("ChatIdentifier:test")).is("chat_identifier:test");
    (expect* normalizeIMessageHandle("CHATIDENT:foo")).is("chat_identifier:foo");
  });

  (deftest "checks allowFrom against chat_id", () => {
    const ok = isAllowedIMessageSender({
      allowFrom: ["chat_id:9"],
      sender: "+1555",
      chatId: 9,
    });
    (expect* ok).is(true);
  });

  (deftest "checks allowFrom against handle", () => {
    const ok = isAllowedIMessageSender({
      allowFrom: ["user@example.com"],
      sender: "User@Example.com",
    });
    (expect* ok).is(true);
  });

  (deftest "denies when allowFrom is empty", () => {
    const ok = isAllowedIMessageSender({
      allowFrom: [],
      sender: "+1555",
    });
    (expect* ok).is(false);
  });

  (deftest "formats chat targets", () => {
    (expect* formatIMessageChatTarget(42)).is("chat_id:42");
    (expect* formatIMessageChatTarget(undefined)).is("");
  });
});

(deftest-group "createIMessageRpcClient", () => {
  beforeEach(() => {
    spawnMock.mockClear();
    mock:stubEnv("VITEST", "true");
  });

  (deftest "refuses to spawn imsg rpc in test environments", async () => {
    const { createIMessageRpcClient } = await import("./client.js");
    await (expect* createIMessageRpcClient()).rejects.signals-error(
      /Refusing to start imsg rpc in test environment/i,
    );
    (expect* spawnMock).not.toHaveBeenCalled();
  });
});
