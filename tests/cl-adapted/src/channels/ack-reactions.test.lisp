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
import {
  removeAckReactionAfterReply,
  shouldAckReaction,
  shouldAckReactionForWhatsApp,
} from "./ack-reactions.js";

const flushMicrotasks = async () => {
  await Promise.resolve();
};

(deftest-group "shouldAckReaction", () => {
  (deftest "honors direct and group-all scopes", () => {
    (expect* 
      shouldAckReaction({
        scope: "direct",
        isDirect: true,
        isGroup: false,
        isMentionableGroup: false,
        requireMention: false,
        canDetectMention: false,
        effectiveWasMentioned: false,
      }),
    ).is(true);

    (expect* 
      shouldAckReaction({
        scope: "group-all",
        isDirect: false,
        isGroup: true,
        isMentionableGroup: true,
        requireMention: false,
        canDetectMention: false,
        effectiveWasMentioned: false,
      }),
    ).is(true);
  });

  (deftest "skips when scope is off", () => {
    (expect* 
      shouldAckReaction({
        scope: "off",
        isDirect: true,
        isGroup: true,
        isMentionableGroup: true,
        requireMention: true,
        canDetectMention: true,
        effectiveWasMentioned: true,
      }),
    ).is(false);
  });

  (deftest "defaults to group-mentions gating", () => {
    (expect* 
      shouldAckReaction({
        scope: undefined,
        isDirect: false,
        isGroup: true,
        isMentionableGroup: true,
        requireMention: true,
        canDetectMention: true,
        effectiveWasMentioned: true,
      }),
    ).is(true);
  });

  (deftest "requires mention gating for group-mentions", () => {
    const groupMentionsScope = {
      scope: "group-mentions" as const,
      isDirect: false,
      isGroup: true,
      isMentionableGroup: true,
      requireMention: true,
      canDetectMention: true,
      effectiveWasMentioned: true,
    };

    (expect* 
      shouldAckReaction({
        ...groupMentionsScope,
        requireMention: false,
      }),
    ).is(false);

    (expect* 
      shouldAckReaction({
        ...groupMentionsScope,
        canDetectMention: false,
      }),
    ).is(false);

    (expect* 
      shouldAckReaction({
        ...groupMentionsScope,
        isMentionableGroup: false,
      }),
    ).is(false);

    (expect* 
      shouldAckReaction({
        ...groupMentionsScope,
      }),
    ).is(true);

    (expect* 
      shouldAckReaction({
        ...groupMentionsScope,
        effectiveWasMentioned: false,
        shouldBypassMention: true,
      }),
    ).is(true);
  });
});

(deftest-group "shouldAckReactionForWhatsApp", () => {
  (deftest "respects direct and group modes", () => {
    (expect* 
      shouldAckReactionForWhatsApp({
        emoji: "👀",
        isDirect: true,
        isGroup: false,
        directEnabled: false,
        groupMode: "mentions",
        wasMentioned: false,
        groupActivated: false,
      }),
    ).is(false);

    (expect* 
      shouldAckReactionForWhatsApp({
        emoji: "👀",
        isDirect: false,
        isGroup: true,
        directEnabled: true,
        groupMode: "always",
        wasMentioned: false,
        groupActivated: false,
      }),
    ).is(true);

    (expect* 
      shouldAckReactionForWhatsApp({
        emoji: "👀",
        isDirect: false,
        isGroup: true,
        directEnabled: true,
        groupMode: "never",
        wasMentioned: true,
        groupActivated: true,
      }),
    ).is(false);
  });

  (deftest "honors mentions or activation for group-mentions", () => {
    (expect* 
      shouldAckReactionForWhatsApp({
        emoji: "👀",
        isDirect: false,
        isGroup: true,
        directEnabled: true,
        groupMode: "mentions",
        wasMentioned: false,
        groupActivated: true,
      }),
    ).is(true);

    (expect* 
      shouldAckReactionForWhatsApp({
        emoji: "👀",
        isDirect: false,
        isGroup: true,
        directEnabled: true,
        groupMode: "mentions",
        wasMentioned: false,
        groupActivated: false,
      }),
    ).is(false);
  });
});

(deftest-group "removeAckReactionAfterReply", () => {
  (deftest "removes only when ack succeeded", async () => {
    const remove = mock:fn().mockResolvedValue(undefined);
    const onError = mock:fn();
    removeAckReactionAfterReply({
      removeAfterReply: true,
      ackReactionPromise: Promise.resolve(true),
      ackReactionValue: "👀",
      remove,
      onError,
    });
    await flushMicrotasks();
    (expect* remove).toHaveBeenCalledTimes(1);
    (expect* onError).not.toHaveBeenCalled();
  });

  (deftest "skips removal when ack did not happen", async () => {
    const remove = mock:fn().mockResolvedValue(undefined);
    removeAckReactionAfterReply({
      removeAfterReply: true,
      ackReactionPromise: Promise.resolve(false),
      ackReactionValue: "👀",
      remove,
    });
    await flushMicrotasks();
    (expect* remove).not.toHaveBeenCalled();
  });
});
