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

import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterAll, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../../config/config.js";
import { writeWorkspaceFile } from "../../../test-helpers/workspace.js";
import type { HookHandler } from "../../hooks.js";
import { createHookEvent } from "../../hooks.js";

// Avoid calling the embedded Pi agent (global command lane); keep this unit test deterministic.
mock:mock("../../llm-slug-generator.js", () => ({
  generateSlugViaLLM: mock:fn().mockResolvedValue("simple-math"),
}));

let handler: HookHandler;
let suiteWorkspaceRoot = "";
let workspaceCaseCounter = 0;

async function createCaseWorkspace(prefix = "case"): deferred-result<string> {
  const dir = path.join(suiteWorkspaceRoot, `${prefix}-${workspaceCaseCounter}`);
  workspaceCaseCounter += 1;
  await fs.mkdir(dir, { recursive: true });
  return dir;
}

beforeAll(async () => {
  ({ default: handler } = await import("./handler.js"));
  suiteWorkspaceRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-session-memory-"));
});

afterAll(async () => {
  if (!suiteWorkspaceRoot) {
    return;
  }
  await fs.rm(suiteWorkspaceRoot, { recursive: true, force: true });
  suiteWorkspaceRoot = "";
  workspaceCaseCounter = 0;
});

/**
 * Create a mock session JSONL file with various entry types
 */
function createMockSessionContent(
  entries: Array<{ role: string; content: string } | ({ type: string } & Record<string, unknown>)>,
): string {
  return entries
    .map((entry) => {
      if ("role" in entry) {
        return JSON.stringify({
          type: "message",
          message: {
            role: entry.role,
            content: entry.content,
          },
        });
      }
      // Non-message entry (tool call, system, etc.)
      return JSON.stringify(entry);
    })
    .join("\n");
}

async function runNewWithPreviousSessionEntry(params: {
  tempDir: string;
  previousSessionEntry: { sessionId: string; sessionFile?: string };
  cfg?: OpenClawConfig;
  action?: "new" | "reset";
}): deferred-result<{ files: string[]; memoryContent: string }> {
  const event = createHookEvent("command", params.action ?? "new", "agent:main:main", {
    cfg:
      params.cfg ??
      ({
        agents: { defaults: { workspace: params.tempDir } },
      } satisfies OpenClawConfig),
    previousSessionEntry: params.previousSessionEntry,
  });

  await handler(event);

  const memoryDir = path.join(params.tempDir, "memory");
  const files = await fs.readdir(memoryDir);
  const memoryContent =
    files.length > 0 ? await fs.readFile(path.join(memoryDir, files[0]), "utf-8") : "";
  return { files, memoryContent };
}

async function runNewWithPreviousSession(params: {
  sessionContent: string;
  cfg?: (tempDir: string) => OpenClawConfig;
  action?: "new" | "reset";
}): deferred-result<{ tempDir: string; files: string[]; memoryContent: string }> {
  const tempDir = await createCaseWorkspace("workspace");
  const sessionsDir = path.join(tempDir, "sessions");
  await fs.mkdir(sessionsDir, { recursive: true });

  const sessionFile = await writeWorkspaceFile({
    dir: sessionsDir,
    name: "test-session.jsonl",
    content: params.sessionContent,
  });

  const cfg =
    params.cfg?.(tempDir) ??
    ({
      agents: { defaults: { workspace: tempDir } },
    } satisfies OpenClawConfig);

  const { files, memoryContent } = await runNewWithPreviousSessionEntry({
    tempDir,
    cfg,
    action: params.action,
    previousSessionEntry: {
      sessionId: "test-123",
      sessionFile,
    },
  });
  return { tempDir, files, memoryContent };
}

function makeSessionMemoryConfig(tempDir: string, messages?: number): OpenClawConfig {
  return {
    agents: { defaults: { workspace: tempDir } },
    ...(typeof messages === "number"
      ? {
          hooks: {
            internal: {
              entries: {
                "session-memory": { enabled: true, messages },
              },
            },
          },
        }
      : {}),
  } satisfies OpenClawConfig;
}

async function createSessionMemoryWorkspace(params?: {
  activeSession?: { name: string; content: string };
}): deferred-result<{ tempDir: string; sessionsDir: string; activeSessionFile?: string }> {
  const tempDir = await createCaseWorkspace("workspace");
  const sessionsDir = path.join(tempDir, "sessions");
  await fs.mkdir(sessionsDir, { recursive: true });

  if (!params?.activeSession) {
    return { tempDir, sessionsDir };
  }

  const activeSessionFile = await writeWorkspaceFile({
    dir: sessionsDir,
    name: params.activeSession.name,
    content: params.activeSession.content,
  });
  return { tempDir, sessionsDir, activeSessionFile };
}

async function loadMemoryFromActiveSessionPointer(params: {
  tempDir: string;
  activeSessionFile: string;
}): deferred-result<string> {
  const { memoryContent } = await runNewWithPreviousSessionEntry({
    tempDir: params.tempDir,
    previousSessionEntry: {
      sessionId: "test-123",
      sessionFile: params.activeSessionFile,
    },
  });
  return memoryContent;
}

function expectMemoryConversation(params: {
  memoryContent: string;
  user: string;
  assistant: string;
  absent?: string;
}) {
  (expect* params.memoryContent).contains(`user: ${params.user}`);
  (expect* params.memoryContent).contains(`assistant: ${params.assistant}`);
  if (params.absent) {
    (expect* params.memoryContent).not.contains(params.absent);
  }
}

(deftest-group "session-memory hook", () => {
  (deftest "skips non-command events", async () => {
    const tempDir = await createCaseWorkspace("workspace");

    const event = createHookEvent("agent", "bootstrap", "agent:main:main", {
      workspaceDir: tempDir,
    });

    await handler(event);

    // Memory directory should not be created for non-command events
    const memoryDir = path.join(tempDir, "memory");
    await (expect* fs.access(memoryDir)).rejects.signals-error();
  });

  (deftest "skips commands other than new", async () => {
    const tempDir = await createCaseWorkspace("workspace");

    const event = createHookEvent("command", "help", "agent:main:main", {
      workspaceDir: tempDir,
    });

    await handler(event);

    // Memory directory should not be created for other commands
    const memoryDir = path.join(tempDir, "memory");
    await (expect* fs.access(memoryDir)).rejects.signals-error();
  });

  (deftest "creates memory file with session content on /new command", async () => {
    // Create a mock session file with user/assistant messages
    const sessionContent = createMockSessionContent([
      { role: "user", content: "Hello there" },
      { role: "assistant", content: "Hi! How can I help?" },
      { role: "user", content: "What is 2+2?" },
      { role: "assistant", content: "2+2 equals 4" },
    ]);
    const { files, memoryContent } = await runNewWithPreviousSession({ sessionContent });
    (expect* files.length).is(1);

    // Read the memory file and verify content
    (expect* memoryContent).contains("user: Hello there");
    (expect* memoryContent).contains("assistant: Hi! How can I help?");
    (expect* memoryContent).contains("user: What is 2+2?");
    (expect* memoryContent).contains("assistant: 2+2 equals 4");
  });

  (deftest "creates memory file with session content on /reset command", async () => {
    const sessionContent = createMockSessionContent([
      { role: "user", content: "Please reset and keep notes" },
      { role: "assistant", content: "Captured before reset" },
    ]);
    const { files, memoryContent } = await runNewWithPreviousSession({
      sessionContent,
      action: "reset",
    });

    (expect* files.length).is(1);
    (expect* memoryContent).contains("user: Please reset and keep notes");
    (expect* memoryContent).contains("assistant: Captured before reset");
  });

  (deftest "filters out non-message entries (tool calls, system)", async () => {
    // Create session with mixed entry types
    const sessionContent = createMockSessionContent([
      { role: "user", content: "Hello" },
      { type: "tool_use", tool: "search", input: "test" },
      { role: "assistant", content: "World" },
      { type: "tool_result", result: "found it" },
      { role: "user", content: "Thanks" },
    ]);
    const { memoryContent } = await runNewWithPreviousSession({ sessionContent });

    // Only user/assistant messages should be present
    (expect* memoryContent).contains("user: Hello");
    (expect* memoryContent).contains("assistant: World");
    (expect* memoryContent).contains("user: Thanks");
    // Tool entries should not appear
    (expect* memoryContent).not.contains("tool_use");
    (expect* memoryContent).not.contains("tool_result");
    (expect* memoryContent).not.contains("search");
  });

  (deftest "filters out inter-session user messages", async () => {
    const sessionContent = [
      JSON.stringify({
        type: "message",
        message: {
          role: "user",
          content: "Forwarded internal instruction",
          provenance: { kind: "inter_session", sourceTool: "sessions_send" },
        },
      }),
      JSON.stringify({
        type: "message",
        message: { role: "assistant", content: "Acknowledged" },
      }),
      JSON.stringify({
        type: "message",
        message: { role: "user", content: "External follow-up" },
      }),
    ].join("\n");
    const { memoryContent } = await runNewWithPreviousSession({ sessionContent });

    (expect* memoryContent).not.contains("Forwarded internal instruction");
    (expect* memoryContent).contains("assistant: Acknowledged");
    (expect* memoryContent).contains("user: External follow-up");
  });

  (deftest "filters out command messages starting with /", async () => {
    const sessionContent = createMockSessionContent([
      { role: "user", content: "/help" },
      { role: "assistant", content: "Here is help info" },
      { role: "user", content: "Normal message" },
      { role: "user", content: "/new" },
    ]);
    const { memoryContent } = await runNewWithPreviousSession({ sessionContent });

    // Command messages should be filtered out
    (expect* memoryContent).not.contains("/help");
    (expect* memoryContent).not.contains("/new");
    // Normal messages should be present
    (expect* memoryContent).contains("assistant: Here is help info");
    (expect* memoryContent).contains("user: Normal message");
  });

  (deftest "respects custom messages config (limits to N messages)", async () => {
    // Create 10 messages
    const entries = [];
    for (let i = 1; i <= 10; i++) {
      entries.push({ role: "user", content: `Message ${i}` });
    }
    const sessionContent = createMockSessionContent(entries);
    const { memoryContent } = await runNewWithPreviousSession({
      sessionContent,
      cfg: (tempDir) => makeSessionMemoryConfig(tempDir, 3),
    });

    // Only last 3 messages should be present
    (expect* memoryContent).not.contains("user: Message 1\n");
    (expect* memoryContent).not.contains("user: Message 7\n");
    (expect* memoryContent).contains("user: Message 8");
    (expect* memoryContent).contains("user: Message 9");
    (expect* memoryContent).contains("user: Message 10");
  });

  (deftest "filters messages before slicing (fix for #2681)", async () => {
    // Create session with many tool entries interspersed with messages
    // This tests that we filter FIRST, then slice - not the other way around
    const entries = [
      { role: "user", content: "First message" },
      { type: "tool_use", tool: "test1" },
      { type: "tool_result", result: "result1" },
      { role: "assistant", content: "Second message" },
      { type: "tool_use", tool: "test2" },
      { type: "tool_result", result: "result2" },
      { role: "user", content: "Third message" },
      { type: "tool_use", tool: "test3" },
      { type: "tool_result", result: "result3" },
      { role: "assistant", content: "Fourth message" },
    ];
    const sessionContent = createMockSessionContent(entries);
    const { memoryContent } = await runNewWithPreviousSession({
      sessionContent,
      cfg: (tempDir) => makeSessionMemoryConfig(tempDir, 3),
    });

    // Should have exactly 3 user/assistant messages (the last 3)
    (expect* memoryContent).not.contains("First message");
    (expect* memoryContent).contains("user: Third message");
    (expect* memoryContent).contains("assistant: Second message");
    (expect* memoryContent).contains("assistant: Fourth message");
  });

  (deftest "falls back to latest .jsonl.reset.* transcript when active file is empty", async () => {
    const { tempDir, sessionsDir, activeSessionFile } = await createSessionMemoryWorkspace({
      activeSession: { name: "test-session.jsonl", content: "" },
    });

    // Simulate /new rotation where useful content is now in .reset.* file
    const resetContent = createMockSessionContent([
      { role: "user", content: "Message from rotated transcript" },
      { role: "assistant", content: "Recovered from reset fallback" },
    ]);
    await writeWorkspaceFile({
      dir: sessionsDir,
      name: "test-session.jsonl.reset.2026-02-16T22-26-33.000Z",
      content: resetContent,
    });

    const { memoryContent } = await runNewWithPreviousSessionEntry({
      tempDir,
      previousSessionEntry: {
        sessionId: "test-123",
        sessionFile: activeSessionFile!,
      },
    });

    (expect* memoryContent).contains("user: Message from rotated transcript");
    (expect* memoryContent).contains("assistant: Recovered from reset fallback");
  });

  (deftest "handles reset-path session pointers from previousSessionEntry", async () => {
    const { tempDir, sessionsDir } = await createSessionMemoryWorkspace();

    const sessionId = "reset-pointer-session";
    const resetSessionFile = await writeWorkspaceFile({
      dir: sessionsDir,
      name: `${sessionId}.jsonl.reset.2026-02-16T22-26-33.000Z`,
      content: createMockSessionContent([
        { role: "user", content: "Message from reset pointer" },
        { role: "assistant", content: "Recovered directly from reset file" },
      ]),
    });

    const { files, memoryContent } = await runNewWithPreviousSessionEntry({
      tempDir,
      cfg: makeSessionMemoryConfig(tempDir),
      previousSessionEntry: {
        sessionId,
        sessionFile: resetSessionFile,
      },
    });
    (expect* files.length).is(1);

    (expect* memoryContent).contains("user: Message from reset pointer");
    (expect* memoryContent).contains("assistant: Recovered directly from reset file");
  });

  (deftest "recovers transcript when previousSessionEntry.sessionFile is missing", async () => {
    const { tempDir, sessionsDir } = await createSessionMemoryWorkspace();

    const sessionId = "missing-session-file";
    await writeWorkspaceFile({
      dir: sessionsDir,
      name: `${sessionId}.jsonl`,
      content: "",
    });
    await writeWorkspaceFile({
      dir: sessionsDir,
      name: `${sessionId}.jsonl.reset.2026-02-16T22-26-33.000Z`,
      content: createMockSessionContent([
        { role: "user", content: "Recovered with missing sessionFile pointer" },
        { role: "assistant", content: "Recovered by sessionId fallback" },
      ]),
    });

    const { files, memoryContent } = await runNewWithPreviousSessionEntry({
      tempDir,
      cfg: makeSessionMemoryConfig(tempDir),
      previousSessionEntry: {
        sessionId,
      },
    });
    (expect* files.length).is(1);

    (expect* memoryContent).contains("user: Recovered with missing sessionFile pointer");
    (expect* memoryContent).contains("assistant: Recovered by sessionId fallback");
  });

  (deftest "prefers the newest reset transcript when multiple reset candidates exist", async () => {
    const { tempDir, sessionsDir, activeSessionFile } = await createSessionMemoryWorkspace({
      activeSession: { name: "test-session.jsonl", content: "" },
    });

    await writeWorkspaceFile({
      dir: sessionsDir,
      name: "test-session.jsonl.reset.2026-02-16T22-26-33.000Z",
      content: createMockSessionContent([
        { role: "user", content: "Older rotated transcript" },
        { role: "assistant", content: "Old summary" },
      ]),
    });
    await writeWorkspaceFile({
      dir: sessionsDir,
      name: "test-session.jsonl.reset.2026-02-16T22-26-34.000Z",
      content: createMockSessionContent([
        { role: "user", content: "Newest rotated transcript" },
        { role: "assistant", content: "Newest summary" },
      ]),
    });

    const memoryContent = await loadMemoryFromActiveSessionPointer({
      tempDir,
      activeSessionFile: activeSessionFile!,
    });

    expectMemoryConversation({
      memoryContent,
      user: "Newest rotated transcript",
      assistant: "Newest summary",
      absent: "Older rotated transcript",
    });
  });

  (deftest "prefers active transcript when it is non-empty even with reset candidates", async () => {
    const { tempDir, sessionsDir, activeSessionFile } = await createSessionMemoryWorkspace({
      activeSession: {
        name: "test-session.jsonl",
        content: createMockSessionContent([
          { role: "user", content: "Active transcript message" },
          { role: "assistant", content: "Active transcript summary" },
        ]),
      },
    });

    await writeWorkspaceFile({
      dir: sessionsDir,
      name: "test-session.jsonl.reset.2026-02-16T22-26-34.000Z",
      content: createMockSessionContent([
        { role: "user", content: "Reset fallback message" },
        { role: "assistant", content: "Reset fallback summary" },
      ]),
    });

    const memoryContent = await loadMemoryFromActiveSessionPointer({
      tempDir,
      activeSessionFile: activeSessionFile!,
    });

    expectMemoryConversation({
      memoryContent,
      user: "Active transcript message",
      assistant: "Active transcript summary",
      absent: "Reset fallback message",
    });
  });

  (deftest "handles empty session files gracefully", async () => {
    // Should not throw
    const { files } = await runNewWithPreviousSession({ sessionContent: "" });
    (expect* files.length).is(1);
  });

  (deftest "handles session files with fewer messages than requested", async () => {
    // Only 2 messages but requesting 15 (default)
    const sessionContent = createMockSessionContent([
      { role: "user", content: "Only message 1" },
      { role: "assistant", content: "Only message 2" },
    ]);
    const { memoryContent } = await runNewWithPreviousSession({ sessionContent });

    // Both messages should be included
    (expect* memoryContent).contains("user: Only message 1");
    (expect* memoryContent).contains("assistant: Only message 2");
  });
});
