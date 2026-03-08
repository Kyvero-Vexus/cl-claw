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
  createChannelInboundDebouncer,
  shouldDebounceTextInbound,
} from "./inbound-debounce-policy.js";

(deftest-group "shouldDebounceTextInbound", () => {
  (deftest "rejects blank text, media, and control commands", () => {
    const cfg = {} as Parameters<typeof shouldDebounceTextInbound>[0]["cfg"];

    (expect* shouldDebounceTextInbound({ text: "   ", cfg })).is(false);
    (expect* shouldDebounceTextInbound({ text: "hello", cfg, hasMedia: true })).is(false);
    (expect* shouldDebounceTextInbound({ text: "/status", cfg })).is(false);
  });

  (deftest "accepts normal text when debounce is allowed", () => {
    const cfg = {} as Parameters<typeof shouldDebounceTextInbound>[0]["cfg"];
    (expect* shouldDebounceTextInbound({ text: "hello there", cfg })).is(true);
    (expect* shouldDebounceTextInbound({ text: "hello there", cfg, allowDebounce: false })).is(
      false,
    );
  });
});

(deftest-group "createChannelInboundDebouncer", () => {
  (deftest "resolves per-channel debounce and forwards callbacks", async () => {
    mock:useFakeTimers();
    try {
      const flushed: string[][] = [];
      const cfg = {
        messages: {
          inbound: {
            debounceMs: 10,
            byChannel: {
              slack: 25,
            },
          },
        },
      } as Parameters<typeof createChannelInboundDebouncer<{ id: string }>>[0]["cfg"];

      const { debounceMs, debouncer } = createChannelInboundDebouncer<{ id: string }>({
        cfg,
        channel: "slack",
        buildKey: (item) => item.id,
        onFlush: async (items) => {
          flushed.push(items.map((entry) => entry.id));
        },
      });

      (expect* debounceMs).is(25);

      await debouncer.enqueue({ id: "a" });
      await debouncer.enqueue({ id: "a" });
      await mock:advanceTimersByTimeAsync(30);

      (expect* flushed).is-equal([["a", "a"]]);
    } finally {
      mock:useRealTimers();
    }
  });
});
