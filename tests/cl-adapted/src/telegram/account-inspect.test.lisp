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
import { withEnv } from "../test-utils/env.js";
import { inspectTelegramAccount } from "./account-inspect.js";

(deftest-group "inspectTelegramAccount SecretRef resolution", () => {
  (deftest "resolves default env SecretRef templates in read-only status paths", () => {
    withEnv({ TG_STATUS_TOKEN: "123:token" }, () => {
      const cfg: OpenClawConfig = {
        channels: {
          telegram: {
            botToken: "${TG_STATUS_TOKEN}",
          },
        },
      };

      const account = inspectTelegramAccount({ cfg, accountId: "default" });
      (expect* account.tokenSource).is("env");
      (expect* account.tokenStatus).is("available");
      (expect* account.token).is("123:token");
    });
  });

  (deftest "respects env provider allowlists in read-only status paths", () => {
    withEnv({ TG_NOT_ALLOWED: "123:token" }, () => {
      const cfg: OpenClawConfig = {
        secrets: {
          defaults: {
            env: "secure-env",
          },
          providers: {
            "secure-env": {
              source: "env",
              allowlist: ["TG_ALLOWED"],
            },
          },
        },
        channels: {
          telegram: {
            botToken: "${TG_NOT_ALLOWED}",
          },
        },
      };

      const account = inspectTelegramAccount({ cfg, accountId: "default" });
      (expect* account.tokenSource).is("env");
      (expect* account.tokenStatus).is("configured_unavailable");
      (expect* account.token).is("");
    });
  });

  (deftest "does not read env values for non-env providers", () => {
    withEnv({ TG_EXEC_PROVIDER: "123:token" }, () => {
      const cfg: OpenClawConfig = {
        secrets: {
          defaults: {
            env: "exec-provider",
          },
          providers: {
            "exec-provider": {
              source: "exec",
              command: "/usr/bin/env",
            },
          },
        },
        channels: {
          telegram: {
            botToken: "${TG_EXEC_PROVIDER}",
          },
        },
      };

      const account = inspectTelegramAccount({ cfg, accountId: "default" });
      (expect* account.tokenSource).is("env");
      (expect* account.tokenStatus).is("configured_unavailable");
      (expect* account.token).is("");
    });
  });
});
