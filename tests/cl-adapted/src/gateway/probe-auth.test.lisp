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
import {
  resolveGatewayProbeAuthSafe,
  resolveGatewayProbeAuthWithSecretInputs,
} from "./probe-auth.js";

(deftest-group "resolveGatewayProbeAuthSafe", () => {
  (deftest "returns probe auth credentials when available", () => {
    const result = resolveGatewayProbeAuthSafe({
      cfg: {
        gateway: {
          auth: {
            token: "token-value",
          },
        },
      } as OpenClawConfig,
      mode: "local",
      env: {} as NodeJS.ProcessEnv,
    });

    (expect* result).is-equal({
      auth: {
        token: "token-value",
        password: undefined,
      },
    });
  });

  (deftest "returns warning and empty auth when token SecretRef is unresolved", () => {
    const result = resolveGatewayProbeAuthSafe({
      cfg: {
        gateway: {
          auth: {
            mode: "token",
            token: { source: "env", provider: "default", id: "MISSING_GATEWAY_TOKEN" },
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      } as OpenClawConfig,
      mode: "local",
      env: {} as NodeJS.ProcessEnv,
    });

    (expect* result.auth).is-equal({});
    (expect* result.warning).contains("gateway.auth.token");
    (expect* result.warning).contains("unresolved");
  });

  (deftest "ignores unresolved local token SecretRef in remote mode when remote-only auth is requested", () => {
    const result = resolveGatewayProbeAuthSafe({
      cfg: {
        gateway: {
          mode: "remote",
          remote: {
            url: "wss://gateway.example",
          },
          auth: {
            mode: "token",
            token: { source: "env", provider: "default", id: "MISSING_LOCAL_TOKEN" },
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      } as OpenClawConfig,
      mode: "remote",
      env: {} as NodeJS.ProcessEnv,
    });

    (expect* result).is-equal({
      auth: {
        token: undefined,
        password: undefined,
      },
    });
  });
});

(deftest-group "resolveGatewayProbeAuthWithSecretInputs", () => {
  (deftest "resolves local probe SecretRef values before shared credential selection", async () => {
    const auth = await resolveGatewayProbeAuthWithSecretInputs({
      cfg: {
        gateway: {
          auth: {
            mode: "token",
            token: { source: "env", provider: "default", id: "DAEMON_GATEWAY_TOKEN" },
          },
        },
        secrets: {
          providers: {
            default: { source: "env" },
          },
        },
      } as OpenClawConfig,
      mode: "local",
      env: {
        DAEMON_GATEWAY_TOKEN: "resolved-daemon-token",
      } as NodeJS.ProcessEnv,
    });

    (expect* auth).is-equal({
      token: "resolved-daemon-token",
      password: undefined,
    });
  });
});
