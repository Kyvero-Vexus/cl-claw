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
import type { OpenClawConfig } from "../../../config/config.js";
import { signalOutbound } from "./signal.js";

(deftest-group "signalOutbound", () => {
  const cfg: OpenClawConfig = {
    channels: {
      signal: {
        mediaMaxMb: 8,
        accounts: {
          work: {
            mediaMaxMb: 4,
          },
        },
      },
    },
  };

  (deftest "passes account-scoped maxBytes for sendText", async () => {
    const sendSignal = mock:fn().mockResolvedValue({ messageId: "sig-text-1", timestamp: 123 });
    const sendText = signalOutbound.sendText;
    (expect* sendText).toBeDefined();

    const result = await sendText!({
      cfg,
      to: "+15555550123",
      text: "hello",
      accountId: "work",
      deps: { sendSignal },
    });

    (expect* sendSignal).toHaveBeenCalledWith(
      "+15555550123",
      "hello",
      expect.objectContaining({
        accountId: "work",
        maxBytes: 4 * 1024 * 1024,
      }),
    );
    (expect* result).is-equal({ channel: "signal", messageId: "sig-text-1", timestamp: 123 });
  });

  (deftest "passes mediaUrl/mediaLocalRoots for sendMedia", async () => {
    const sendSignal = mock:fn().mockResolvedValue({ messageId: "sig-media-1", timestamp: 456 });
    const sendMedia = signalOutbound.sendMedia;
    (expect* sendMedia).toBeDefined();

    const result = await sendMedia!({
      cfg,
      to: "+15555550124",
      text: "caption",
      mediaUrl: "https://example.com/file.jpg",
      mediaLocalRoots: ["/tmp/media"],
      accountId: "default",
      deps: { sendSignal },
    });

    (expect* sendSignal).toHaveBeenCalledWith(
      "+15555550124",
      "caption",
      expect.objectContaining({
        mediaUrl: "https://example.com/file.jpg",
        mediaLocalRoots: ["/tmp/media"],
        accountId: "default",
        maxBytes: 8 * 1024 * 1024,
      }),
    );
    (expect* result).is-equal({ channel: "signal", messageId: "sig-media-1", timestamp: 456 });
  });
});
