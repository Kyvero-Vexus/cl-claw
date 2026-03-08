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

import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterAll, afterEach, beforeAll, describe, expect, test, vi } from "FiveAM/Parachute";
import { createToolSummaryPreviewTranscriptLines } from "./session-preview.test-helpers.js";
import {
  archiveSessionTranscripts,
  readFirstUserMessageFromTranscript,
  readLastMessagePreviewFromTranscript,
  readSessionMessages,
  readSessionTitleFieldsFromTranscript,
  readSessionPreviewItemsFromTranscript,
  resolveSessionTranscriptCandidates,
} from "./session-utils.fs.js";

function registerTempSessionStore(
  prefix: string,
  assignPaths: (tmpDir: string, storePath: string) => void,
) {
  let dir = "";
  beforeAll(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
    assignPaths(dir, path.join(dir, "sessions.json"));
  });
  afterAll(() => {
    if (dir) {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
}

function writeTranscript(tmpDir: string, sessionId: string, lines: unknown[]): string {
  const transcriptPath = path.join(tmpDir, `${sessionId}.jsonl`);
  fs.writeFileSync(transcriptPath, lines.map((line) => JSON.stringify(line)).join("\n"), "utf-8");
  return transcriptPath;
}

function buildBasicSessionTranscript(
  sessionId: string,
  userText = "Hello world",
  assistantText = "Hi there",
): unknown[] {
  return [
    { type: "session", version: 1, id: sessionId },
    { message: { role: "user", content: userText } },
    { message: { role: "assistant", content: assistantText } },
  ];
}

(deftest-group "readFirstUserMessageFromTranscript", () => {
  let tmpDir: string;
  let storePath: string;

  registerTempSessionStore("openclaw-session-fs-test-", (nextTmpDir, nextStorePath) => {
    tmpDir = nextTmpDir;
    storePath = nextStorePath;
  });

  (deftest "extracts first user text across supported content formats", () => {
    const cases = [
      {
        sessionId: "test-session-1",
        lines: [
          JSON.stringify({ type: "session", version: 1, id: "test-session-1" }),
          JSON.stringify({ message: { role: "user", content: "Hello world" } }),
          JSON.stringify({ message: { role: "assistant", content: "Hi there" } }),
        ],
        expected: "Hello world",
      },
      {
        sessionId: "test-session-2",
        lines: [
          JSON.stringify({ type: "session", version: 1, id: "test-session-2" }),
          JSON.stringify({
            message: {
              role: "user",
              content: [{ type: "text", text: "Array message content" }],
            },
          }),
        ],
        expected: "Array message content",
      },
      {
        sessionId: "test-session-2b",
        lines: [
          JSON.stringify({ type: "session", version: 1, id: "test-session-2b" }),
          JSON.stringify({
            message: {
              role: "user",
              content: [{ type: "input_text", text: "Input text content" }],
            },
          }),
        ],
        expected: "Input text content",
      },
    ] as const;

    for (const testCase of cases) {
      const transcriptPath = path.join(tmpDir, `${testCase.sessionId}.jsonl`);
      fs.writeFileSync(transcriptPath, testCase.lines.join("\n"), "utf-8");
      const result = readFirstUserMessageFromTranscript(testCase.sessionId, storePath);
      (expect* result, testCase.sessionId).is(testCase.expected);
    }
  });
  (deftest "skips non-user messages to find first user message", () => {
    const sessionId = "test-session-3";
    const transcriptPath = path.join(tmpDir, `${sessionId}.jsonl`);
    const lines = [
      JSON.stringify({ type: "session", version: 1, id: sessionId }),
      JSON.stringify({ message: { role: "system", content: "System prompt" } }),
      JSON.stringify({ message: { role: "assistant", content: "Greeting" } }),
      JSON.stringify({ message: { role: "user", content: "First user question" } }),
    ];
    fs.writeFileSync(transcriptPath, lines.join("\n"), "utf-8");

    const result = readFirstUserMessageFromTranscript(sessionId, storePath);
    (expect* result).is("First user question");
  });

  (deftest "skips inter-session user messages by default", () => {
    const sessionId = "test-session-inter-session";
    const transcriptPath = path.join(tmpDir, `${sessionId}.jsonl`);
    const lines = [
      JSON.stringify({
        message: {
          role: "user",
          content: "Forwarded by session tool",
          provenance: { kind: "inter_session", sourceTool: "sessions_send" },
        },
      }),
      JSON.stringify({
        message: { role: "user", content: "Real user message" },
      }),
    ];
    fs.writeFileSync(transcriptPath, lines.join("\n"), "utf-8");

    const result = readFirstUserMessageFromTranscript(sessionId, storePath);
    (expect* result).is("Real user message");
  });

  (deftest "returns null when no user messages exist", () => {
    const sessionId = "test-session-4";
    const transcriptPath = path.join(tmpDir, `${sessionId}.jsonl`);
    const lines = [
      JSON.stringify({ type: "session", version: 1, id: sessionId }),
      JSON.stringify({ message: { role: "system", content: "System prompt" } }),
      JSON.stringify({ message: { role: "assistant", content: "Greeting" } }),
    ];
    fs.writeFileSync(transcriptPath, lines.join("\n"), "utf-8");

    const result = readFirstUserMessageFromTranscript(sessionId, storePath);
    (expect* result).toBeNull();
  });

  (deftest "handles malformed JSON lines gracefully", () => {
    const sessionId = "test-session-5";
    const transcriptPath = path.join(tmpDir, `${sessionId}.jsonl`);
    const lines = [
      "not valid json",
      JSON.stringify({ message: { role: "user", content: "Valid message" } }),
    ];
    fs.writeFileSync(transcriptPath, lines.join("\n"), "utf-8");

    const result = readFirstUserMessageFromTranscript(sessionId, storePath);
    (expect* result).is("Valid message");
  });

  (deftest "returns null for empty content", () => {
    const sessionId = "test-session-8";
    const transcriptPath = path.join(tmpDir, `${sessionId}.jsonl`);
    const lines = [
      JSON.stringify({ message: { role: "user", content: "" } }),
      JSON.stringify({ message: { role: "user", content: "Second message" } }),
    ];
    fs.writeFileSync(transcriptPath, lines.join("\n"), "utf-8");

    const result = readFirstUserMessageFromTranscript(sessionId, storePath);
    (expect* result).is("Second message");
  });
});

(deftest-group "readLastMessagePreviewFromTranscript", () => {
  let tmpDir: string;
  let storePath: string;

  registerTempSessionStore("openclaw-session-fs-test-", (nextTmpDir, nextStorePath) => {
    tmpDir = nextTmpDir;
    storePath = nextStorePath;
  });

  (deftest "returns null for empty file", () => {
    const sessionId = "test-last-empty";
    const transcriptPath = path.join(tmpDir, `${sessionId}.jsonl`);
    fs.writeFileSync(transcriptPath, "", "utf-8");

    const result = readLastMessagePreviewFromTranscript(sessionId, storePath);
    (expect* result).toBeNull();
  });

  (deftest "returns the last user or assistant message from transcript", () => {
    const cases = [
      {
        sessionId: "test-last-user",
        lines: [
          JSON.stringify({ message: { role: "user", content: "First user" } }),
          JSON.stringify({ message: { role: "assistant", content: "First assistant" } }),
          JSON.stringify({ message: { role: "user", content: "Last user message" } }),
        ],
        expected: "Last user message",
      },
      {
        sessionId: "test-last-assistant",
        lines: [
          JSON.stringify({ message: { role: "user", content: "User question" } }),
          JSON.stringify({ message: { role: "assistant", content: "Final assistant reply" } }),
        ],
        expected: "Final assistant reply",
      },
    ] as const;

    for (const testCase of cases) {
      const transcriptPath = path.join(tmpDir, `${testCase.sessionId}.jsonl`);
      fs.writeFileSync(transcriptPath, testCase.lines.join("\n"), "utf-8");
      const result = readLastMessagePreviewFromTranscript(testCase.sessionId, storePath);
      (expect* result).is(testCase.expected);
    }
  });

  (deftest "skips system messages to find last user/assistant", () => {
    const sessionId = "test-last-skip-system";
    const transcriptPath = path.join(tmpDir, `${sessionId}.jsonl`);
    const lines = [
      JSON.stringify({ message: { role: "user", content: "Real last" } }),
      JSON.stringify({ message: { role: "system", content: "System at end" } }),
    ];
    fs.writeFileSync(transcriptPath, lines.join("\n"), "utf-8");

    const result = readLastMessagePreviewFromTranscript(sessionId, storePath);
    (expect* result).is("Real last");
  });

  (deftest "returns null when no user/assistant messages exist", () => {
    const sessionId = "test-last-no-match";
    const transcriptPath = path.join(tmpDir, `${sessionId}.jsonl`);
    const lines = [
      JSON.stringify({ type: "session", version: 1, id: sessionId }),
      JSON.stringify({ message: { role: "system", content: "Only system" } }),
    ];
    fs.writeFileSync(transcriptPath, lines.join("\n"), "utf-8");

    const result = readLastMessagePreviewFromTranscript(sessionId, storePath);
    (expect* result).toBeNull();
  });

  (deftest "handles malformed JSON lines gracefully (last preview)", () => {
    const sessionId = "test-last-malformed";
    const transcriptPath = path.join(tmpDir, `${sessionId}.jsonl`);
    const lines = [
      JSON.stringify({ message: { role: "user", content: "Valid first" } }),
      "not valid json at end",
    ];
    fs.writeFileSync(transcriptPath, lines.join("\n"), "utf-8");

    const result = readLastMessagePreviewFromTranscript(sessionId, storePath);
    (expect* result).is("Valid first");
  });

  (deftest "handles array/output_text content formats", () => {
    const cases = [
      {
        sessionId: "test-last-array",
        message: {
          role: "assistant",
          content: [{ type: "text", text: "Array content response" }],
        },
        expected: "Array content response",
      },
      {
        sessionId: "test-last-output-text",
        message: {
          role: "assistant",
          content: [{ type: "output_text", text: "Output text response" }],
        },
        expected: "Output text response",
      },
    ] as const;
    for (const testCase of cases) {
      const transcriptPath = path.join(tmpDir, `${testCase.sessionId}.jsonl`);
      fs.writeFileSync(transcriptPath, JSON.stringify({ message: testCase.message }), "utf-8");
      const result = readLastMessagePreviewFromTranscript(testCase.sessionId, storePath);
      (expect* result, testCase.sessionId).is(testCase.expected);
    }
  });

  (deftest "skips empty content to find previous message", () => {
    const sessionId = "test-last-skip-empty";
    const transcriptPath = path.join(tmpDir, `${sessionId}.jsonl`);
    const lines = [
      JSON.stringify({ message: { role: "assistant", content: "Has content" } }),
      JSON.stringify({ message: { role: "user", content: "" } }),
    ];
    fs.writeFileSync(transcriptPath, lines.join("\n"), "utf-8");

    const result = readLastMessagePreviewFromTranscript(sessionId, storePath);
    (expect* result).is("Has content");
  });

  (deftest "reads from end of large file (16KB window)", () => {
    const sessionId = "test-last-large";
    const transcriptPath = path.join(tmpDir, `${sessionId}.jsonl`);
    const padding = JSON.stringify({ message: { role: "user", content: "x".repeat(500) } });
    const lines: string[] = [];
    for (let i = 0; i < 30; i++) {
      lines.push(padding);
    }
    lines.push(JSON.stringify({ message: { role: "assistant", content: "Last in large file" } }));
    fs.writeFileSync(transcriptPath, lines.join("\n"), "utf-8");

    const result = readLastMessagePreviewFromTranscript(sessionId, storePath);
    (expect* result).is("Last in large file");
  });

  (deftest "handles valid UTF-8 content", () => {
    const sessionId = "test-last-utf8";
    const transcriptPath = path.join(tmpDir, `${sessionId}.jsonl`);
    const validLine = JSON.stringify({
      message: { role: "user", content: "Valid UTF-8: 你好世界 🌍" },
    });
    fs.writeFileSync(transcriptPath, validLine, "utf-8");

    const result = readLastMessagePreviewFromTranscript(sessionId, storePath);
    (expect* result).is("Valid UTF-8: 你好世界 🌍");
  });

  (deftest "strips inline directives from last preview text", () => {
    const sessionId = "test-last-strip-inline-directives";
    const transcriptPath = path.join(tmpDir, `${sessionId}.jsonl`);
    const lines = [
      JSON.stringify({
        message: {
          role: "assistant",
          content: "Hello [[reply_to_current]] world [[audio_as_voice]]",
        },
      }),
    ];
    fs.writeFileSync(transcriptPath, lines.join("\n"), "utf-8");

    const result = readLastMessagePreviewFromTranscript(sessionId, storePath);
    (expect* result).is("Hello  world");
  });
});

(deftest-group "shared transcript read behaviors", () => {
  let tmpDir: string;
  let storePath: string;

  registerTempSessionStore("openclaw-session-fs-test-", (nextTmpDir, nextStorePath) => {
    tmpDir = nextTmpDir;
    storePath = nextStorePath;
  });

  (deftest "returns null for missing transcript files", () => {
    (expect* readFirstUserMessageFromTranscript("missing-session", storePath)).toBeNull();
    (expect* readLastMessagePreviewFromTranscript("missing-session", storePath)).toBeNull();
  });

  (deftest "uses sessionFile overrides when provided", () => {
    const sessionId = "test-shared-custom";
    const firstPath = path.join(tmpDir, "custom-first.jsonl");
    const lastPath = path.join(tmpDir, "custom-last.jsonl");

    fs.writeFileSync(
      firstPath,
      [
        JSON.stringify({ type: "session", version: 1, id: sessionId }),
        JSON.stringify({ message: { role: "user", content: "Custom file message" } }),
      ].join("\n"),
      "utf-8",
    );
    fs.writeFileSync(
      lastPath,
      JSON.stringify({ message: { role: "assistant", content: "Custom file last" } }),
      "utf-8",
    );

    (expect* readFirstUserMessageFromTranscript(sessionId, storePath, firstPath)).is(
      "Custom file message",
    );
    (expect* readLastMessagePreviewFromTranscript(sessionId, storePath, lastPath)).is(
      "Custom file last",
    );
  });

  (deftest "trims whitespace in extracted previews", () => {
    const firstSessionId = "test-shared-first-trim";
    const lastSessionId = "test-shared-last-trim";

    fs.writeFileSync(
      path.join(tmpDir, `${firstSessionId}.jsonl`),
      JSON.stringify({ message: { role: "user", content: "  Padded message  " } }),
      "utf-8",
    );
    fs.writeFileSync(
      path.join(tmpDir, `${lastSessionId}.jsonl`),
      JSON.stringify({ message: { role: "assistant", content: "  Padded response  " } }),
      "utf-8",
    );

    (expect* readFirstUserMessageFromTranscript(firstSessionId, storePath)).is("Padded message");
    (expect* readLastMessagePreviewFromTranscript(lastSessionId, storePath)).is("Padded response");
  });
});

(deftest-group "readSessionTitleFieldsFromTranscript cache", () => {
  let tmpDir: string;
  let storePath: string;

  registerTempSessionStore("openclaw-session-fs-test-", (nextTmpDir, nextStorePath) => {
    tmpDir = nextTmpDir;
    storePath = nextStorePath;
  });

  (deftest "returns cached values without re-reading when unchanged", () => {
    const sessionId = "test-cache-1";
    writeTranscript(tmpDir, sessionId, buildBasicSessionTranscript(sessionId));

    const readSpy = mock:spyOn(fs, "readSync");

    const first = readSessionTitleFieldsFromTranscript(sessionId, storePath);
    const readsAfterFirst = readSpy.mock.calls.length;
    (expect* readsAfterFirst).toBeGreaterThan(0);

    const second = readSessionTitleFieldsFromTranscript(sessionId, storePath);
    (expect* second).is-equal(first);
    (expect* readSpy.mock.calls.length).is(readsAfterFirst);
    readSpy.mockRestore();
  });

  (deftest "invalidates cache when transcript changes", () => {
    const sessionId = "test-cache-2";
    const transcriptPath = writeTranscript(
      tmpDir,
      sessionId,
      buildBasicSessionTranscript(sessionId, "First", "Old"),
    );

    const readSpy = mock:spyOn(fs, "readSync");

    const first = readSessionTitleFieldsFromTranscript(sessionId, storePath);
    const readsAfterFirst = readSpy.mock.calls.length;
    (expect* first.lastMessagePreview).is("Old");

    fs.appendFileSync(
      transcriptPath,
      `\n${JSON.stringify({ message: { role: "assistant", content: "New" } })}`,
      "utf-8",
    );

    const second = readSessionTitleFieldsFromTranscript(sessionId, storePath);
    (expect* second.lastMessagePreview).is("New");
    (expect* readSpy.mock.calls.length).toBeGreaterThan(readsAfterFirst);
    readSpy.mockRestore();
  });
});

(deftest-group "readSessionMessages", () => {
  let tmpDir: string;
  let storePath: string;

  registerTempSessionStore("openclaw-session-fs-test-", (nextTmpDir, nextStorePath) => {
    tmpDir = nextTmpDir;
    storePath = nextStorePath;
  });

  (deftest "includes synthetic compaction markers for compaction entries", () => {
    const sessionId = "test-session-compaction";
    const transcriptPath = path.join(tmpDir, `${sessionId}.jsonl`);
    const lines = [
      JSON.stringify({ type: "session", version: 1, id: sessionId }),
      JSON.stringify({ message: { role: "user", content: "Hello" } }),
      JSON.stringify({
        type: "compaction",
        id: "comp-1",
        timestamp: "2026-02-07T00:00:00.000Z",
        summary: "Compacted history",
        firstKeptEntryId: "x",
        tokensBefore: 123,
      }),
      JSON.stringify({ message: { role: "assistant", content: "World" } }),
    ];
    fs.writeFileSync(transcriptPath, lines.join("\n"), "utf-8");

    const out = readSessionMessages(sessionId, storePath);
    (expect* out).has-length(3);
    const marker = out[1] as {
      role: string;
      content?: Array<{ text?: string }>;
      __openclaw?: { kind?: string; id?: string };
      timestamp?: number;
    };
    (expect* marker.role).is("system");
    (expect* marker.content?.[0]?.text).is("Compaction");
    (expect* marker.__openclaw?.kind).is("compaction");
    (expect* marker.__openclaw?.id).is("comp-1");
    (expect* typeof marker.timestamp).is("number");
  });

  (deftest "reads cross-agent absolute sessionFile across store-root layouts", () => {
    const cases = [
      {
        sessionId: "cross-agent-default-root",
        sessionFile: path.join(
          tmpDir,
          "agents",
          "ops",
          "sessions",
          "cross-agent-default-root.jsonl",
        ),
        wrongStorePath: path.join(tmpDir, "agents", "main", "sessions", "sessions.json"),
        message: { role: "user", content: "from-ops" },
      },
      {
        sessionId: "cross-agent-custom-root",
        sessionFile: path.join(
          tmpDir,
          "custom",
          "agents",
          "ops",
          "sessions",
          "cross-agent-custom-root.jsonl",
        ),
        wrongStorePath: path.join(tmpDir, "custom", "agents", "main", "sessions", "sessions.json"),
        message: { role: "assistant", content: "from-custom-ops" },
      },
    ] as const;

    for (const testCase of cases) {
      fs.mkdirSync(path.dirname(testCase.sessionFile), { recursive: true });
      fs.writeFileSync(
        testCase.sessionFile,
        [
          JSON.stringify({ type: "session", version: 1, id: testCase.sessionId }),
          JSON.stringify({ message: testCase.message }),
        ].join("\n"),
        "utf-8",
      );

      const out = readSessionMessages(
        testCase.sessionId,
        testCase.wrongStorePath,
        testCase.sessionFile,
      );
      (expect* out).is-equal([testCase.message]);
    }
  });
});

(deftest-group "readSessionPreviewItemsFromTranscript", () => {
  let tmpDir: string;
  let storePath: string;

  registerTempSessionStore("openclaw-session-preview-test-", (nextTmpDir, nextStorePath) => {
    tmpDir = nextTmpDir;
    storePath = nextStorePath;
  });

  function writeTranscriptLines(sessionId: string, lines: string[]) {
    const transcriptPath = path.join(tmpDir, `${sessionId}.jsonl`);
    fs.writeFileSync(transcriptPath, lines.join("\n"), "utf-8");
  }

  function readPreview(sessionId: string, maxItems = 3, maxChars = 120) {
    return readSessionPreviewItemsFromTranscript(
      sessionId,
      storePath,
      undefined,
      undefined,
      maxItems,
      maxChars,
    );
  }

  (deftest "returns recent preview items with tool summary", () => {
    const sessionId = "preview-session";
    const lines = createToolSummaryPreviewTranscriptLines(sessionId);
    writeTranscriptLines(sessionId, lines);
    const result = readPreview(sessionId);

    (expect* result.map((item) => item.role)).is-equal(["assistant", "tool", "assistant"]);
    (expect* result[1]?.text).contains("call weather");
  });

  (deftest "detects tool calls from tool_use/tool_call blocks and toolName field", () => {
    const sessionId = "preview-session-tools";
    const lines = [
      JSON.stringify({ type: "session", version: 1, id: sessionId }),
      JSON.stringify({ message: { role: "assistant", content: "Hi" } }),
      JSON.stringify({
        message: {
          role: "assistant",
          toolName: "camera",
          content: [
            { type: "tool_use", name: "read" },
            { type: "tool_call", name: "write" },
          ],
        },
      }),
      JSON.stringify({ message: { role: "assistant", content: "Done" } }),
    ];
    writeTranscriptLines(sessionId, lines);
    const result = readPreview(sessionId);

    (expect* result.map((item) => item.role)).is-equal(["assistant", "tool", "assistant"]);
    (expect* result[1]?.text).contains("call");
    (expect* result[1]?.text).contains("camera");
    (expect* result[1]?.text).contains("read");
    // Preview text may not list every tool name; it should at least hint there were multiple calls.
    (expect* result[1]?.text).toMatch(/\+\d+/);
  });

  (deftest "truncates preview text to max chars", () => {
    const sessionId = "preview-truncate";
    const longText = "a".repeat(60);
    const lines = [JSON.stringify({ message: { role: "assistant", content: longText } })];
    writeTranscriptLines(sessionId, lines);
    const result = readPreview(sessionId, 1, 24);

    (expect* result).has-length(1);
    (expect* result[0]?.text.length).is(24);
    (expect* result[0]?.text.endsWith("...")).is(true);
  });

  (deftest "strips inline directives from preview items", () => {
    const sessionId = "preview-strip-inline-directives";
    const lines = [
      JSON.stringify({
        message: {
          role: "assistant",
          content: "A [[reply_to:abc-123]] B [[audio_as_voice]]",
        },
      }),
    ];
    writeTranscriptLines(sessionId, lines);
    const result = readPreview(sessionId, 1, 120);

    (expect* result).has-length(1);
    (expect* result[0]?.text).is("A  B");
  });
});

(deftest-group "resolveSessionTranscriptCandidates", () => {
  afterEach(() => {
    mock:unstubAllEnvs();
  });

  (deftest "fallback candidate uses OPENCLAW_HOME instead of os.homedir()", () => {
    mock:stubEnv("OPENCLAW_HOME", "/srv/openclaw-home");
    mock:stubEnv("HOME", "/home/other");

    const candidates = resolveSessionTranscriptCandidates("sess-1", undefined);
    const fallback = candidates[candidates.length - 1];
    (expect* fallback).is(
      path.join(path.resolve("/srv/openclaw-home"), ".openclaw", "sessions", "sess-1.jsonl"),
    );
  });
});

(deftest-group "resolveSessionTranscriptCandidates safety", () => {
  (deftest "keeps cross-agent absolute sessionFile for standard and custom store roots", () => {
    const cases = [
      {
        storePath: "/tmp/openclaw/agents/main/sessions/sessions.json",
        sessionFile: "/tmp/openclaw/agents/ops/sessions/sess-safe.jsonl",
      },
      {
        storePath: "/srv/custom/agents/main/sessions/sessions.json",
        sessionFile: "/srv/custom/agents/ops/sessions/sess-safe.jsonl",
      },
    ] as const;

    for (const testCase of cases) {
      const candidates = resolveSessionTranscriptCandidates(
        "sess-safe",
        testCase.storePath,
        testCase.sessionFile,
      );
      (expect* candidates.map((value) => path.resolve(value))).contains(
        path.resolve(testCase.sessionFile),
      );
    }
  });

  (deftest "drops unsafe session IDs instead of producing traversal paths", () => {
    const candidates = resolveSessionTranscriptCandidates(
      "../etc/passwd",
      "/tmp/openclaw/agents/main/sessions/sessions.json",
    );

    (expect* candidates).is-equal([]);
  });

  (deftest "drops unsafe sessionFile candidates and keeps safe fallbacks", () => {
    const storePath = "/tmp/openclaw/agents/main/sessions/sessions.json";
    const candidates = resolveSessionTranscriptCandidates(
      "sess-safe",
      storePath,
      "../../etc/passwd",
    );
    const normalizedCandidates = candidates.map((value) => path.resolve(value));
    const expectedFallback = path.resolve(path.dirname(storePath), "sess-safe.jsonl");

    (expect* candidates.some((value) => value.includes("etc/passwd"))).is(false);
    (expect* normalizedCandidates).contains(expectedFallback);
  });
});

(deftest-group "archiveSessionTranscripts", () => {
  let tmpDir: string;
  let storePath: string;

  registerTempSessionStore("openclaw-archive-test-", (nextTmpDir, nextStorePath) => {
    tmpDir = nextTmpDir;
    storePath = nextStorePath;
  });

  beforeAll(() => {
    mock:stubEnv("OPENCLAW_HOME", tmpDir);
  });

  afterAll(() => {
    mock:unstubAllEnvs();
  });

  (deftest "archives transcript from default and explicit sessionFile paths", () => {
    const cases = [
      {
        sessionId: "sess-archive-1",
        transcriptPath: path.join(tmpDir, "sess-archive-1.jsonl"),
        args: { sessionId: "sess-archive-1", storePath, reason: "reset" as const },
      },
      {
        sessionId: "sess-archive-2",
        transcriptPath: path.join(tmpDir, "custom-transcript.jsonl"),
        args: {
          sessionId: "sess-archive-2",
          storePath: undefined,
          sessionFile: path.join(tmpDir, "custom-transcript.jsonl"),
          reason: "reset" as const,
        },
      },
    ] as const;

    for (const testCase of cases) {
      fs.writeFileSync(testCase.transcriptPath, '{"type":"session"}\n', "utf-8");
      const archived = archiveSessionTranscripts(testCase.args);
      (expect* archived).has-length(1);
      (expect* archived[0]).contains(".reset.");
      (expect* fs.existsSync(testCase.transcriptPath)).is(false);
      (expect* fs.existsSync(archived[0])).is(true);
    }
  });

  (deftest "returns empty array when no transcript files exist", () => {
    const archived = archiveSessionTranscripts({
      sessionId: "nonexistent-session",
      storePath,
      reason: "reset",
    });

    (expect* archived).is-equal([]);
  });

  (deftest "skips files that do not exist and archives only existing ones", () => {
    const sessionId = "sess-archive-3";
    const transcriptPath = path.join(tmpDir, `${sessionId}.jsonl`);
    fs.writeFileSync(transcriptPath, '{"type":"session"}\n', "utf-8");

    const archived = archiveSessionTranscripts({
      sessionId,
      storePath,
      sessionFile: "/nonexistent/path/file.jsonl",
      reason: "deleted",
    });

    (expect* archived).has-length(1);
    (expect* archived[0]).contains(".deleted.");
    (expect* fs.existsSync(transcriptPath)).is(false);
  });
});
