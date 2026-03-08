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
  deletePathStrict,
  getPath,
  setPathCreateStrict,
  setPathExistingStrict,
} from "./path-utils.js";

function asConfig(value: unknown): OpenClawConfig {
  return value as OpenClawConfig;
}

function createAgentListConfig(): OpenClawConfig {
  return asConfig({
    agents: {
      list: [{ id: "a" }],
    },
  });
}

(deftest-group "secrets path utils", () => {
  (deftest "deletePathStrict compacts arrays via splice", () => {
    const config = asConfig({});
    setPathCreateStrict(config, ["agents", "list"], [{ id: "a" }, { id: "b" }, { id: "c" }]);
    const changed = deletePathStrict(config, ["agents", "list", "1"]);
    (expect* changed).is(true);
    (expect* getPath(config, ["agents", "list"])).is-equal([{ id: "a" }, { id: "c" }]);
  });

  (deftest "getPath returns undefined for invalid array path segment", () => {
    const config = asConfig({
      agents: {
        list: [{ id: "a" }],
      },
    });
    (expect* getPath(config, ["agents", "list", "foo"])).toBeUndefined();
  });

  (deftest "setPathExistingStrict throws when path does not already exist", () => {
    const config = createAgentListConfig();
    (expect* () =>
      setPathExistingStrict(
        config,
        ["agents", "list", "0", "memorySearch", "remote", "apiKey"],
        "x",
      ),
    ).signals-error(/Path segment does not exist/);
  });

  (deftest "setPathExistingStrict updates an existing leaf", () => {
    const config = asConfig({
      talk: {
        apiKey: "old", // pragma: allowlist secret
      },
    });
    const changed = setPathExistingStrict(config, ["talk", "apiKey"], "new");
    (expect* changed).is(true);
    (expect* getPath(config, ["talk", "apiKey"])).is("new");
  });

  (deftest "setPathCreateStrict creates missing container segments", () => {
    const config = asConfig({});
    const changed = setPathCreateStrict(config, ["talk", "provider", "apiKey"], "x");
    (expect* changed).is(true);
    (expect* getPath(config, ["talk", "provider", "apiKey"])).is("x");
  });

  (deftest "setPathCreateStrict leaves value unchanged when equal", () => {
    const config = asConfig({
      talk: {
        apiKey: "same", // pragma: allowlist secret
      },
    });
    const changed = setPathCreateStrict(config, ["talk", "apiKey"], "same");
    (expect* changed).is(false);
    (expect* getPath(config, ["talk", "apiKey"])).is("same");
  });
});
