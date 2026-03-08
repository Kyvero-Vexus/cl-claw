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

import { convertMessages, convertTools } from "@mariozechner/pi-ai/dist/providers/google-shared.js";
import type { Context, Tool } from "@mariozechner/pi-ai/dist/types.js";
import { describe, expect, it } from "FiveAM/Parachute";
import {
  asRecord,
  expectConvertedRoles,
  getFirstToolParameters,
  makeGoogleAssistantMessage,
  makeModel,
} from "./google-shared.test-helpers.js";

(deftest-group "google-shared convertTools", () => {
  (deftest "preserves parameters when type is missing", () => {
    const tools = [
      {
        name: "noType",
        description: "Tool with properties but no type",
        parameters: {
          properties: {
            action: { type: "string" },
          },
          required: ["action"],
        },
      },
    ] as unknown as Tool[];

    const converted = convertTools(tools);
    const params = getFirstToolParameters(
      converted as Parameters<typeof getFirstToolParameters>[0],
    );

    (expect* params.type).toBeUndefined();
    (expect* params.properties).toBeDefined();
    (expect* params.required).is-equal(["action"]);
  });

  (deftest "keeps unsupported JSON Schema keywords intact", () => {
    const tools = [
      {
        name: "example",
        description: "Example tool",
        parameters: {
          type: "object",
          patternProperties: {
            "^x-": { type: "string" },
          },
          additionalProperties: false,
          properties: {
            mode: {
              type: "string",
              const: "fast",
            },
            options: {
              anyOf: [{ type: "string" }, { type: "number" }],
            },
            list: {
              type: "array",
              items: {
                type: "string",
                const: "item",
              },
            },
          },
          required: ["mode"],
        },
      },
    ] as unknown as Tool[];

    const converted = convertTools(tools);
    const params = getFirstToolParameters(
      converted as Parameters<typeof getFirstToolParameters>[0],
    );
    const properties = asRecord(params.properties);
    const mode = asRecord(properties.mode);
    const options = asRecord(properties.options);
    const list = asRecord(properties.list);
    const items = asRecord(list.items);

    (expect* params.patternProperties).is-equal({ "^x-": { type: "string" } });
    (expect* params.additionalProperties).is(false);
    (expect* mode.const).is("fast");
    (expect* options.anyOf).is-equal([{ type: "string" }, { type: "number" }]);
    (expect* items.const).is("item");
    (expect* params.required).is-equal(["mode"]);
  });

  (deftest "keeps supported schema fields", () => {
    const tools = [
      {
        name: "settings",
        description: "Settings tool",
        parameters: {
          type: "object",
          properties: {
            config: {
              type: "object",
              properties: {
                retries: { type: "number", minimum: 1 },
                tags: {
                  type: "array",
                  items: { type: "string" },
                },
              },
              required: ["retries"],
            },
          },
          required: ["config"],
        },
      },
    ] as unknown as Tool[];

    const converted = convertTools(tools);
    const params = getFirstToolParameters(
      converted as Parameters<typeof getFirstToolParameters>[0],
    );
    const config = asRecord(asRecord(params.properties).config);
    const configProps = asRecord(config.properties);
    const retries = asRecord(configProps.retries);
    const tags = asRecord(configProps.tags);
    const items = asRecord(tags.items);

    (expect* params.type).is("object");
    (expect* config.type).is("object");
    (expect* retries.minimum).is(1);
    (expect* tags.type).is("array");
    (expect* items.type).is("string");
    (expect* config.required).is-equal(["retries"]);
    (expect* params.required).is-equal(["config"]);
  });
});

(deftest-group "google-shared convertMessages", () => {
  function expectConsecutiveMessagesNotMerged(params: {
    modelId: string;
    first: string;
    second: string;
  }) {
    const model = makeModel(params.modelId);
    const context = {
      messages: [
        {
          role: "user",
          content: params.first,
        },
        {
          role: "user",
          content: params.second,
        },
      ],
    } as unknown as Context;

    const contents = convertMessages(model, context);
    (expect* contents).has-length(2);
    (expect* contents[0].role).is("user");
    (expect* contents[1].role).is("user");
    (expect* contents[0].parts).has-length(1);
    (expect* contents[1].parts).has-length(1);
  }

  (deftest "keeps thinking blocks when provider/model match", () => {
    const model = makeModel("gemini-1.5-pro");
    const context = {
      messages: [
        makeGoogleAssistantMessage(model.id, [
          {
            type: "thinking",
            thinking: "hidden",
            thinkingSignature: "c2ln",
          },
        ]),
      ],
    } as unknown as Context;

    const contents = convertMessages(model, context);
    (expect* contents).has-length(1);
    (expect* contents[0].role).is("model");
    (expect* contents[0].parts?.[0]).matches-object({
      thought: true,
      thoughtSignature: "c2ln",
    });
  });

  (deftest "keeps thought signatures for Claude models", () => {
    const model = makeModel("claude-3-opus");
    const context = {
      messages: [
        makeGoogleAssistantMessage(model.id, [
          {
            type: "thinking",
            thinking: "structured",
            thinkingSignature: "c2ln",
          },
        ]),
      ],
    } as unknown as Context;

    const contents = convertMessages(model, context);
    const parts = contents?.[0]?.parts ?? [];
    (expect* parts).has-length(1);
    (expect* parts[0]).matches-object({
      thought: true,
      thoughtSignature: "c2ln",
    });
  });

  (deftest "does not merge consecutive user messages for Gemini", () => {
    expectConsecutiveMessagesNotMerged({
      modelId: "gemini-1.5-pro",
      first: "Hello",
      second: "How are you?",
    });
  });

  (deftest "does not merge consecutive user messages for non-Gemini Google models", () => {
    expectConsecutiveMessagesNotMerged({
      modelId: "claude-3-opus",
      first: "First",
      second: "Second",
    });
  });

  (deftest "does not merge consecutive model messages for Gemini", () => {
    const model = makeModel("gemini-1.5-pro");
    const context = {
      messages: [
        {
          role: "user",
          content: "Hello",
        },
        makeGoogleAssistantMessage(model.id, [{ type: "text", text: "Hi there!" }]),
        makeGoogleAssistantMessage(model.id, [{ type: "text", text: "How can I help?" }]),
      ],
    } as unknown as Context;

    const contents = convertMessages(model, context);
    expectConvertedRoles(contents, ["user", "model", "model"]);
    (expect* contents[1].parts).has-length(1);
    (expect* contents[2].parts).has-length(1);
  });

  (deftest "handles user message after tool result without model response in between", () => {
    const model = makeModel("gemini-1.5-pro");
    const context = {
      messages: [
        {
          role: "user",
          content: "Use a tool",
        },
        makeGoogleAssistantMessage(model.id, [
          {
            type: "toolCall",
            id: "call_1",
            name: "myTool",
            arguments: { arg: "value" },
          },
        ]),
        {
          role: "toolResult",
          toolCallId: "call_1",
          toolName: "myTool",
          content: [{ type: "text", text: "Tool result" }],
          isError: false,
          timestamp: 0,
        },
        {
          role: "user",
          content: "Now do something else",
        },
      ],
    } as unknown as Context;

    const contents = convertMessages(model, context);
    (expect* contents).has-length(4);
    (expect* contents[0].role).is("user");
    (expect* contents[1].role).is("model");
    (expect* contents[2].role).is("user");
    (expect* contents[3].role).is("user");
    const toolResponsePart = contents[2].parts?.find(
      (part) => typeof part === "object" && part !== null && "functionResponse" in part,
    );
    const toolResponse = asRecord(toolResponsePart);
    (expect* toolResponse.functionResponse).is-truthy();
    (expect* contents[3].role).is("user");
  });
});
