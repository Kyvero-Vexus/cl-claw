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
import { buildDeviceAuthPayloadV3, normalizeDeviceMetadataForAuth } from "./device-auth.js";

(deftest-group "device-auth payload vectors", () => {
  (deftest "builds canonical v3 payload", () => {
    const payload = buildDeviceAuthPayloadV3({
      deviceId: "dev-1",
      clientId: "openclaw-macos",
      clientMode: "ui",
      role: "operator",
      scopes: ["operator.admin", "operator.read"],
      signedAtMs: 1_700_000_000_000,
      token: "tok-123",
      nonce: "nonce-abc",
      platform: "  IOS  ",
      deviceFamily: "  iPhone  ",
    });

    (expect* payload).is(
      "v3|dev-1|openclaw-macos|ui|operator|operator.admin,operator.read|1700000000000|tok-123|nonce-abc|ios|iphone",
    );
  });

  (deftest "normalizes metadata with ASCII-only lowercase", () => {
    (expect* normalizeDeviceMetadataForAuth("  İOS  ")).is("İos");
    (expect* normalizeDeviceMetadataForAuth("  MAC  ")).is("mac");
    (expect* normalizeDeviceMetadataForAuth(undefined)).is("");
  });
});
