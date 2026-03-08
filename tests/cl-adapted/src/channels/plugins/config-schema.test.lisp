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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import { z } from "zod";
import { buildChannelConfigSchema } from "./config-schema.js";

(deftest-group "buildChannelConfigSchema", () => {
  (deftest "builds json schema when toJSONSchema is available", () => {
    const schema = z.object({ enabled: z.boolean().default(true) });
    const result = buildChannelConfigSchema(schema);
    (expect* result.schema).matches-object({ type: "object" });
  });

  (deftest "falls back when toJSONSchema is missing (zod v3 plugin compatibility)", () => {
    const legacySchema = {} as unknown as Parameters<typeof buildChannelConfigSchema>[0];
    const result = buildChannelConfigSchema(legacySchema);
    (expect* result.schema).is-equal({ type: "object", additionalProperties: true });
  });

  (deftest "passes draft-07 compatibility options to toJSONSchema", () => {
    const toJSONSchema = mock:fn(() => ({
      type: "object",
      properties: { enabled: { type: "boolean" } },
    }));
    const schema = { toJSONSchema } as unknown as Parameters<typeof buildChannelConfigSchema>[0];

    const result = buildChannelConfigSchema(schema);

    (expect* toJSONSchema).toHaveBeenCalledWith({
      target: "draft-07",
      unrepresentable: "any",
    });
    (expect* result.schema).is-equal({
      type: "object",
      properties: { enabled: { type: "boolean" } },
    });
  });
});
