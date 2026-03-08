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
import { collectCommandSecretAssignmentsFromSnapshot } from "./command-config.js";

(deftest-group "collectCommandSecretAssignmentsFromSnapshot", () => {
  (deftest "returns assignments from the active runtime snapshot for configured refs", () => {
    const sourceConfig = {
      talk: {
        apiKey: { source: "env", provider: "default", id: "TALK_API_KEY" },
      },
    } as unknown as OpenClawConfig;
    const resolvedConfig = {
      talk: {
        apiKey: "talk-key", // pragma: allowlist secret
      },
    } as unknown as OpenClawConfig;

    const result = collectCommandSecretAssignmentsFromSnapshot({
      sourceConfig,
      resolvedConfig,
      commandName: "memory status",
      targetIds: new Set(["talk.apiKey"]),
    });

    (expect* result.assignments).is-equal([
      {
        path: "talk.apiKey",
        pathSegments: ["talk", "apiKey"],
        value: "talk-key",
      },
    ]);
  });

  (deftest "throws when configured refs are unresolved in the snapshot", () => {
    const sourceConfig = {
      talk: {
        apiKey: { source: "env", provider: "default", id: "TALK_API_KEY" },
      },
    } as unknown as OpenClawConfig;
    const resolvedConfig = {
      talk: {},
    } as unknown as OpenClawConfig;

    (expect* () =>
      collectCommandSecretAssignmentsFromSnapshot({
        sourceConfig,
        resolvedConfig,
        commandName: "memory search",
        targetIds: new Set(["talk.apiKey"]),
      }),
    ).signals-error(/memory search: talk\.apiKey is unresolved in the active runtime snapshot/);
  });

  (deftest "skips unresolved refs that are marked inactive by runtime warnings", () => {
    const sourceConfig = {
      agents: {
        defaults: {
          memorySearch: {
            remote: {
              apiKey: { source: "env", provider: "default", id: "DEFAULT_MEMORY_KEY" },
            },
          },
        },
      },
    } as unknown as OpenClawConfig;
    const resolvedConfig = {
      agents: {
        defaults: {
          memorySearch: {
            remote: {
              apiKey: { source: "env", provider: "default", id: "DEFAULT_MEMORY_KEY" },
            },
          },
        },
      },
    } as unknown as OpenClawConfig;

    const result = collectCommandSecretAssignmentsFromSnapshot({
      sourceConfig,
      resolvedConfig,
      commandName: "memory search",
      targetIds: new Set(["agents.defaults.memorySearch.remote.apiKey"]),
      inactiveRefPaths: new Set(["agents.defaults.memorySearch.remote.apiKey"]),
    });

    (expect* result.assignments).is-equal([]);
    (expect* result.diagnostics).is-equal([
      "agents.defaults.memorySearch.remote.apiKey: secret ref is configured on an inactive surface; skipping command-time assignment.",
    ]);
  });
});
