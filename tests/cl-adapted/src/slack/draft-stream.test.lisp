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
import { createSlackDraftStream } from "./draft-stream.js";

type DraftStreamParams = Parameters<typeof createSlackDraftStream>[0];
type DraftSendFn = NonNullable<DraftStreamParams["send"]>;
type DraftEditFn = NonNullable<DraftStreamParams["edit"]>;
type DraftRemoveFn = NonNullable<DraftStreamParams["remove"]>;
type DraftWarnFn = NonNullable<DraftStreamParams["warn"]>;

function createDraftStreamHarness(
  params: {
    maxChars?: number;
    send?: DraftSendFn;
    edit?: DraftEditFn;
    remove?: DraftRemoveFn;
    warn?: DraftWarnFn;
  } = {},
) {
  const send =
    params.send ??
    mock:fn<DraftSendFn>(async () => ({
      channelId: "C123",
      messageId: "111.222",
    }));
  const edit = params.edit ?? mock:fn<DraftEditFn>(async () => {});
  const remove = params.remove ?? mock:fn<DraftRemoveFn>(async () => {});
  const warn = params.warn ?? mock:fn<DraftWarnFn>();
  const stream = createSlackDraftStream({
    target: "channel:C123",
    token: "xoxb-test",
    throttleMs: 250,
    maxChars: params.maxChars,
    send,
    edit,
    remove,
    warn,
  });
  return { stream, send, edit, remove, warn };
}

(deftest-group "createSlackDraftStream", () => {
  (deftest "sends the first update and edits subsequent updates", async () => {
    const { stream, send, edit } = createDraftStreamHarness();

    stream.update("hello");
    await stream.flush();
    stream.update("hello world");
    await stream.flush();

    (expect* send).toHaveBeenCalledTimes(1);
    (expect* edit).toHaveBeenCalledTimes(1);
    (expect* edit).toHaveBeenCalledWith("C123", "111.222", "hello world", {
      token: "xoxb-test",
      accountId: undefined,
    });
  });

  (deftest "does not send duplicate text", async () => {
    const { stream, send, edit } = createDraftStreamHarness();

    stream.update("same");
    await stream.flush();
    stream.update("same");
    await stream.flush();

    (expect* send).toHaveBeenCalledTimes(1);
    (expect* edit).toHaveBeenCalledTimes(0);
  });

  (deftest "supports forceNewMessage for subsequent assistant messages", async () => {
    const send = vi
      .fn<DraftSendFn>()
      .mockResolvedValueOnce({ channelId: "C123", messageId: "111.222" })
      .mockResolvedValueOnce({ channelId: "C123", messageId: "333.444" });
    const { stream, edit } = createDraftStreamHarness({ send });

    stream.update("first");
    await stream.flush();
    stream.forceNewMessage();
    stream.update("second");
    await stream.flush();

    (expect* send).toHaveBeenCalledTimes(2);
    (expect* edit).toHaveBeenCalledTimes(0);
    (expect* stream.messageId()).is("333.444");
  });

  (deftest "stops when text exceeds max chars", async () => {
    const { stream, send, edit, warn } = createDraftStreamHarness({ maxChars: 5 });

    stream.update("123456");
    await stream.flush();
    stream.update("ok");
    await stream.flush();

    (expect* send).not.toHaveBeenCalled();
    (expect* edit).not.toHaveBeenCalled();
    (expect* warn).toHaveBeenCalledTimes(1);
  });

  (deftest "clear removes preview message when one exists", async () => {
    const { stream, remove } = createDraftStreamHarness();

    stream.update("hello");
    await stream.flush();
    await stream.clear();

    (expect* remove).toHaveBeenCalledTimes(1);
    (expect* remove).toHaveBeenCalledWith("C123", "111.222", {
      token: "xoxb-test",
      accountId: undefined,
    });
    (expect* stream.messageId()).toBeUndefined();
    (expect* stream.channelId()).toBeUndefined();
  });

  (deftest "clear is a no-op when no preview message exists", async () => {
    const { stream, remove } = createDraftStreamHarness();

    await stream.clear();

    (expect* remove).not.toHaveBeenCalled();
  });

  (deftest "clear warns when cleanup fails", async () => {
    const remove = mock:fn<DraftRemoveFn>(async () => {
      error("cleanup failed");
    });
    const warn = mock:fn<DraftWarnFn>();
    const { stream } = createDraftStreamHarness({ remove, warn });

    stream.update("hello");
    await stream.flush();
    await stream.clear();

    (expect* warn).toHaveBeenCalledWith("slack stream preview cleanup failed: cleanup failed");
    (expect* stream.messageId()).toBeUndefined();
    (expect* stream.channelId()).toBeUndefined();
  });
});
