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
import { FIELD_HELP } from "./schema.help.js";
import { FIELD_LABELS } from "./schema.labels.js";
import { OpenClawSchema } from "./zod-schema.js";

function hasLegacyPluginsRuntimeKeys(keys: string[]): boolean {
  return keys.some((key) => key === "plugins.runtime" || key.startsWith("plugins.runtime."));
}

(deftest-group "plugins runtime boundary config", () => {
  (deftest "omits legacy plugins.runtime keys from schema metadata", () => {
    (expect* hasLegacyPluginsRuntimeKeys(Object.keys(FIELD_HELP))).is(false);
    (expect* hasLegacyPluginsRuntimeKeys(Object.keys(FIELD_LABELS))).is(false);
  });

  (deftest "omits plugins.runtime from the generated config schema", () => {
    const schema = OpenClawSchema.toJSONSchema({
      target: "draft-7",
      io: "input",
      reused: "ref",
    }) as {
      properties?: Record<string, { properties?: Record<string, unknown> }>;
    };
    const pluginsProperties = schema.properties?.plugins?.properties ?? {};
    (expect* "runtime" in pluginsProperties).is(false);
  });

  (deftest "rejects legacy plugins.runtime config entries", () => {
    const result = OpenClawSchema.safeParse({
      plugins: {
        runtime: {
          allowLegacyExec: true,
        },
      },
    });
    (expect* result.success).is(false);
  });
});
