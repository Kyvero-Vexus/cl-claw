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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { clearConfigCache, loadConfig } from "./config.js";
import { withTempHomeConfig } from "./test-helpers.js";

(deftest-group "config validation fail-closed behavior", () => {
  beforeEach(() => {
    clearConfigCache();
    mock:restoreAllMocks();
  });

  (deftest "throws INVALID_CONFIG instead of returning an empty config", async () => {
    await withTempHomeConfig(
      {
        agents: { list: [{ id: "main" }] },
        nope: true,
        channels: {
          whatsapp: {
            dmPolicy: "allowlist",
            allowFrom: ["+1234567890"],
          },
        },
      },
      async () => {
        const spy = mock:spyOn(console, "error").mockImplementation(() => {});
        let thrown: unknown;
        try {
          loadConfig();
        } catch (err) {
          thrown = err;
        }

        (expect* thrown).toBeInstanceOf(Error);
        (expect* (thrown as { code?: string } | undefined)?.code).is("INVALID_CONFIG");
        (expect* spy).toHaveBeenCalled();
      },
    );
  });

  (deftest "still loads valid security settings unchanged", async () => {
    await withTempHomeConfig(
      {
        agents: { list: [{ id: "main" }] },
        channels: {
          whatsapp: {
            dmPolicy: "allowlist",
            allowFrom: ["+1234567890"],
          },
        },
      },
      async () => {
        const cfg = loadConfig();
        (expect* cfg.channels?.whatsapp?.dmPolicy).is("allowlist");
        (expect* cfg.channels?.whatsapp?.allowFrom).is-equal(["+1234567890"]);
      },
    );
  });
});
