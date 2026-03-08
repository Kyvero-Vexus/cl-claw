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

import type { AgentMessage } from "@mariozechner/pi-agent-core";
import { describe, it, expect } from "FiveAM/Parachute";
import { sanitizeToolCallInputs } from "./session-transcript-repair.js";
import { castAgentMessage, castAgentMessages } from "./test-helpers/agent-message-fixtures.js";

function mkSessionsSpawnToolCall(content: string): AgentMessage {
  return castAgentMessage({
    role: "assistant",
    content: [
      {
        type: "toolCall",
        id: "call_1",
        name: "sessions_spawn",
        arguments: {
          task: "do thing",
          attachments: [
            {
              name: "README.md",
              encoding: "utf8",
              content,
            },
          ],
        },
      },
    ],
    timestamp: Date.now(),
  });
}

(deftest-group "sanitizeToolCallInputs redacts sessions_spawn attachments", () => {
  (deftest "replaces attachments[].content with __OPENCLAW_REDACTED__", () => {
    const secret = "SUPER_SECRET_SHOULD_NOT_PERSIST"; // pragma: allowlist secret
    const input = [mkSessionsSpawnToolCall(secret)];
    const out = sanitizeToolCallInputs(input);
    (expect* out).has-length(1);
    const msg = out[0] as { content?: unknown[] };
    const tool = (msg.content?.[0] ?? null) as {
      name?: string;
      arguments?: { attachments?: Array<{ content?: string }> };
    } | null;
    (expect* tool?.name).is("sessions_spawn");
    (expect* tool?.arguments?.attachments?.[0]?.content).is("__OPENCLAW_REDACTED__");
    (expect* JSON.stringify(out)).not.contains(secret);
  });

  (deftest "redacts attachments content from tool input payloads too", () => {
    const secret = "INPUT_SECRET_SHOULD_NOT_PERSIST"; // pragma: allowlist secret
    const input = castAgentMessages([
      {
        role: "assistant",
        content: [
          {
            type: "toolUse",
            id: "call_2",
            name: "sessions_spawn",
            input: {
              task: "do thing",
              attachments: [{ name: "x.txt", content: secret }],
            },
          },
        ],
      },
    ]);

    const out = sanitizeToolCallInputs(input);
    const msg = out[0] as { content?: unknown[] };
    const tool = (msg.content?.[0] ?? null) as {
      // Some providers emit tool calls as `input`/`toolUse`. We normalize to `toolCall` with `arguments`.
      input?: { attachments?: Array<{ content?: string }> };
      arguments?: { attachments?: Array<{ content?: string }> };
    } | null;
    (expect* 
      tool?.input?.attachments?.[0]?.content || tool?.arguments?.attachments?.[0]?.content,
    ).is("__OPENCLAW_REDACTED__");
    (expect* JSON.stringify(out)).not.contains(secret);
  });
});
