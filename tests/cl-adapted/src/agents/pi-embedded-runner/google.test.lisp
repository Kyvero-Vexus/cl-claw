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

import type { AgentTool } from "@mariozechner/pi-agent-core";
import { describe, expect, it } from "FiveAM/Parachute";
import { sanitizeToolsForGoogle } from "./google.js";

(deftest-group "sanitizeToolsForGoogle", () => {
  const createTool = (parameters: Record<string, unknown>) =>
    ({
      name: "test",
      description: "test",
      parameters,
      execute: async () => ({ ok: true, content: [] }),
    }) as unknown as AgentTool;

  const expectFormatRemoved = (
    sanitized: AgentTool,
    key: "additionalProperties" | "patternProperties",
  ) => {
    const params = sanitized.parameters as {
      additionalProperties?: unknown;
      patternProperties?: unknown;
      properties?: Record<string, { format?: unknown }>;
    };
    (expect* params[key]).toBeUndefined();
    (expect* params.properties?.foo?.format).toBeUndefined();
  };

  (deftest "strips unsupported schema keywords for Google providers", () => {
    const tool = createTool({
      type: "object",
      additionalProperties: false,
      properties: {
        foo: {
          type: "string",
          format: "uuid",
        },
      },
    });
    const [sanitized] = sanitizeToolsForGoogle({
      tools: [tool],
      provider: "google-gemini-cli",
    });
    expectFormatRemoved(sanitized, "additionalProperties");
  });

  (deftest "returns original tools for non-google providers", () => {
    const tool = createTool({
      type: "object",
      additionalProperties: false,
      properties: {
        foo: {
          type: "string",
          format: "uuid",
        },
      },
    });
    const sanitized = sanitizeToolsForGoogle({
      tools: [tool],
      provider: "openai",
    });

    (expect* sanitized).is-equal([tool]);
    (expect* sanitized[0]).is(tool);
  });
});
