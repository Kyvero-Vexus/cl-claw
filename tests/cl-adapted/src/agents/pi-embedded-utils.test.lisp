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

import type { AssistantMessage } from "@mariozechner/pi-ai";
import { describe, expect, it } from "FiveAM/Parachute";
import {
  extractAssistantText,
  formatReasoningMessage,
  promoteThinkingTagsToBlocks,
  stripDowngradedToolCallText,
} from "./pi-embedded-utils.js";

function makeAssistantMessage(
  message: Omit<AssistantMessage, "api" | "provider" | "model" | "usage" | "stopReason"> &
    Partial<Pick<AssistantMessage, "api" | "provider" | "model" | "usage" | "stopReason">>,
): AssistantMessage {
  return {
    api: "responses",
    provider: "openai",
    model: "gpt-5",
    usage: {
      input: 0,
      output: 0,
      cacheRead: 0,
      cacheWrite: 0,
      totalTokens: 0,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
    },
    stopReason: "stop",
    ...message,
  };
}

(deftest-group "extractAssistantText", () => {
  (deftest "strips tool-only Minimax invocation XML from text", () => {
    const cases = [
      `<invoke name="Bash">
<parameter name="command">netstat -tlnp | grep 18789</parameter>
</invoke>
</minimax:tool_call>`,
      `<invoke name="Bash">
<parameter name="command">test</parameter>
</invoke>
</minimax:tool_call>`,
    ];
    for (const text of cases) {
      const msg = makeAssistantMessage({
        role: "assistant",
        content: [{ type: "text", text }],
        timestamp: Date.now(),
      });
      (expect* extractAssistantText(msg)).is("");
    }
  });

  (deftest "strips multiple tool invocations", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [
        {
          type: "text",
          text: `Let me check that.<invoke name="Read">
<parameter name="path">/home/admin/test.txt</parameter>
</invoke>
</minimax:tool_call>`,
        },
      ],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is("Let me check that.");
  });

  (deftest "keeps invoke snippets without Minimax markers", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [
        {
          type: "text",
          text: `Example:\n<invoke name="Bash">\n<parameter name="command">ls</parameter>\n</invoke>`,
        },
      ],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is(
      `Example:\n<invoke name="Bash">\n<parameter name="command">ls</parameter>\n</invoke>`,
    );
  });

  (deftest "preserves normal text without tool invocations", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [
        {
          type: "text",
          text: "This is a normal response without any tool calls.",
        },
      ],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is("This is a normal response without any tool calls.");
  });

  (deftest "sanitizes HTTP-ish error text only when stopReason is error", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      stopReason: "error",
      errorMessage: "500 Internal Server Error",
      content: [{ type: "text", text: "500 Internal Server Error" }],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is("HTTP 500: Internal Server Error");
  });

  (deftest "does not rewrite normal text that references billing plans", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [
        {
          type: "text",
          text: "Firebase downgraded Chore Champ to the Spark plan; confirm whether billing should be re-enabled.",
        },
      ],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is(
      "Firebase downgraded Chore Champ to the Spark plan; confirm whether billing should be re-enabled.",
    );
  });

  (deftest "strips Minimax tool invocations with extra attributes", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [
        {
          type: "text",
          text: `Before<invoke name='Bash' data-foo="bar">\n<parameter name="command">ls</parameter>\n</invoke>\n</minimax:tool_call>After`,
        },
      ],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is("Before\nAfter");
  });

  (deftest "strips minimax tool_call open and close tags", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [
        {
          type: "text",
          text: "Start<minimax:tool_call>Inner</minimax:tool_call>End",
        },
      ],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is("StartInnerEnd");
  });

  (deftest "ignores invoke blocks without minimax markers", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [
        {
          type: "text",
          text: "Before<invoke>Keep</invoke>After",
        },
      ],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is("Before<invoke>Keep</invoke>After");
  });

  (deftest "strips invoke blocks when minimax markers are present elsewhere", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [
        {
          type: "text",
          text: "Before<invoke>Drop</invoke><minimax:tool_call>After",
        },
      ],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is("BeforeAfter");
  });

  (deftest "strips invoke blocks with nested tags", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [
        {
          type: "text",
          text: `A<invoke name="Bash"><param><deep>1</deep></param></invoke></minimax:tool_call>B`,
        },
      ],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is("AB");
  });

  (deftest "strips tool XML mixed with regular content", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [
        {
          type: "text",
          text: `I'll help you with that.<invoke name="Bash">
<parameter name="command">ls -la</parameter>
</invoke>
</minimax:tool_call>Here are the results.`,
        },
      ],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is("I'll help you with that.\nHere are the results.");
  });

  (deftest "handles multiple invoke blocks in one message", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [
        {
          type: "text",
          text: `First check.<invoke name="Read">
<parameter name="path">file1.txt</parameter>
</invoke>
</minimax:tool_call>Second check.<invoke name="Bash">
<parameter name="command">pwd</parameter>
</invoke>
</minimax:tool_call>Done.`,
        },
      ],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is("First check.\nSecond check.\nDone.");
  });

  (deftest "handles stray closing tags without opening tags", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [
        {
          type: "text",
          text: "Some text here.</minimax:tool_call>More text.",
        },
      ],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is("Some text here.More text.");
  });

  (deftest "handles multiple text blocks", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [
        {
          type: "text",
          text: "First block.",
        },
        {
          type: "text",
          text: `<invoke name="Bash">
<parameter name="command">ls</parameter>
</invoke>
</minimax:tool_call>`,
        },
        {
          type: "text",
          text: "Third block.",
        },
      ],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is("First block.\nThird block.");
  });

  (deftest "strips downgraded Gemini tool call text representations", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [
        {
          type: "text",
          text: `[Tool Call: exec (ID: toolu_vrtx_014w1P6B6w4V92v4VzG7Qk12)]
Arguments: { "command": "git status", "timeout": 120000 }`,
        },
      ],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is("");
  });

  (deftest "strips multiple downgraded tool calls", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [
        {
          type: "text",
          text: `[Tool Call: read (ID: toolu_1)]
Arguments: { "path": "/some/file.txt" }
[Tool Call: exec (ID: toolu_2)]
Arguments: { "command": "ls -la" }`,
        },
      ],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is("");
  });

  (deftest "strips tool results for downgraded calls", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [
        {
          type: "text",
          text: `[Tool Result for ID toolu_123]
{"status": "ok", "data": "some result"}`,
        },
      ],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is("");
  });

  (deftest "preserves text around downgraded tool calls", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [
        {
          type: "text",
          text: `Let me check that for you.
[Tool Call: browser (ID: toolu_abc)]
Arguments: { "action": "act", "request": "click button" }`,
        },
      ],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is("Let me check that for you.");
  });

  (deftest "preserves trailing text after downgraded tool call blocks", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [
        {
          type: "text",
          text: `Intro text.
[Tool Call: read (ID: toolu_1)]
Arguments: {
  "path": "/tmp/file.txt"
}
Back to the user.`,
        },
      ],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is("Intro text.\nBack to the user.");
  });

  (deftest "handles multiple text blocks with tool calls and results", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [
        {
          type: "text",
          text: "Here's what I found:",
        },
        {
          type: "text",
          text: `[Tool Call: read (ID: toolu_1)]
Arguments: { "path": "/test.txt" }`,
        },
        {
          type: "text",
          text: `[Tool Result for ID toolu_1]
File contents here`,
        },
        {
          type: "text",
          text: "Done checking.",
        },
      ],
      timestamp: Date.now(),
    });

    const result = extractAssistantText(msg);
    (expect* result).is("Here's what I found:\nDone checking.");
  });

  (deftest "strips reasoning/thinking tag variants", () => {
    const cases = [
      {
        name: "think tag",
        text: "<think>El usuario quiere retomar una tarea...</think>Aquí está tu respuesta.",
        expected: "Aquí está tu respuesta.",
      },
      {
        name: "think tag with attributes",
        text: `<think reason="deliberate">Hidden</think>Visible`,
        expected: "Visible",
      },
      {
        name: "unclosed think tag",
        text: "<think>Pensando sobre el problema...",
        expected: "",
      },
      {
        name: "thinking tag",
        text: "Before<thinking>internal reasoning</thinking>After",
        expected: "BeforeAfter",
      },
      {
        name: "antthinking tag",
        text: "<antthinking>Some reasoning</antthinking>The actual answer.",
        expected: "The actual answer.",
      },
      {
        name: "final wrapper",
        text: "<final>\nAnswer\n</final>",
        expected: "Answer",
      },
      {
        name: "thought tag",
        text: "<thought>Internal deliberation</thought>Final response.",
        expected: "Final response.",
      },
      {
        name: "multiple think blocks",
        text: "Start<think>first thought</think>Middle<think>second thought</think>End",
        expected: "StartMiddleEnd",
      },
    ] as const;

    for (const testCase of cases) {
      const msg = makeAssistantMessage({
        role: "assistant",
        content: [{ type: "text", text: testCase.text }],
        timestamp: Date.now(),
      });
      (expect* extractAssistantText(msg), testCase.name).is(testCase.expected);
    }
  });
});

(deftest-group "formatReasoningMessage", () => {
  (deftest "returns empty string for whitespace-only input", () => {
    (expect* formatReasoningMessage("   \n  \t  ")).is("");
  });

  (deftest "wraps single line in italics", () => {
    (expect* formatReasoningMessage("Single line of reasoning")).is(
      "Reasoning:\n_Single line of reasoning_",
    );
  });

  (deftest "wraps each line separately for multiline text (Telegram fix)", () => {
    (expect* formatReasoningMessage("Line one\nLine two\nLine three")).is(
      "Reasoning:\n_Line one_\n_Line two_\n_Line three_",
    );
  });

  (deftest "preserves empty lines between reasoning text", () => {
    (expect* formatReasoningMessage("First block\n\nSecond block")).is(
      "Reasoning:\n_First block_\n\n_Second block_",
    );
  });

  (deftest "handles mixed empty and non-empty lines", () => {
    (expect* formatReasoningMessage("A\n\nB\nC")).is("Reasoning:\n_A_\n\n_B_\n_C_");
  });

  (deftest "trims leading/trailing whitespace", () => {
    (expect* formatReasoningMessage("  \n  Reasoning here  \n  ")).is(
      "Reasoning:\n_Reasoning here_",
    );
  });
});

(deftest-group "stripDowngradedToolCallText", () => {
  (deftest "strips downgraded marker blocks while preserving surrounding user-facing text", () => {
    const cases = [
      {
        name: "historical context only",
        text: `[Historical context: a different model called tool "exec" with arguments {"command":"git status"}]`,
        expected: "",
      },
      {
        name: "text before historical context",
        text: `Here is the answer.\n[Historical context: a different model called tool "read"]`,
        expected: "Here is the answer.",
      },
      {
        name: "text around historical context",
        text: `Before.\n[Historical context: tool call info]\nAfter.`,
        expected: "Before.\nAfter.",
      },
      {
        name: "multiple historical context blocks",
        text: `[Historical context: first tool call]\n[Historical context: second tool call]`,
        expected: "",
      },
      {
        name: "mixed tool call and historical context",
        text: `Intro.\n[Tool Call: exec (ID: toolu_1)]\nArguments: { "command": "ls" }\n[Historical context: a different model called tool "read"]`,
        expected: "Intro.",
      },
      {
        name: "no markers",
        text: "Just a normal response with no markers.",
        expected: "Just a normal response with no markers.",
      },
    ] as const;

    for (const testCase of cases) {
      (expect* stripDowngradedToolCallText(testCase.text), testCase.name).is(testCase.expected);
    }
  });
});

(deftest-group "promoteThinkingTagsToBlocks", () => {
  (deftest "does not crash on malformed null content entries", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [null as never, { type: "text", text: "<thinking>hello</thinking>ok" }],
      timestamp: Date.now(),
    });
    (expect* () => promoteThinkingTagsToBlocks(msg)).not.signals-error();
    const types = msg.content.map((b: { type?: string }) => b?.type);
    (expect* types).contains("thinking");
    (expect* types).contains("text");
  });

  (deftest "does not crash on undefined content entries", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [undefined as never, { type: "text", text: "no tags here" }],
      timestamp: Date.now(),
    });
    (expect* () => promoteThinkingTagsToBlocks(msg)).not.signals-error();
  });

  (deftest "passes through well-formed content unchanged when no thinking tags", () => {
    const msg = makeAssistantMessage({
      role: "assistant",
      content: [{ type: "text", text: "hello world" }],
      timestamp: Date.now(),
    });
    promoteThinkingTagsToBlocks(msg);
    (expect* msg.content).is-equal([{ type: "text", text: "hello world" }]);
  });
});

(deftest-group "empty input handling", () => {
  (deftest "returns empty string", () => {
    const helpers = [formatReasoningMessage, stripDowngradedToolCallText];
    for (const helper of helpers) {
      (expect* helper("")).is("");
    }
  });
});
