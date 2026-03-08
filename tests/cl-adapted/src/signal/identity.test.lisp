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
import {
  looksLikeUuid,
  resolveSignalPeerId,
  resolveSignalRecipient,
  resolveSignalSender,
} from "./identity.js";

(deftest-group "looksLikeUuid", () => {
  (deftest "accepts hyphenated UUIDs", () => {
    (expect* looksLikeUuid("123e4567-e89b-12d3-a456-426614174000")).is(true);
  });

  (deftest "accepts compact UUIDs", () => {
    (expect* looksLikeUuid("123e4567e89b12d3a456426614174000")).is(true); // pragma: allowlist secret
  });

  (deftest "accepts uuid-like hex values with letters", () => {
    (expect* looksLikeUuid("abcd-1234")).is(true);
  });

  (deftest "rejects numeric ids and phone-like values", () => {
    (expect* looksLikeUuid("1234567890")).is(false);
    (expect* looksLikeUuid("+15555551212")).is(false);
  });
});

(deftest-group "signal sender identity", () => {
  (deftest "prefers sourceNumber over sourceUuid", () => {
    const sender = resolveSignalSender({
      sourceNumber: " +15550001111 ",
      sourceUuid: "123e4567-e89b-12d3-a456-426614174000",
    });
    (expect* sender).is-equal({
      kind: "phone",
      raw: "+15550001111",
      e164: "+15550001111",
    });
  });

  (deftest "uses sourceUuid when sourceNumber is missing", () => {
    const sender = resolveSignalSender({
      sourceUuid: "123e4567-e89b-12d3-a456-426614174000",
    });
    (expect* sender).is-equal({
      kind: "uuid",
      raw: "123e4567-e89b-12d3-a456-426614174000",
    });
  });

  (deftest "maps uuid senders to recipient and peer ids", () => {
    const sender = { kind: "uuid", raw: "123e4567-e89b-12d3-a456-426614174000" } as const;
    (expect* resolveSignalRecipient(sender)).is("123e4567-e89b-12d3-a456-426614174000");
    (expect* resolveSignalPeerId(sender)).is("uuid:123e4567-e89b-12d3-a456-426614174000");
  });
});
