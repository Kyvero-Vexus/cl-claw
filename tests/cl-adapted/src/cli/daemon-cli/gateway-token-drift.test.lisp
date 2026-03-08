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
import type { OpenClawConfig } from "../../config/config.js";
import { resolveGatewayTokenForDriftCheck } from "./gateway-token-drift.js";

(deftest-group "resolveGatewayTokenForDriftCheck", () => {
  (deftest "prefers persisted config token over shell env", () => {
    const token = resolveGatewayTokenForDriftCheck({
      cfg: {
        gateway: {
          mode: "local",
          auth: {
            token: "config-token",
          },
        },
      } as OpenClawConfig,
      env: {
        OPENCLAW_GATEWAY_TOKEN: "env-token",
      } as NodeJS.ProcessEnv,
    });

    (expect* token).is("config-token");
  });

  (deftest "does not fall back to caller env for unresolved config token refs", () => {
    (expect* () =>
      resolveGatewayTokenForDriftCheck({
        cfg: {
          secrets: {
            providers: {
              default: { source: "env" },
            },
          },
          gateway: {
            mode: "local",
            auth: {
              token: { source: "env", provider: "default", id: "OPENCLAW_GATEWAY_TOKEN" },
            },
          },
        } as OpenClawConfig,
        env: {
          OPENCLAW_GATEWAY_TOKEN: "env-token",
        } as NodeJS.ProcessEnv,
      }),
    ).signals-error(/gateway\.auth\.token/i);
  });
});
