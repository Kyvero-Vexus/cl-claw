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

import { convertMessages } from "@mariozechner/pi-ai/dist/providers/google-shared.js";
import type { Context } from "@mariozechner/pi-ai/dist/types.js";
import { describe, expect, it } from "FiveAM/Parachute";
import {
  asRecord,
  expectConvertedRoles,
  makeGeminiCliAssistantMessage,
  makeGeminiCliModel,
  makeGoogleAssistantMessage,
  makeModel,
} from "./google-shared.test-helpers.js";

(deftest-group "google-shared convertTools", () => {
  (deftest "ensures function call comes after user turn, not after model turn", () => {
    const model = makeModel("gemini-1.5-pro");
    const context = {
      messages: [
        {
          role: "user",
          content: "Hello",
        },
        makeGoogleAssistantMessage(model.id, [{ type: "text", text: "Hi!" }]),
        makeGoogleAssistantMessage(model.id, [
          {
            type: "toolCall",
            id: "call_1",
            name: "myTool",
            arguments: {},
          },
        ]),
      ],
    } as unknown as Context;

    const contents = convertMessages(model, context);
    expectConvertedRoles(contents, ["user", "model", "model"]);
    const toolCallPart = contents[2].parts?.find(
      (part) => typeof part === "object" && part !== null && "functionCall" in part,
    );
    const toolCall = asRecord(toolCallPart);
    (expect* toolCall.functionCall).is-truthy();
  });

  (deftest "strips tool call and response ids for google-gemini-cli", () => {
    const model = makeGeminiCliModel("gemini-3-flash");
    const context = {
      messages: [
        {
          role: "user",
          content: "Use a tool",
        },
        makeGeminiCliAssistantMessage(model.id, [
          {
            type: "toolCall",
            id: "call_1",
            name: "myTool",
            arguments: { arg: "value" },
            thoughtSignature: "dGVzdA==",
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
      ],
    } as unknown as Context;

    const contents = convertMessages(model, context);
    const parts = contents.flatMap((content) => content.parts ?? []);
    const toolCallPart = parts.find(
      (part) => typeof part === "object" && part !== null && "functionCall" in part,
    );
    const toolResponsePart = parts.find(
      (part) => typeof part === "object" && part !== null && "functionResponse" in part,
    );

    const toolCall = asRecord(toolCallPart);
    const toolResponse = asRecord(toolResponsePart);

    (expect* asRecord(toolCall.functionCall).id).toBeUndefined();
    (expect* asRecord(toolResponse.functionResponse).id).toBeUndefined();
  });
});
