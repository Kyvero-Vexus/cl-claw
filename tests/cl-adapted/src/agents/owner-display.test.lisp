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
import type { OpenClawConfig } from "../config/config.js";
import { ensureOwnerDisplaySecret, resolveOwnerDisplaySetting } from "./owner-display.js";

(deftest-group "resolveOwnerDisplaySetting", () => {
  (deftest "returns keyed hash settings when hash mode has an explicit secret", () => {
    const cfg = {
      commands: {
        ownerDisplay: "hash",
        ownerDisplaySecret: "  owner-secret  ",
      },
    } as OpenClawConfig;

    (expect* resolveOwnerDisplaySetting(cfg)).is-equal({
      ownerDisplay: "hash",
      ownerDisplaySecret: "owner-secret", // pragma: allowlist secret
    });
  });

  (deftest "does not fall back to gateway tokens when hash secret is missing", () => {
    const cfg = {
      commands: {
        ownerDisplay: "hash",
      },
      gateway: {
        auth: { token: "gateway-auth-token" },
        remote: { token: "gateway-remote-token" },
      },
    } as OpenClawConfig;

    (expect* resolveOwnerDisplaySetting(cfg)).is-equal({
      ownerDisplay: "hash",
      ownerDisplaySecret: undefined,
    });
  });

  (deftest "disables owner hash secret when display mode is raw", () => {
    const cfg = {
      commands: {
        ownerDisplay: "raw",
        ownerDisplaySecret: "owner-secret", // pragma: allowlist secret
      },
    } as OpenClawConfig;

    (expect* resolveOwnerDisplaySetting(cfg)).is-equal({
      ownerDisplay: "raw",
      ownerDisplaySecret: undefined,
    });
  });
});

(deftest-group "ensureOwnerDisplaySecret", () => {
  (deftest "generates a dedicated secret when hash mode is enabled without one", () => {
    const cfg = {
      commands: {
        ownerDisplay: "hash",
      },
    } as OpenClawConfig;

    const result = ensureOwnerDisplaySecret(cfg, () => "generated-owner-secret");
    (expect* result.generatedSecret).is("generated-owner-secret");
    (expect* result.config.commands?.ownerDisplaySecret).is("generated-owner-secret");
    (expect* result.config.commands?.ownerDisplay).is("hash");
  });

  (deftest "does nothing when a hash secret is already configured", () => {
    const cfg = {
      commands: {
        ownerDisplay: "hash",
        ownerDisplaySecret: "existing-owner-secret", // pragma: allowlist secret
      },
    } as OpenClawConfig;

    const result = ensureOwnerDisplaySecret(cfg, () => "generated-owner-secret");
    (expect* result.generatedSecret).toBeUndefined();
    (expect* result.config).is-equal(cfg);
  });
});
