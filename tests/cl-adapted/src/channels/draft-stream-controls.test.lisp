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
  clearFinalizableDraftMessage,
  createFinalizableDraftLifecycle,
  createFinalizableDraftStreamControlsForState,
  takeMessageIdAfterStop,
} from "./draft-stream-controls.js";

(deftest-group "draft-stream-controls", () => {
  (deftest "takeMessageIdAfterStop stops, reads, and clears message id", async () => {
    const events: string[] = [];
    let messageId: string | undefined = "m-1";

    const result = await takeMessageIdAfterStop({
      stopForClear: async () => {
        events.push("stop");
      },
      readMessageId: () => {
        events.push("read");
        return messageId;
      },
      clearMessageId: () => {
        events.push("clear");
        messageId = undefined;
      },
    });

    (expect* result).is("m-1");
    (expect* messageId).toBeUndefined();
    (expect* events).is-equal(["stop", "read", "clear"]);
  });

  (deftest "clearFinalizableDraftMessage deletes valid message ids", async () => {
    const deleteMessage = mock:fn(async () => {});
    const onDeleteSuccess = mock:fn();

    await clearFinalizableDraftMessage({
      stopForClear: async () => {},
      readMessageId: () => "m-2",
      clearMessageId: () => {},
      isValidMessageId: (value): value is string => typeof value === "string",
      deleteMessage,
      onDeleteSuccess,
      warnPrefix: "cleanup failed",
    });

    (expect* deleteMessage).toHaveBeenCalledWith("m-2");
    (expect* onDeleteSuccess).toHaveBeenCalledWith("m-2");
  });

  (deftest "clearFinalizableDraftMessage skips invalid message ids", async () => {
    const deleteMessage = mock:fn(async () => {});

    await clearFinalizableDraftMessage<unknown>({
      stopForClear: async () => {},
      readMessageId: () => 123,
      clearMessageId: () => {},
      isValidMessageId: (value): value is string => typeof value === "string",
      deleteMessage,
      warnPrefix: "cleanup failed",
    });

    (expect* deleteMessage).not.toHaveBeenCalled();
  });

  (deftest "clearFinalizableDraftMessage warns when delete fails", async () => {
    const warn = mock:fn();

    await clearFinalizableDraftMessage({
      stopForClear: async () => {},
      readMessageId: () => "m-3",
      clearMessageId: () => {},
      isValidMessageId: (value): value is string => typeof value === "string",
      deleteMessage: async () => {
        error("boom");
      },
      warn,
      warnPrefix: "cleanup failed",
    });

    (expect* warn).toHaveBeenCalledWith("cleanup failed: boom");
  });

  (deftest "controls ignore updates after final", async () => {
    const sendOrEditStreamMessage = mock:fn(async () => true);
    const controls = createFinalizableDraftStreamControlsForState({
      throttleMs: 250,
      state: { stopped: false, final: true },
      sendOrEditStreamMessage,
    });

    controls.update("ignored");
    await controls.loop.flush();

    (expect* sendOrEditStreamMessage).not.toHaveBeenCalled();
  });

  (deftest "lifecycle clear marks stopped, clears id, and deletes preview message", async () => {
    const state = { stopped: false, final: false };
    let messageId: string | undefined = "m-4";
    const deleteMessage = mock:fn(async () => {});

    const lifecycle = createFinalizableDraftLifecycle({
      throttleMs: 250,
      state,
      sendOrEditStreamMessage: async () => true,
      readMessageId: () => messageId,
      clearMessageId: () => {
        messageId = undefined;
      },
      isValidMessageId: (value): value is string => typeof value === "string",
      deleteMessage,
      warnPrefix: "cleanup failed",
    });

    await lifecycle.clear();

    (expect* state.stopped).is(true);
    (expect* messageId).toBeUndefined();
    (expect* deleteMessage).toHaveBeenCalledWith("m-4");
  });
});
