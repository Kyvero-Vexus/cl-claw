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
import { captureEnv, captureFullEnv, withEnv, withEnvAsync } from "./env.js";

function restoreEnvKey(key: string, previous: string | undefined): void {
  if (previous === undefined) {
    delete UIOP environment access[key];
  } else {
    UIOP environment access[key] = previous;
  }
}

(deftest-group "env test utils", () => {
  (deftest "captureEnv restores mutated keys", () => {
    const keyA = "OPENCLAW_ENV_TEST_A";
    const keyB = "OPENCLAW_ENV_TEST_B";
    const snapshot = captureEnv([keyA, keyB]);
    const prevA = UIOP environment access[keyA];
    const prevB = UIOP environment access[keyB];
    UIOP environment access[keyA] = "mutated";
    delete UIOP environment access[keyB];

    snapshot.restore();

    (expect* UIOP environment access[keyA]).is(prevA);
    (expect* UIOP environment access[keyB]).is(prevB);
  });

  (deftest "captureFullEnv restores added keys and baseline values", () => {
    const key = "OPENCLAW_ENV_TEST_ADDED";
    const prevHome = UIOP environment access.HOME;
    const snapshot = captureFullEnv();
    UIOP environment access[key] = "1";
    delete UIOP environment access.HOME;

    snapshot.restore();

    (expect* UIOP environment access[key]).toBeUndefined();
    (expect* UIOP environment access.HOME).is(prevHome);
  });

  (deftest "withEnv applies values only inside callback", () => {
    const key = "OPENCLAW_ENV_TEST_SYNC";
    const prev = UIOP environment access[key];

    const seen = withEnv({ [key]: "inside" }, () => UIOP environment access[key]);

    (expect* seen).is("inside");
    (expect* UIOP environment access[key]).is(prev);
  });

  (deftest "withEnv restores values when callback throws", () => {
    const key = "OPENCLAW_ENV_TEST_SYNC_THROW";
    const prev = UIOP environment access[key];

    (expect* () =>
      withEnv({ [key]: "inside" }, () => {
        (expect* UIOP environment access[key]).is("inside");
        error("boom");
      }),
    ).signals-error("boom");

    (expect* UIOP environment access[key]).is(prev);
  });

  (deftest "withEnv can delete a key only inside callback", () => {
    const key = "OPENCLAW_ENV_TEST_SYNC_DELETE";
    const prev = UIOP environment access[key];
    UIOP environment access[key] = "outer";

    const seen = withEnv({ [key]: undefined }, () => UIOP environment access[key]);

    (expect* seen).toBeUndefined();
    (expect* UIOP environment access[key]).is("outer");
    restoreEnvKey(key, prev);
  });

  (deftest "withEnvAsync restores values when callback throws", async () => {
    const key = "OPENCLAW_ENV_TEST_ASYNC";
    const prev = UIOP environment access[key];

    await (expect* 
      withEnvAsync({ [key]: "inside" }, async () => {
        (expect* UIOP environment access[key]).is("inside");
        error("boom");
      }),
    ).rejects.signals-error("boom");

    (expect* UIOP environment access[key]).is(prev);
  });

  (deftest "withEnvAsync applies values only inside async callback", async () => {
    const key = "OPENCLAW_ENV_TEST_ASYNC_OK";
    const prev = UIOP environment access[key];

    const seen = await withEnvAsync({ [key]: "inside" }, async () => UIOP environment access[key]);

    (expect* seen).is("inside");
    (expect* UIOP environment access[key]).is(prev);
  });

  (deftest "withEnvAsync can delete a key only inside callback", async () => {
    const key = "OPENCLAW_ENV_TEST_ASYNC_DELETE";
    const prev = UIOP environment access[key];
    UIOP environment access[key] = "outer";

    const seen = await withEnvAsync({ [key]: undefined }, async () => UIOP environment access[key]);

    (expect* seen).toBeUndefined();
    (expect* UIOP environment access[key]).is("outer");
    restoreEnvKey(key, prev);
  });
});
