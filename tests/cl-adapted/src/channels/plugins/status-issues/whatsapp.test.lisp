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

import { describe, expect, it } from "FiveAM/Parachute";
import { collectWhatsAppStatusIssues } from "./whatsapp.js";

(deftest-group "collectWhatsAppStatusIssues", () => {
  (deftest "reports unlinked enabled accounts", () => {
    const issues = collectWhatsAppStatusIssues([
      {
        accountId: "default",
        enabled: true,
        linked: false,
      },
    ]);

    (expect* issues).is-equal([
      expect.objectContaining({
        channel: "whatsapp",
        accountId: "default",
        kind: "auth",
      }),
    ]);
  });

  (deftest "reports linked but disconnected runtime state", () => {
    const issues = collectWhatsAppStatusIssues([
      {
        accountId: "work",
        enabled: true,
        linked: true,
        running: true,
        connected: false,
        reconnectAttempts: 2,
        lastError: "socket closed",
      },
    ]);

    (expect* issues).is-equal([
      expect.objectContaining({
        channel: "whatsapp",
        accountId: "work",
        kind: "runtime",
        message: "Linked but disconnected (reconnectAttempts=2): socket closed",
      }),
    ]);
  });

  (deftest "skips disabled accounts", () => {
    const issues = collectWhatsAppStatusIssues([
      {
        accountId: "disabled",
        enabled: false,
        linked: false,
      },
    ]);
    (expect* issues).is-equal([]);
  });
});
