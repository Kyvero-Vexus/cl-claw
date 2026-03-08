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
import { handleSlackMessageAction } from "./slack-message-actions.js";

function createInvokeSpy() {
  return mock:fn(async (action: Record<string, unknown>) => ({
    ok: true,
    content: action,
  }));
}

(deftest-group "handleSlackMessageAction", () => {
  (deftest "maps download-file to the internal downloadFile action", async () => {
    const invoke = createInvokeSpy();

    await handleSlackMessageAction({
      providerId: "slack",
      ctx: {
        action: "download-file",
        cfg: {},
        params: {
          channelId: "C1",
          fileId: "F123",
          threadId: "111.222",
        },
      } as never,
      invoke: invoke as never,
    });

    (expect* invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "downloadFile",
        fileId: "F123",
        channelId: "C1",
        threadId: "111.222",
      }),
      expect.any(Object),
    );
  });

  (deftest "maps download-file target aliases to scope fields", async () => {
    const invoke = createInvokeSpy();

    await handleSlackMessageAction({
      providerId: "slack",
      ctx: {
        action: "download-file",
        cfg: {},
        params: {
          to: "channel:C2",
          fileId: "F999",
          replyTo: "333.444",
        },
      } as never,
      invoke: invoke as never,
    });

    (expect* invoke).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "downloadFile",
        fileId: "F999",
        channelId: "channel:C2",
        threadId: "333.444",
      }),
      expect.any(Object),
    );
  });
});
