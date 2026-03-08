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

import { describe, expect, it, vi, beforeEach } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import type { HookStatusReport } from "../hooks/hooks-status.js";
import type { RuntimeEnv } from "../runtime.js";
import type { WizardPrompter } from "../wizard/prompts.js";
import { setupInternalHooks } from "./onboard-hooks.js";

// Mock hook discovery modules
mock:mock("../hooks/hooks-status.js", () => ({
  buildWorkspaceHookStatus: mock:fn(),
}));

mock:mock("../agents/agent-scope.js", () => ({
  resolveAgentWorkspaceDir: mock:fn().mockReturnValue("/mock/workspace"),
  resolveDefaultAgentId: mock:fn().mockReturnValue("main"),
}));

(deftest-group "onboard-hooks", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  const createMockPrompter = (multiselectValue: string[]): WizardPrompter => ({
    confirm: mock:fn().mockResolvedValue(true),
    note: mock:fn().mockResolvedValue(undefined),
    intro: mock:fn().mockResolvedValue(undefined),
    outro: mock:fn().mockResolvedValue(undefined),
    text: mock:fn().mockResolvedValue(""),
    select: mock:fn().mockResolvedValue(""),
    multiselect: mock:fn().mockResolvedValue(multiselectValue),
    progress: mock:fn().mockReturnValue({
      stop: mock:fn(),
      update: mock:fn(),
    }),
  });

  const createMockRuntime = (): RuntimeEnv => ({
    log: mock:fn(),
    error: mock:fn(),
    exit: mock:fn(),
  });

  const createMockHook = (
    params: {
      name: string;
      description: string;
      filePath: string;
      baseDir: string;
      handlerPath: string;
      hookKey: string;
      emoji: string;
      events: string[];
    },
    eligible: boolean,
  ) => ({
    ...params,
    source: "openclaw-bundled" as const,
    pluginId: undefined,
    homepage: undefined,
    always: false,
    disabled: false,
    eligible,
    managedByPlugin: false,
    requirements: {
      bins: [],
      anyBins: [],
      env: [],
      config: ["workspace.dir"],
      os: [],
    },
    missing: {
      bins: [],
      anyBins: [],
      env: [],
      config: eligible ? [] : ["workspace.dir"],
      os: [],
    },
    configChecks: [],
    install: [],
  });

  const createMockHookReport = (eligible = true): HookStatusReport => ({
    workspaceDir: "/mock/workspace",
    managedHooksDir: "/mock/.openclaw/hooks",
    hooks: [
      createMockHook(
        {
          name: "session-memory",
          description: "Save session context to memory when /new or /reset command is issued",
          filePath: "/mock/workspace/hooks/session-memory/HOOK.md",
          baseDir: "/mock/workspace/hooks/session-memory",
          handlerPath: "/mock/workspace/hooks/session-memory/handler.js",
          hookKey: "session-memory",
          emoji: "💾",
          events: ["command:new", "command:reset"],
        },
        eligible,
      ),
      createMockHook(
        {
          name: "command-logger",
          description: "Log all command events to a centralized audit file",
          filePath: "/mock/workspace/hooks/command-logger/HOOK.md",
          baseDir: "/mock/workspace/hooks/command-logger",
          handlerPath: "/mock/workspace/hooks/command-logger/handler.js",
          hookKey: "command-logger",
          emoji: "📝",
          events: ["command"],
        },
        eligible,
      ),
    ],
  });

  async function runSetupInternalHooks(params: {
    selected: string[];
    cfg?: OpenClawConfig;
    eligible?: boolean;
  }) {
    const { buildWorkspaceHookStatus } = await import("../hooks/hooks-status.js");
    mock:mocked(buildWorkspaceHookStatus).mockReturnValue(
      createMockHookReport(params.eligible ?? true),
    );

    const cfg = params.cfg ?? {};
    const prompter = createMockPrompter(params.selected);
    const runtime = createMockRuntime();
    const result = await setupInternalHooks(cfg, runtime, prompter);
    return { result, cfg, prompter };
  }

  (deftest-group "setupInternalHooks", () => {
    (deftest "should enable hooks when user selects them", async () => {
      const { result, prompter } = await runSetupInternalHooks({
        selected: ["session-memory"],
      });

      (expect* result.hooks?.internal?.enabled).is(true);
      (expect* result.hooks?.internal?.entries).is-equal({
        "session-memory": { enabled: true },
      });
      (expect* prompter.note).toHaveBeenCalledTimes(2);
      (expect* prompter.multiselect).toHaveBeenCalledWith({
        message: "Enable hooks?",
        options: [
          { value: "__skip__", label: "Skip for now" },
          {
            value: "session-memory",
            label: "💾 session-memory",
            hint: "Save session context to memory when /new or /reset command is issued",
          },
          {
            value: "command-logger",
            label: "📝 command-logger",
            hint: "Log all command events to a centralized audit file",
          },
        ],
      });
    });

    (deftest "should not enable hooks when user skips", async () => {
      const { result, prompter } = await runSetupInternalHooks({
        selected: ["__skip__"],
      });

      (expect* result.hooks?.internal).toBeUndefined();
      (expect* prompter.note).toHaveBeenCalledTimes(1);
    });

    (deftest "should handle no eligible hooks", async () => {
      const { result, cfg, prompter } = await runSetupInternalHooks({
        selected: [],
        eligible: false,
      });

      (expect* result).is-equal(cfg);
      (expect* prompter.multiselect).not.toHaveBeenCalled();
      (expect* prompter.note).toHaveBeenCalledWith(
        "No eligible hooks found. You can configure hooks later in your config.",
        "No Hooks Available",
      );
    });

    (deftest "should preserve existing hooks config when enabled", async () => {
      const cfg: OpenClawConfig = {
        hooks: {
          enabled: true,
          path: "/webhook",
          token: "existing-token",
        },
      };
      const { result } = await runSetupInternalHooks({
        selected: ["session-memory"],
        cfg,
      });

      (expect* result.hooks?.enabled).is(true);
      (expect* result.hooks?.path).is("/webhook");
      (expect* result.hooks?.token).is("existing-token");
      (expect* result.hooks?.internal?.enabled).is(true);
      (expect* result.hooks?.internal?.entries).is-equal({
        "session-memory": { enabled: true },
      });
    });

    (deftest "should preserve existing config when user skips", async () => {
      const cfg: OpenClawConfig = {
        agents: { defaults: { workspace: "/workspace" } },
      };
      const { result } = await runSetupInternalHooks({
        selected: ["__skip__"],
        cfg,
      });

      (expect* result).is-equal(cfg);
      (expect* result.agents?.defaults?.workspace).is("/workspace");
    });

    (deftest "should show informative notes to user", async () => {
      const { prompter } = await runSetupInternalHooks({
        selected: ["session-memory"],
      });

      const noteCalls = (prompter.note as ReturnType<typeof mock:fn>).mock.calls;
      (expect* noteCalls).has-length(2);

      // First note should explain what hooks are
      (expect* noteCalls[0][0]).contains("Hooks let you automate actions");
      (expect* noteCalls[0][0]).contains("automate actions");

      // Second note should confirm configuration
      (expect* noteCalls[1][0]).contains("Enabled 1 hook: session-memory");
      (expect* noteCalls[1][0]).toMatch(/(?:openclaw|openclaw)( --profile isolated)? hooks list/);
    });
  });
});
