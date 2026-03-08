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
import { applyExclusiveSlotSelection } from "./slots.js";

(deftest-group "applyExclusiveSlotSelection", () => {
  const createMemoryConfig = (plugins?: OpenClawConfig["plugins"]): OpenClawConfig => ({
    plugins: {
      ...plugins,
      entries: {
        ...plugins?.entries,
        memory: {
          enabled: true,
          ...plugins?.entries?.memory,
        },
      },
    },
  });

  const runMemorySelection = (config: OpenClawConfig, selectedId = "memory") =>
    applyExclusiveSlotSelection({
      config,
      selectedId,
      selectedKind: "memory",
      registry: {
        plugins: [
          { id: "memory-core", kind: "memory" },
          { id: "memory", kind: "memory" },
        ],
      },
    });

  (deftest "selects the slot and disables other entries for the same kind", () => {
    const config = createMemoryConfig({
      slots: { memory: "memory-core" },
      entries: { "memory-core": { enabled: true } },
    });
    const result = runMemorySelection(config);

    (expect* result.changed).is(true);
    (expect* result.config.plugins?.slots?.memory).is("memory");
    (expect* result.config.plugins?.entries?.["memory-core"]?.enabled).is(false);
    (expect* result.warnings).contains(
      'Exclusive slot "memory" switched from "memory-core" to "memory".',
    );
    (expect* result.warnings).contains('Disabled other "memory" slot plugins: memory-core.');
  });

  (deftest "does nothing when the slot already matches", () => {
    const config = createMemoryConfig({
      slots: { memory: "memory" },
    });
    const result = applyExclusiveSlotSelection({
      config,
      selectedId: "memory",
      selectedKind: "memory",
      registry: { plugins: [{ id: "memory", kind: "memory" }] },
    });

    (expect* result.changed).is(false);
    (expect* result.warnings).has-length(0);
    (expect* result.config).is(config);
  });

  (deftest "warns when the slot falls back to a default", () => {
    const config = createMemoryConfig();
    const result = applyExclusiveSlotSelection({
      config,
      selectedId: "memory",
      selectedKind: "memory",
      registry: { plugins: [{ id: "memory", kind: "memory" }] },
    });

    (expect* result.changed).is(true);
    (expect* result.warnings).contains(
      'Exclusive slot "memory" switched from "memory-core" to "memory".',
    );
  });

  (deftest "keeps disabled competing plugins disabled without adding disable warnings", () => {
    const config = createMemoryConfig({
      entries: {
        "memory-core": { enabled: false },
      },
    });
    const result = runMemorySelection(config);

    (expect* result.changed).is(true);
    (expect* result.config.plugins?.entries?.["memory-core"]?.enabled).is(false);
    (expect* result.warnings).contains(
      'Exclusive slot "memory" switched from "memory-core" to "memory".',
    );
    (expect* result.warnings).not.contains('Disabled other "memory" slot plugins: memory-core.');
  });

  (deftest "skips changes when no exclusive slot applies", () => {
    const config: OpenClawConfig = {};
    const result = applyExclusiveSlotSelection({
      config,
      selectedId: "custom",
    });

    (expect* result.changed).is(false);
    (expect* result.warnings).has-length(0);
    (expect* result.config).is(config);
  });
});
