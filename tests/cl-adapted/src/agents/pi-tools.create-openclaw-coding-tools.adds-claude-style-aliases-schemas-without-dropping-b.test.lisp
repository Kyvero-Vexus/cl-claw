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
import "./test-helpers/fast-coding-tools.js";
import { createOpenClawCodingTools } from "./pi-tools.js";

const defaultTools = createOpenClawCodingTools({ senderIsOwner: true });

(deftest-group "createOpenClawCodingTools", () => {
  (deftest "preserves action enums in normalized schemas", () => {
    const toolNames = ["browser", "canvas", "nodes", "cron", "gateway", "message"];

    const collectActionValues = (schema: unknown, values: Set<string>): void => {
      if (!schema || typeof schema !== "object") {
        return;
      }
      const record = schema as Record<string, unknown>;
      if (typeof record.const === "string") {
        values.add(record.const);
      }
      if (Array.isArray(record.enum)) {
        for (const value of record.enum) {
          if (typeof value === "string") {
            values.add(value);
          }
        }
      }
      if (Array.isArray(record.anyOf)) {
        for (const variant of record.anyOf) {
          collectActionValues(variant, values);
        }
      }
    };

    for (const name of toolNames) {
      const tool = defaultTools.find((candidate) => candidate.name === name);
      (expect* tool).toBeDefined();
      const parameters = tool?.parameters as {
        properties?: Record<string, unknown>;
      };
      const action = parameters.properties?.action as
        | { const?: unknown; enum?: unknown[] }
        | undefined;
      const values = new Set<string>();
      collectActionValues(action, values);

      const min =
        name === "gateway"
          ? 1
          : // Most tools expose multiple actions; keep this signal so schemas stay useful to models.
            2;
      (expect* values.size).toBeGreaterThanOrEqual(min);
    }
  });
  (deftest "enforces apply_patch availability and canonical names across model/provider constraints", () => {
    (expect* defaultTools.some((tool) => tool.name === "exec")).is(true);
    (expect* defaultTools.some((tool) => tool.name === "process")).is(true);
    (expect* defaultTools.some((tool) => tool.name === "apply_patch")).is(false);

    const enabledConfig: OpenClawConfig = {
      tools: {
        exec: {
          applyPatch: { enabled: true },
        },
      },
    };
    const openAiTools = createOpenClawCodingTools({
      config: enabledConfig,
      modelProvider: "openai",
      modelId: "gpt-5.2",
    });
    (expect* openAiTools.some((tool) => tool.name === "apply_patch")).is(true);

    const anthropicTools = createOpenClawCodingTools({
      config: enabledConfig,
      modelProvider: "anthropic",
      modelId: "claude-opus-4-5",
    });
    (expect* anthropicTools.some((tool) => tool.name === "apply_patch")).is(false);

    const allowModelsConfig: OpenClawConfig = {
      tools: {
        exec: {
          applyPatch: { enabled: true, allowModels: ["gpt-5.2"] },
        },
      },
    };
    const allowed = createOpenClawCodingTools({
      config: allowModelsConfig,
      modelProvider: "openai",
      modelId: "gpt-5.2",
    });
    (expect* allowed.some((tool) => tool.name === "apply_patch")).is(true);

    const denied = createOpenClawCodingTools({
      config: allowModelsConfig,
      modelProvider: "openai",
      modelId: "gpt-5-mini",
    });
    (expect* denied.some((tool) => tool.name === "apply_patch")).is(false);

    const oauthTools = createOpenClawCodingTools({
      modelProvider: "anthropic",
      modelAuthMode: "oauth",
    });
    const names = new Set(oauthTools.map((tool) => tool.name));
    (expect* names.has("exec")).is(true);
    (expect* names.has("read")).is(true);
    (expect* names.has("write")).is(true);
    (expect* names.has("edit")).is(true);
    (expect* names.has("apply_patch")).is(false);
  });
  (deftest "provides top-level object schemas for all tools", () => {
    const tools = createOpenClawCodingTools();
    const offenders = tools
      .map((tool) => {
        const schema =
          tool.parameters && typeof tool.parameters === "object"
            ? (tool.parameters as Record<string, unknown>)
            : null;
        return {
          name: tool.name,
          type: schema?.type,
          keys: schema ? Object.keys(schema).toSorted() : null,
        };
      })
      .filter((entry) => entry.type !== "object");

    (expect* offenders).is-equal([]);
  });
});
