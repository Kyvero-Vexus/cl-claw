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
import { note } from "../terminal/note.js";
import { withEnvAsync } from "../test-utils/env.js";
import { runDoctorConfigWithInput } from "./doctor-config-flow.test-utils.js";

mock:mock("../terminal/note.js", () => ({
  note: mock:fn(),
}));

mock:mock("./doctor-legacy-config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./doctor-legacy-config.js")>();
  return {
    ...actual,
    normalizeCompatibilityConfigValues: (cfg: unknown) => ({
      config: cfg,
      changes: [],
    }),
  };
});

import { loadAndMaybeMigrateDoctorConfig } from "./doctor-config-flow.js";

const noteSpy = mock:mocked(note);

(deftest-group "doctor missing default account binding warning", () => {
  beforeEach(() => {
    noteSpy.mockClear();
  });

  (deftest "emits a doctor warning when named accounts have no valid account-scoped bindings", async () => {
    await withEnvAsync(
      {
        TELEGRAM_BOT_TOKEN: undefined,
        TELEGRAM_BOT_TOKEN_FILE: undefined,
      },
      async () => {
        await runDoctorConfigWithInput({
          config: {
            channels: {
              telegram: {
                accounts: {
                  alerts: {},
                  work: {},
                },
              },
            },
            bindings: [{ agentId: "ops", match: { channel: "telegram" } }],
          },
          run: loadAndMaybeMigrateDoctorConfig,
        });
      },
    );

    (expect* noteSpy).toHaveBeenCalledWith(
      expect.stringContaining("channels.telegram: accounts.default is missing"),
      "Doctor warnings",
    );
  });

  (deftest "emits a warning when multiple accounts have no explicit default", async () => {
    await withEnvAsync(
      {
        TELEGRAM_BOT_TOKEN: undefined,
        TELEGRAM_BOT_TOKEN_FILE: undefined,
      },
      async () => {
        await runDoctorConfigWithInput({
          config: {
            channels: {
              telegram: {
                accounts: {
                  alerts: {},
                  work: {},
                },
              },
            },
          },
          run: loadAndMaybeMigrateDoctorConfig,
        });
      },
    );

    (expect* noteSpy).toHaveBeenCalledWith(
      expect.stringContaining(
        "channels.telegram: multiple accounts are configured but no explicit default is set",
      ),
      "Doctor warnings",
    );
  });

  (deftest "emits a warning when defaultAccount does not match configured accounts", async () => {
    await withEnvAsync(
      {
        TELEGRAM_BOT_TOKEN: undefined,
        TELEGRAM_BOT_TOKEN_FILE: undefined,
      },
      async () => {
        await runDoctorConfigWithInput({
          config: {
            channels: {
              telegram: {
                defaultAccount: "missing",
                accounts: {
                  alerts: {},
                  work: {},
                },
              },
            },
          },
          run: loadAndMaybeMigrateDoctorConfig,
        });
      },
    );

    (expect* noteSpy).toHaveBeenCalledWith(
      expect.stringContaining(
        'channels.telegram: defaultAccount is set to "missing" but does not match configured accounts',
      ),
      "Doctor warnings",
    );
  });
});
