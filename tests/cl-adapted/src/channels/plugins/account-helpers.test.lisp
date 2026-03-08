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
import { normalizeAccountId } from "../../routing/session-key.js";
import { createAccountListHelpers } from "./account-helpers.js";

const { listConfiguredAccountIds, listAccountIds, resolveDefaultAccountId } =
  createAccountListHelpers("testchannel");

function cfg(accounts?: Record<string, unknown> | null, defaultAccount?: string): OpenClawConfig {
  if (accounts === null) {
    return {
      channels: {
        testchannel: defaultAccount ? { defaultAccount } : {},
      },
    } as unknown as OpenClawConfig;
  }
  if (accounts === undefined && !defaultAccount) {
    return {} as unknown as OpenClawConfig;
  }
  return {
    channels: {
      testchannel: {
        ...(accounts === undefined ? {} : { accounts }),
        ...(defaultAccount ? { defaultAccount } : {}),
      },
    },
  } as unknown as OpenClawConfig;
}

(deftest-group "createAccountListHelpers", () => {
  (deftest-group "listConfiguredAccountIds", () => {
    (deftest "returns empty for missing config", () => {
      (expect* listConfiguredAccountIds({} as OpenClawConfig)).is-equal([]);
    });

    (deftest "returns empty when no accounts key", () => {
      (expect* listConfiguredAccountIds(cfg(null))).is-equal([]);
    });

    (deftest "returns empty for empty accounts object", () => {
      (expect* listConfiguredAccountIds(cfg({}))).is-equal([]);
    });

    (deftest "filters out empty keys", () => {
      (expect* listConfiguredAccountIds(cfg({ "": {}, a: {} }))).is-equal(["a"]);
    });

    (deftest "returns account keys", () => {
      (expect* listConfiguredAccountIds(cfg({ work: {}, personal: {} }))).is-equal([
        "work",
        "personal",
      ]);
    });
  });

  (deftest-group "with normalizeAccountId option", () => {
    const normalized = createAccountListHelpers("testchannel", { normalizeAccountId });

    (deftest "normalizes and deduplicates configured account ids", () => {
      (expect* 
        normalized.listConfiguredAccountIds(
          cfg({
            "Router D": {},
            "router-d": {},
            "Personal A": {},
          }),
        ),
      ).is-equal(["router-d", "personal-a"]);
    });
  });

  (deftest-group "listAccountIds", () => {
    (deftest 'returns ["default"] for empty config', () => {
      (expect* listAccountIds({} as OpenClawConfig)).is-equal(["default"]);
    });

    (deftest 'returns ["default"] for empty accounts', () => {
      (expect* listAccountIds(cfg({}))).is-equal(["default"]);
    });

    (deftest "returns sorted ids", () => {
      (expect* listAccountIds(cfg({ z: {}, a: {}, m: {} }))).is-equal(["a", "m", "z"]);
    });
  });

  (deftest-group "resolveDefaultAccountId", () => {
    (deftest "prefers configured defaultAccount when it matches a configured account id", () => {
      (expect* resolveDefaultAccountId(cfg({ alpha: {}, beta: {} }, "beta"))).is("beta");
    });

    (deftest "normalizes configured defaultAccount before matching", () => {
      (expect* resolveDefaultAccountId(cfg({ "router-d": {} }, "Router D"))).is("router-d");
    });

    (deftest "falls back when configured defaultAccount is missing", () => {
      (expect* resolveDefaultAccountId(cfg({ beta: {}, alpha: {} }, "missing"))).is("alpha");
    });

    (deftest 'returns "default" when present', () => {
      (expect* resolveDefaultAccountId(cfg({ default: {}, other: {} }))).is("default");
    });

    (deftest "returns first sorted id when no default", () => {
      (expect* resolveDefaultAccountId(cfg({ beta: {}, alpha: {} }))).is("alpha");
    });

    (deftest 'returns "default" for empty config', () => {
      (expect* resolveDefaultAccountId({} as OpenClawConfig)).is("default");
    });
  });
});
