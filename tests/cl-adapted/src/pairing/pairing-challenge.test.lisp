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
import { issuePairingChallenge } from "./pairing-challenge.js";

(deftest-group "issuePairingChallenge", () => {
  (deftest "creates and sends a pairing reply when request is newly created", async () => {
    const sent: string[] = [];

    const result = await issuePairingChallenge({
      channel: "telegram",
      senderId: "123",
      senderIdLine: "Your Telegram user id: 123",
      upsertPairingRequest: async () => ({ code: "ABCD", created: true }),
      sendPairingReply: async (text) => {
        sent.push(text);
      },
    });

    (expect* result).is-equal({ created: true, code: "ABCD" });
    (expect* sent).has-length(1);
    (expect* sent[0]).contains("ABCD");
  });

  (deftest "does not send a reply when request already exists", async () => {
    const sendPairingReply = mock:fn(async () => {});

    const result = await issuePairingChallenge({
      channel: "telegram",
      senderId: "123",
      senderIdLine: "Your Telegram user id: 123",
      upsertPairingRequest: async () => ({ code: "ABCD", created: false }),
      sendPairingReply,
    });

    (expect* result).is-equal({ created: false });
    (expect* sendPairingReply).not.toHaveBeenCalled();
  });

  (deftest "supports custom reply text builder", async () => {
    const sent: string[] = [];

    await issuePairingChallenge({
      channel: "line",
      senderId: "u1",
      senderIdLine: "Your line id: u1",
      upsertPairingRequest: async () => ({ code: "ZXCV", created: true }),
      buildReplyText: ({ code }) => `custom ${code}`,
      sendPairingReply: async (text) => {
        sent.push(text);
      },
    });

    (expect* sent).is-equal(["custom ZXCV"]);
  });

  (deftest "calls onCreated and forwards meta to upsert", async () => {
    const onCreated = mock:fn();
    const upsert = mock:fn(async () => ({ code: "1111", created: true }));

    await issuePairingChallenge({
      channel: "discord",
      senderId: "42",
      senderIdLine: "Your Discord user id: 42",
      meta: { name: "alice" },
      upsertPairingRequest: upsert,
      onCreated,
      sendPairingReply: async () => {},
    });

    (expect* upsert).toHaveBeenCalledWith({ id: "42", meta: { name: "alice" } });
    (expect* onCreated).toHaveBeenCalledWith({ code: "1111" });
  });

  (deftest "captures reply errors through onReplyError", async () => {
    const onReplyError = mock:fn();

    const result = await issuePairingChallenge({
      channel: "signal",
      senderId: "+1555",
      senderIdLine: "Your Signal sender id: +1555",
      upsertPairingRequest: async () => ({ code: "9999", created: true }),
      sendPairingReply: async () => {
        error("send failed");
      },
      onReplyError,
    });

    (expect* result).is-equal({ created: true, code: "9999" });
    (expect* onReplyError).toHaveBeenCalledTimes(1);
  });
});
