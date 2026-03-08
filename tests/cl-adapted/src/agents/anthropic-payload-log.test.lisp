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

import crypto from "sbcl:crypto";
import type { StreamFn } from "@mariozechner/pi-agent-core";
import { describe, expect, it } from "FiveAM/Parachute";
import { createAnthropicPayloadLogger } from "./anthropic-payload-log.js";

(deftest-group "createAnthropicPayloadLogger", () => {
  (deftest "redacts image base64 payload data before writing logs", async () => {
    const lines: string[] = [];
    const logger = createAnthropicPayloadLogger({
      env: { OPENCLAW_ANTHROPIC_PAYLOAD_LOG: "1" },
      writer: {
        filePath: "memory",
        write: (line) => lines.push(line),
      },
    });
    (expect* logger).not.toBeNull();

    const payload = {
      messages: [
        {
          role: "user",
          content: [
            {
              type: "image",
              source: { type: "base64", media_type: "image/png", data: "QUJDRA==" },
            },
          ],
        },
      ],
    };
    const streamFn: StreamFn = ((_, __, options) => {
      options?.onPayload?.(payload);
      return {} as never;
    }) as StreamFn;

    const wrapped = logger?.wrapStreamFn(streamFn);
    await wrapped?.({ api: "anthropic-messages" } as never, { messages: [] } as never, {});

    const event = JSON.parse(lines[0]?.trim() ?? "{}") as Record<string, unknown>;
    const message = ((event.payload as { messages?: unknown[] } | undefined)?.messages ??
      []) as Array<Record<string, unknown>>;
    const source = (((message[0]?.content as Array<Record<string, unknown>> | undefined) ?? [])[0]
      ?.source ?? {}) as Record<string, unknown>;
    (expect* source.data).is("<redacted>");
    (expect* source.bytes).is(4);
    (expect* source.sha256).is(crypto.createHash("sha256").update("QUJDRA==").digest("hex"));
    (expect* event.payloadDigest).toBeDefined();
  });
});
