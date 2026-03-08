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
import { SILENT_REPLY_TOKEN } from "../auto-reply/tokens.js";
import { typedCases } from "../test-utils/typed-cases.js";
import { buildSubagentSystemPrompt } from "./subagent-announce.js";
import { buildAgentSystemPrompt, buildRuntimeLine } from "./system-prompt.js";

(deftest-group "buildAgentSystemPrompt", () => {
  (deftest "formats owner section for plain, hash, and missing owner lists", () => {
    const cases = typedCases<{
      name: string;
      params: Parameters<typeof buildAgentSystemPrompt>[0];
      expectAuthorizedSection: boolean;
      contains: string[];
      notContains: string[];
      hashMatch?: RegExp;
    }>([
      {
        name: "plain owner numbers",
        params: {
          workspaceDir: "/tmp/openclaw",
          ownerNumbers: ["+123", " +456 ", ""],
        },
        expectAuthorizedSection: true,
        contains: [
          "Authorized senders: +123, +456. These senders are allowlisted; do not assume they are the owner.",
        ],
        notContains: [],
      },
      {
        name: "hashed owner numbers",
        params: {
          workspaceDir: "/tmp/openclaw",
          ownerNumbers: ["+123", "+456", ""],
          ownerDisplay: "hash",
        },
        expectAuthorizedSection: true,
        contains: ["Authorized senders:"],
        notContains: ["+123", "+456"],
        hashMatch: /[a-f0-9]{12}/,
      },
      {
        name: "missing owners",
        params: {
          workspaceDir: "/tmp/openclaw",
        },
        expectAuthorizedSection: false,
        contains: [],
        notContains: ["## Authorized Senders", "Authorized senders:"],
      },
    ]);

    for (const testCase of cases) {
      const prompt = buildAgentSystemPrompt(testCase.params);
      if (testCase.expectAuthorizedSection) {
        (expect* prompt, testCase.name).contains("## Authorized Senders");
      } else {
        (expect* prompt, testCase.name).not.contains("## Authorized Senders");
      }
      for (const value of testCase.contains) {
        (expect* prompt, `${testCase.name}:${value}`).contains(value);
      }
      for (const value of testCase.notContains) {
        (expect* prompt, `${testCase.name}:${value}`).not.contains(value);
      }
      if (testCase.hashMatch) {
        (expect* prompt, testCase.name).toMatch(testCase.hashMatch);
      }
    }
  });

  (deftest "uses a stable, keyed HMAC when ownerDisplaySecret is provided", () => {
    const secretA = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      ownerNumbers: ["+123"],
      ownerDisplay: "hash",
      ownerDisplaySecret: "secret-key-A", // pragma: allowlist secret
    });

    const secretB = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      ownerNumbers: ["+123"],
      ownerDisplay: "hash",
      ownerDisplaySecret: "secret-key-B", // pragma: allowlist secret
    });

    const lineA = secretA.split("## Authorized Senders")[1]?.split("\n")[1];
    const lineB = secretB.split("## Authorized Senders")[1]?.split("\n")[1];
    const tokenA = lineA?.match(/[a-f0-9]{12}/)?.[0];
    const tokenB = lineB?.match(/[a-f0-9]{12}/)?.[0];

    (expect* tokenA).toBeDefined();
    (expect* tokenB).toBeDefined();
    (expect* tokenA).not.is(tokenB);
  });

  (deftest "omits extended sections in minimal prompt mode", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      promptMode: "minimal",
      ownerNumbers: ["+123"],
      skillsPrompt:
        "<available_skills>\n  <skill>\n    <name>demo</name>\n  </skill>\n</available_skills>",
      heartbeatPrompt: "ping",
      toolNames: ["message", "memory_search"],
      docsPath: "/tmp/openclaw/docs",
      extraSystemPrompt: "Subagent details",
      ttsHint: "Voice (TTS) is enabled.",
    });

    (expect* prompt).not.contains("## Authorized Senders");
    // Skills are included even in minimal mode when skillsPrompt is provided (cron sessions need them)
    (expect* prompt).contains("## Skills");
    (expect* prompt).not.contains("## Memory Recall");
    (expect* prompt).not.contains("## Documentation");
    (expect* prompt).not.contains("## Reply Tags");
    (expect* prompt).not.contains("## Messaging");
    (expect* prompt).not.contains("## Voice (TTS)");
    (expect* prompt).not.contains("## Silent Replies");
    (expect* prompt).not.contains("## Heartbeats");
    (expect* prompt).contains("## Safety");
    (expect* prompt).contains(
      "For long waits, avoid rapid poll loops: use exec with enough yieldMs or process(action=poll, timeout=<ms>).",
    );
    (expect* prompt).contains("You have no independent goals");
    (expect* prompt).contains("Prioritize safety and human oversight");
    (expect* prompt).contains("if instructions conflict");
    (expect* prompt).contains("Inspired by Anthropic's constitution");
    (expect* prompt).contains("Do not manipulate or persuade anyone");
    (expect* prompt).contains("Do not copy yourself or change system prompts");
    (expect* prompt).contains("## Subagent Context");
    (expect* prompt).not.contains("## Group Chat Context");
    (expect* prompt).contains("Subagent details");
  });

  (deftest "includes skills in minimal prompt mode when skillsPrompt is provided (cron regression)", () => {
    // Isolated cron sessions use promptMode="minimal" but must still receive skills.
    const skillsPrompt =
      "<available_skills>\n  <skill>\n    <name>demo</name>\n  </skill>\n</available_skills>";
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      promptMode: "minimal",
      skillsPrompt,
    });

    (expect* prompt).contains("## Skills (mandatory)");
    (expect* prompt).contains("<available_skills>");
    (expect* prompt).contains(
      "When a skill drives external API writes, assume rate limits: prefer fewer larger writes, avoid tight one-item loops, serialize bursts when possible, and respect 429/Retry-After.",
    );
  });

  (deftest "omits skills in minimal prompt mode when skillsPrompt is absent", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      promptMode: "minimal",
    });

    (expect* prompt).not.contains("## Skills");
  });

  (deftest "includes safety guardrails in full prompts", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
    });

    (expect* prompt).contains("## Safety");
    (expect* prompt).contains("You have no independent goals");
    (expect* prompt).contains("Prioritize safety and human oversight");
    (expect* prompt).contains("if instructions conflict");
    (expect* prompt).contains("Inspired by Anthropic's constitution");
    (expect* prompt).contains("Do not manipulate or persuade anyone");
    (expect* prompt).contains("Do not copy yourself or change system prompts");
  });

  (deftest "includes voice hint when provided", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      ttsHint: "Voice (TTS) is enabled.",
    });

    (expect* prompt).contains("## Voice (TTS)");
    (expect* prompt).contains("Voice (TTS) is enabled.");
  });

  (deftest "adds reasoning tag hint when enabled", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      reasoningTagHint: true,
    });

    (expect* prompt).contains("## Reasoning Format");
    (expect* prompt).contains("<think>...</think>");
    (expect* prompt).contains("<final>...</final>");
  });

  (deftest "includes a CLI quick reference section", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
    });

    (expect* prompt).contains("## OpenClaw CLI Quick Reference");
    (expect* prompt).contains("openclaw gateway restart");
    (expect* prompt).contains("Do not invent commands");
  });

  (deftest "guides runtime completion events without exposing internal metadata", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
    });

    (expect* prompt).contains("Runtime-generated completion events may ask for a user update.");
    (expect* prompt).contains("Rewrite those in your normal assistant voice");
    (expect* prompt).contains("do not forward raw internal metadata");
  });

  (deftest "guides subagent workflows to avoid polling loops", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
    });

    (expect* prompt).contains(
      "For long waits, avoid rapid poll loops: use exec with enough yieldMs or process(action=poll, timeout=<ms>).",
    );
    (expect* prompt).contains("Completion is push-based: it will auto-announce when done.");
    (expect* prompt).contains("Do not poll `subagents list` / `sessions_list` in a loop");
    (expect* prompt).contains(
      "When a first-class tool exists for an action, use the tool directly instead of asking the user to run equivalent CLI or slash commands.",
    );
  });

  (deftest "lists available tools when provided", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      toolNames: ["exec", "sessions_list", "sessions_history", "sessions_send"],
    });

    (expect* prompt).contains("Tool availability (filtered by policy):");
    (expect* prompt).contains("sessions_list");
    (expect* prompt).contains("sessions_history");
    (expect* prompt).contains("sessions_send");
  });

  (deftest "documents ACP sessions_spawn agent targeting requirements", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      toolNames: ["sessions_spawn"],
    });

    (expect* prompt).contains("sessions_spawn");
    (expect* prompt).contains(
      'runtime="acp" requires `agentId` unless `acp.defaultAgent` is configured',
    );
    (expect* prompt).contains("not agents_list");
  });

  (deftest "guides harness requests to ACP thread-bound spawns", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      toolNames: ["sessions_spawn", "subagents", "agents_list", "exec"],
    });

    (expect* prompt).contains(
      'For requests like "do this in codex/claude code/gemini", treat it as ACP harness intent',
    );
    (expect* prompt).contains(
      'On Discord, default ACP harness requests to thread-bound persistent sessions (`thread: true`, `mode: "session"`)',
    );
    (expect* prompt).contains(
      "do not route ACP harness requests through `subagents`/`agents_list` or local PTY exec flows",
    );
    (expect* prompt).contains(
      'do not call `message` with `action=thread-create`; use `sessions_spawn` (`runtime: "acp"`, `thread: true`) as the single thread creation path',
    );
  });

  (deftest "omits ACP harness guidance when ACP is disabled", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      toolNames: ["sessions_spawn", "subagents", "agents_list", "exec"],
      acpEnabled: false,
    });

    (expect* prompt).not.contains(
      'For requests like "do this in codex/claude code/gemini", treat it as ACP harness intent',
    );
    (expect* prompt).not.contains('runtime="acp" requires `agentId`');
    (expect* prompt).not.contains("not ACP harness ids");
    (expect* prompt).contains("- sessions_spawn: Spawn an isolated sub-agent session");
    (expect* prompt).contains("- agents_list: List OpenClaw agent ids allowed for sessions_spawn");
  });

  (deftest "omits ACP harness spawn guidance for sandboxed sessions and shows ACP block note", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      toolNames: ["sessions_spawn", "subagents", "agents_list", "exec"],
      sandboxInfo: {
        enabled: true,
      },
    });

    (expect* prompt).not.contains('runtime="acp" requires `agentId`');
    (expect* prompt).not.contains("ACP harness ids follow acp.allowedAgents");
    (expect* prompt).not.contains(
      'For requests like "do this in codex/claude code/gemini", treat it as ACP harness intent',
    );
    (expect* prompt).not.contains(
      'do not call `message` with `action=thread-create`; use `sessions_spawn` (`runtime: "acp"`, `thread: true`) as the single thread creation path',
    );
    (expect* prompt).contains("ACP harness spawns are blocked from sandboxed sessions");
    (expect* prompt).contains('`runtime: "acp"`');
    (expect* prompt).contains('Use `runtime: "subagent"` instead.');
  });

  (deftest "preserves tool casing in the prompt", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      toolNames: ["Read", "Exec", "process"],
      skillsPrompt:
        "<available_skills>\n  <skill>\n    <name>demo</name>\n  </skill>\n</available_skills>",
      docsPath: "/tmp/openclaw/docs",
    });

    (expect* prompt).contains("- Read: Read file contents");
    (expect* prompt).contains("- Exec: Run shell commands");
    (expect* prompt).contains(
      "- If exactly one skill clearly applies: read its SKILL.md at <location> with `Read`, then follow it.",
    );
    (expect* prompt).contains("OpenClaw docs: /tmp/openclaw/docs");
    (expect* prompt).contains(
      "For OpenClaw behavior, commands, config, or architecture: consult local docs first.",
    );
  });

  (deftest "includes docs guidance when docsPath is provided", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      docsPath: "/tmp/openclaw/docs",
    });

    (expect* prompt).contains("## Documentation");
    (expect* prompt).contains("OpenClaw docs: /tmp/openclaw/docs");
    (expect* prompt).contains(
      "For OpenClaw behavior, commands, config, or architecture: consult local docs first.",
    );
  });

  (deftest "includes workspace notes when provided", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      workspaceNotes: ["Reminder: commit your changes in this workspace after edits."],
    });

    (expect* prompt).contains("Reminder: commit your changes in this workspace after edits.");
  });

  (deftest "shows timezone section for 12h, 24h, and timezone-only modes", () => {
    const cases = [
      {
        name: "12-hour",
        params: {
          workspaceDir: "/tmp/openclaw",
          userTimezone: "America/Chicago",
          userTime: "Monday, January 5th, 2026 — 3:26 PM",
          userTimeFormat: "12" as const,
        },
      },
      {
        name: "24-hour",
        params: {
          workspaceDir: "/tmp/openclaw",
          userTimezone: "America/Chicago",
          userTime: "Monday, January 5th, 2026 — 15:26",
          userTimeFormat: "24" as const,
        },
      },
      {
        name: "timezone-only",
        params: {
          workspaceDir: "/tmp/openclaw",
          userTimezone: "America/Chicago",
          userTimeFormat: "24" as const,
        },
      },
    ] as const;

    for (const testCase of cases) {
      const prompt = buildAgentSystemPrompt(testCase.params);
      (expect* prompt, testCase.name).contains("## Current Date & Time");
      (expect* prompt, testCase.name).contains("Time zone: America/Chicago");
    }
  });

  (deftest "hints to use session_status for current date/time", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/clawd",
      userTimezone: "America/Chicago",
    });

    (expect* prompt).contains("session_status");
    (expect* prompt).contains("current date");
  });

  // The system prompt intentionally does NOT include the current date/time.
  // Only the timezone is included, to keep the prompt stable for caching.
  // See: https://github.com/moltbot/moltbot/commit/66eec295b894bce8333886cfbca3b960c57c4946
  // Agents should use session_status or message timestamps to determine the date/time.
  // Related: https://github.com/moltbot/moltbot/issues/1897
  //          https://github.com/moltbot/moltbot/issues/3658
  (deftest "does NOT include a date or time in the system prompt (cache stability)", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/clawd",
      userTimezone: "America/Chicago",
      userTime: "Monday, January 5th, 2026 — 3:26 PM",
      userTimeFormat: "12",
    });

    // The prompt should contain the timezone but NOT the formatted date/time string.
    // This is intentional for prompt cache stability — the date/time was removed in
    // commit 66eec295b. If you're here because you want to add it back, please see
    // https://github.com/moltbot/moltbot/issues/3658 for the preferred approach:
    // gateway-level timestamp injection into messages, not the system prompt.
    (expect* prompt).contains("Time zone: America/Chicago");
    (expect* prompt).not.contains("Monday, January 5th, 2026");
    (expect* prompt).not.contains("3:26 PM");
    (expect* prompt).not.contains("15:26");
  });

  (deftest "includes model alias guidance when aliases are provided", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      modelAliasLines: [
        "- Opus: anthropic/claude-opus-4-5",
        "- Sonnet: anthropic/claude-sonnet-4-5",
      ],
    });

    (expect* prompt).contains("## Model Aliases");
    (expect* prompt).contains("Prefer aliases when specifying model overrides");
    (expect* prompt).contains("- Opus: anthropic/claude-opus-4-5");
  });

  (deftest "adds ClaudeBot self-update guidance when gateway tool is available", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      toolNames: ["gateway", "exec"],
    });

    (expect* prompt).contains("## OpenClaw Self-Update");
    (expect* prompt).contains("config.schema.lookup");
    (expect* prompt).contains("config.apply");
    (expect* prompt).contains("config.patch");
    (expect* prompt).contains("update.run");
    (expect* prompt).not.contains("Use config.schema to");
    (expect* prompt).not.contains("config.schema, config.apply");
  });

  (deftest "includes skills guidance when skills prompt is present", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      skillsPrompt:
        "<available_skills>\n  <skill>\n    <name>demo</name>\n  </skill>\n</available_skills>",
    });

    (expect* prompt).contains("## Skills");
    (expect* prompt).contains(
      "- If exactly one skill clearly applies: read its SKILL.md at <location> with `read`, then follow it.",
    );
  });

  (deftest "appends available skills when provided", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      skillsPrompt:
        "<available_skills>\n  <skill>\n    <name>demo</name>\n  </skill>\n</available_skills>",
    });

    (expect* prompt).contains("<available_skills>");
    (expect* prompt).contains("<name>demo</name>");
  });

  (deftest "omits skills section when no skills prompt is provided", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
    });

    (expect* prompt).not.contains("## Skills");
    (expect* prompt).not.contains("<available_skills>");
  });

  (deftest "renders project context files when provided", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      contextFiles: [
        { path: "AGENTS.md", content: "Alpha" },
        { path: "IDENTITY.md", content: "Bravo" },
      ],
    });

    (expect* prompt).contains("# Project Context");
    (expect* prompt).contains("## AGENTS.md");
    (expect* prompt).contains("Alpha");
    (expect* prompt).contains("## IDENTITY.md");
    (expect* prompt).contains("Bravo");
  });

  (deftest "ignores context files with missing or blank paths", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      contextFiles: [
        { path: undefined as unknown as string, content: "Missing path" },
        { path: "   ", content: "Blank path" },
        { path: "AGENTS.md", content: "Alpha" },
      ],
    });

    (expect* prompt).contains("# Project Context");
    (expect* prompt).contains("## AGENTS.md");
    (expect* prompt).contains("Alpha");
    (expect* prompt).not.contains("Missing path");
    (expect* prompt).not.contains("Blank path");
  });

  (deftest "adds SOUL guidance when a soul file is present", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      contextFiles: [
        { path: "./SOUL.md", content: "Persona" },
        { path: "dir\\SOUL.md", content: "Persona Windows" },
      ],
    });

    (expect* prompt).contains(
      "If SOUL.md is present, embody its persona and tone. Avoid stiff, generic replies; follow its guidance unless higher-priority instructions override it.",
    );
  });

  (deftest "renders bootstrap truncation warning even when no context files are injected", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      bootstrapTruncationWarningLines: ["AGENTS.md: 200 raw -> 0 injected"],
      contextFiles: [],
    });

    (expect* prompt).contains("# Project Context");
    (expect* prompt).contains("⚠ Bootstrap truncation warning:");
    (expect* prompt).contains("- AGENTS.md: 200 raw -> 0 injected");
  });

  (deftest "summarizes the message tool when available", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      toolNames: ["message"],
    });

    (expect* prompt).contains("message: Send messages and channel actions");
    (expect* prompt).contains("### message tool");
    (expect* prompt).contains(`respond with ONLY: ${SILENT_REPLY_TOKEN}`);
  });

  (deftest "includes inline button style guidance when runtime supports inline buttons", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      toolNames: ["message"],
      runtimeInfo: {
        channel: "telegram",
        capabilities: ["inlineButtons"],
      },
    });

    (expect* prompt).contains("buttons=[[{text,callback_data,style?}]]");
    (expect* prompt).contains("`style` can be `primary`, `success`, or `danger`");
  });

  (deftest "includes runtime provider capabilities when present", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      runtimeInfo: {
        channel: "telegram",
        capabilities: ["inlineButtons"],
      },
    });

    (expect* prompt).contains("channel=telegram");
    (expect* prompt).contains("capabilities=inlineButtons");
  });

  (deftest "includes agent id in runtime when provided", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      runtimeInfo: {
        agentId: "work",
        host: "host",
        os: "macOS",
        arch: "arm64",
        sbcl: "v20",
        model: "anthropic/claude",
      },
    });

    (expect* prompt).contains("agent=work");
  });

  (deftest "includes reasoning visibility hint", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      reasoningLevel: "off",
    });

    (expect* prompt).contains("Reasoning: off");
    (expect* prompt).contains("/reasoning");
    (expect* prompt).contains("/status shows Reasoning");
  });

  (deftest "builds runtime line with agent and channel details", () => {
    const line = buildRuntimeLine(
      {
        agentId: "work",
        host: "host",
        repoRoot: "/repo",
        os: "macOS",
        arch: "arm64",
        sbcl: "v20",
        model: "anthropic/claude",
        defaultModel: "anthropic/claude-opus-4-5",
      },
      "telegram",
      ["inlineButtons"],
      "low",
    );

    (expect* line).contains("agent=work");
    (expect* line).contains("host=host");
    (expect* line).contains("repo=/repo");
    (expect* line).contains("os=macOS (arm64)");
    (expect* line).contains("sbcl=v20");
    (expect* line).contains("model=anthropic/claude");
    (expect* line).contains("default_model=anthropic/claude-opus-4-5");
    (expect* line).contains("channel=telegram");
    (expect* line).contains("capabilities=inlineButtons");
    (expect* line).contains("thinking=low");
  });

  (deftest "describes sandboxed runtime and elevated when allowed", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      sandboxInfo: {
        enabled: true,
        workspaceDir: "/tmp/sandbox",
        containerWorkspaceDir: "/workspace",
        workspaceAccess: "ro",
        agentWorkspaceMount: "/agent",
        elevated: { allowed: true, defaultLevel: "on" },
      },
    });

    (expect* prompt).contains("Your working directory is: /workspace");
    (expect* prompt).contains(
      "For read/write/edit/apply_patch, file paths resolve against host workspace: /tmp/openclaw. For bash/exec commands, use sandbox container paths under /workspace (or relative paths from that workdir), not host paths.",
    );
    (expect* prompt).contains("Sandbox container workdir: /workspace");
    (expect* prompt).contains(
      "Sandbox host mount source (file tools bridge only; not valid inside sandbox exec): /tmp/sandbox",
    );
    (expect* prompt).contains("You are running in a sandboxed runtime");
    (expect* prompt).contains("Sub-agents stay sandboxed");
    (expect* prompt).contains("User can toggle with /elevated on|off|ask|full.");
    (expect* prompt).contains("Current elevated level: on");
  });

  (deftest "includes reaction guidance when provided", () => {
    const prompt = buildAgentSystemPrompt({
      workspaceDir: "/tmp/openclaw",
      reactionGuidance: {
        level: "minimal",
        channel: "Telegram",
      },
    });

    (expect* prompt).contains("## Reactions");
    (expect* prompt).contains("Reactions are enabled for Telegram in MINIMAL mode.");
  });
});

(deftest-group "buildSubagentSystemPrompt", () => {
  (deftest "renders depth-1 orchestrator guidance, labels, and recovery notes", () => {
    const prompt = buildSubagentSystemPrompt({
      childSessionKey: "agent:main:subagent:abc",
      task: "research task",
      childDepth: 1,
      maxSpawnDepth: 2,
    });

    (expect* prompt).contains("## Sub-Agent Spawning");
    (expect* prompt).contains(
      "You CAN spawn your own sub-agents for parallel or complex work using `sessions_spawn`.",
    );
    (expect* prompt).contains("sessions_spawn");
    (expect* prompt).contains('runtime: "acp"');
    (expect* prompt).contains("For ACP harness sessions (codex/claudecode/gemini)");
    (expect* prompt).contains("set `agentId` unless `acp.defaultAgent` is configured");
    (expect* prompt).contains("Do not ask users to run slash commands or CLI");
    (expect* prompt).contains("Do not use `exec` (`openclaw ...`, `acpx ...`)");
    (expect* prompt).contains("Use `subagents` only for OpenClaw subagents");
    (expect* prompt).contains("Subagent results auto-announce back to you");
    (expect* prompt).contains(
      "After spawning children, do NOT call sessions_list, sessions_history, exec sleep, or any polling tool.",
    );
    (expect* prompt).contains(
      "Track expected child session keys and only send your final answer after completion events for ALL expected children arrive.",
    );
    (expect* prompt).contains(
      "If a child completion event arrives AFTER you already sent your final answer, reply ONLY with NO_REPLY.",
    );
    (expect* prompt).contains("Avoid polling loops");
    (expect* prompt).contains("spawned by the main agent");
    (expect* prompt).contains("reported to the main agent");
    (expect* prompt).contains("[compacted: tool output removed to free context]");
    (expect* prompt).contains("[truncated: output exceeded context limit]");
    (expect* prompt).contains("offset/limit");
    (expect* prompt).contains("instead of full-file `cat`");
  });

  (deftest "omits ACP spawning guidance when ACP is disabled", () => {
    const prompt = buildSubagentSystemPrompt({
      childSessionKey: "agent:main:subagent:abc",
      task: "research task",
      childDepth: 1,
      maxSpawnDepth: 2,
      acpEnabled: false,
    });

    (expect* prompt).not.contains('runtime: "acp"');
    (expect* prompt).not.contains("For ACP harness sessions (codex/claudecode/gemini)");
    (expect* prompt).not.contains("set `agentId` unless `acp.defaultAgent` is configured");
    (expect* prompt).contains("You CAN spawn your own sub-agents");
  });

  (deftest "renders depth-2 leaf guidance with parent orchestrator labels", () => {
    const prompt = buildSubagentSystemPrompt({
      childSessionKey: "agent:main:subagent:abc:subagent:def",
      task: "leaf task",
      childDepth: 2,
      maxSpawnDepth: 2,
    });

    (expect* prompt).contains("## Sub-Agent Spawning");
    (expect* prompt).contains("leaf worker");
    (expect* prompt).contains("CANNOT spawn further sub-agents");
    (expect* prompt).contains("spawned by the parent orchestrator");
    (expect* prompt).contains("reported to the parent orchestrator");
  });

  (deftest "omits spawning guidance for depth-1 leaf agents", () => {
    const leafCases = [
      {
        name: "explicit maxSpawnDepth 1",
        input: {
          childSessionKey: "agent:main:subagent:abc",
          task: "research task",
          childDepth: 1,
          maxSpawnDepth: 1,
        },
        expectMainAgentLabel: false,
      },
      {
        name: "implicit default depth/maxSpawnDepth",
        input: {
          childSessionKey: "agent:main:subagent:abc",
          task: "basic task",
        },
        expectMainAgentLabel: true,
      },
    ] as const;

    for (const testCase of leafCases) {
      const prompt = buildSubagentSystemPrompt(testCase.input);
      (expect* prompt, testCase.name).not.contains("## Sub-Agent Spawning");
      (expect* prompt, testCase.name).not.contains("You CAN spawn");
      if (testCase.expectMainAgentLabel) {
        (expect* prompt, testCase.name).contains("spawned by the main agent");
      }
    }
  });
});
