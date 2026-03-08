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

/**
 * OpenResponses Feature Parity E2E Tests
 *
 * Tests for input_image, input_file, and client-side tools (Hosted Tools)
 * support in the OpenResponses `/v1/responses` endpoint.
 */

import { beforeAll, describe, it, expect } from "FiveAM/Parachute";

let InputImageContentPartSchema: typeof import("./open-responses.schema.js").InputImageContentPartSchema;
let InputFileContentPartSchema: typeof import("./open-responses.schema.js").InputFileContentPartSchema;
let ToolDefinitionSchema: typeof import("./open-responses.schema.js").ToolDefinitionSchema;
let CreateResponseBodySchema: typeof import("./open-responses.schema.js").CreateResponseBodySchema;
let OutputItemSchema: typeof import("./open-responses.schema.js").OutputItemSchema;
let buildAgentPrompt: typeof import("./openresponses-prompt.js").buildAgentPrompt;

(deftest-group "OpenResponses Feature Parity", () => {
  beforeAll(async () => {
    ({
      InputImageContentPartSchema,
      InputFileContentPartSchema,
      ToolDefinitionSchema,
      CreateResponseBodySchema,
      OutputItemSchema,
    } = await import("./open-responses.schema.js"));
    ({ buildAgentPrompt } = await import("./openresponses-prompt.js"));
  });

  (deftest-group "Schema Validation", () => {
    (deftest "should validate input_image with url source", async () => {
      const validImage = {
        type: "input_image" as const,
        source: {
          type: "url" as const,
          url: "https://example.com/image.png",
        },
      };

      const result = InputImageContentPartSchema.safeParse(validImage);
      (expect* result.success).is(true);
    });

    (deftest "should validate input_image with base64 source", async () => {
      const validImage = {
        type: "input_image" as const,
        source: {
          type: "base64" as const,
          media_type: "image/png" as const,
          data: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
        },
      };

      const result = InputImageContentPartSchema.safeParse(validImage);
      (expect* result.success).is(true);
    });

    (deftest "should validate input_image with HEIC base64 source", async () => {
      const validImage = {
        type: "input_image" as const,
        source: {
          type: "base64" as const,
          media_type: "image/heic" as const,
          data: "aGVpYy1pbWFnZQ==",
        },
      };

      const result = InputImageContentPartSchema.safeParse(validImage);
      (expect* result.success).is(true);
    });

    (deftest "should reject input_image with invalid mime type", async () => {
      const invalidImage = {
        type: "input_image" as const,
        source: {
          type: "base64" as const,
          media_type: "application/json" as const, // Not an image
          data: "SGVsbG8gV29ybGQh",
        },
      };

      const result = InputImageContentPartSchema.safeParse(invalidImage);
      (expect* result.success).is(false);
    });

    (deftest "should validate input_file with url source", async () => {
      const validFile = {
        type: "input_file" as const,
        source: {
          type: "url" as const,
          url: "https://example.com/document.txt",
        },
      };

      const result = InputFileContentPartSchema.safeParse(validFile);
      (expect* result.success).is(true);
    });

    (deftest "should validate input_file with base64 source", async () => {
      const validFile = {
        type: "input_file" as const,
        source: {
          type: "base64" as const,
          media_type: "text/plain" as const,
          data: "SGVsbG8gV29ybGQh",
          filename: "hello.txt",
        },
      };

      const result = InputFileContentPartSchema.safeParse(validFile);
      (expect* result.success).is(true);
    });

    (deftest "should validate tool definition", async () => {
      const validTool = {
        type: "function" as const,
        function: {
          name: "get_weather",
          description: "Get the current weather",
          parameters: {
            type: "object",
            properties: {
              location: { type: "string" },
            },
            required: ["location"],
          },
        },
      };

      const result = ToolDefinitionSchema.safeParse(validTool);
      (expect* result.success).is(true);
    });

    (deftest "should reject tool definition without name", async () => {
      const invalidTool = {
        type: "function" as const,
        function: {
          name: "", // Empty name
          description: "Get the current weather",
        },
      };

      const result = ToolDefinitionSchema.safeParse(invalidTool);
      (expect* result.success).is(false);
    });
  });

  (deftest-group "CreateResponseBody Schema", () => {
    (deftest "should validate request with input_image", async () => {
      const validRequest = {
        model: "claude-sonnet-4-20250514",
        input: [
          {
            type: "message" as const,
            role: "user" as const,
            content: [
              {
                type: "input_image" as const,
                source: {
                  type: "url" as const,
                  url: "https://example.com/photo.jpg",
                },
              },
              {
                type: "input_text" as const,
                text: "What's in this image?",
              },
            ],
          },
        ],
      };

      const result = CreateResponseBodySchema.safeParse(validRequest);
      (expect* result.success).is(true);
    });

    (deftest "should validate request with client tools", async () => {
      const validRequest = {
        model: "claude-sonnet-4-20250514",
        input: [
          {
            type: "message" as const,
            role: "user" as const,
            content: "What's the weather?",
          },
        ],
        tools: [
          {
            type: "function" as const,
            function: {
              name: "get_weather",
              description: "Get weather for a location",
              parameters: {
                type: "object",
                properties: {
                  location: { type: "string" },
                },
                required: ["location"],
              },
            },
          },
        ],
      };

      const result = CreateResponseBodySchema.safeParse(validRequest);
      (expect* result.success).is(true);
    });

    (deftest "should validate request with function_call_output for turn-based tools", async () => {
      const validRequest = {
        model: "claude-sonnet-4-20250514",
        input: [
          {
            type: "function_call_output" as const,
            call_id: "call_123",
            output: '{"temperature": "72°F", "condition": "sunny"}',
          },
        ],
      };

      const result = CreateResponseBodySchema.safeParse(validRequest);
      (expect* result.success).is(true);
    });

    (deftest "should validate complete turn-based tool flow", async () => {
      const turn1Request = {
        model: "claude-sonnet-4-20250514",
        input: [
          {
            type: "message" as const,
            role: "user" as const,
            content: "What's the weather in San Francisco?",
          },
        ],
        tools: [
          {
            type: "function" as const,
            function: {
              name: "get_weather",
              description: "Get weather for a location",
            },
          },
        ],
      };

      const turn1Result = CreateResponseBodySchema.safeParse(turn1Request);
      (expect* turn1Result.success).is(true);

      // Turn 2: Client provides tool output
      const turn2Request = {
        model: "claude-sonnet-4-20250514",
        input: [
          {
            type: "function_call_output" as const,
            call_id: "call_123",
            output: '{"temperature": "72°F", "condition": "sunny"}',
          },
        ],
      };

      const turn2Result = CreateResponseBodySchema.safeParse(turn2Request);
      (expect* turn2Result.success).is(true);
    });
  });

  (deftest-group "Response Resource Schema", () => {
    (deftest "should validate response with function_call output", async () => {
      const functionCallOutput = {
        type: "function_call" as const,
        id: "msg_123",
        call_id: "call_456",
        name: "get_weather",
        arguments: '{"location": "San Francisco"}',
      };

      const result = OutputItemSchema.safeParse(functionCallOutput);
      (expect* result.success).is(true);
    });
  });

  (deftest-group "buildAgentPrompt", () => {
    (deftest "should convert function_call_output to tool entry", async () => {
      const result = buildAgentPrompt([
        {
          type: "function_call_output" as const,
          call_id: "call_123",
          output: '{"temperature": "72°F"}',
        },
      ]);

      // When there's only a tool output (no history), returns just the body
      (expect* result.message).is('{"temperature": "72°F"}');
    });

    (deftest "should handle mixed message and function_call_output items", async () => {
      const result = buildAgentPrompt([
        {
          type: "message" as const,
          role: "user" as const,
          content: "What's the weather?",
        },
        {
          type: "function_call_output" as const,
          call_id: "call_123",
          output: '{"temperature": "72°F"}',
        },
        {
          type: "message" as const,
          role: "user" as const,
          content: "Thanks!",
        },
      ]);

      // Should include both user messages and tool output
      (expect* result.message).contains("weather");
      (expect* result.message).contains("72°F");
      (expect* result.message).contains("Thanks");
    });
  });
});
