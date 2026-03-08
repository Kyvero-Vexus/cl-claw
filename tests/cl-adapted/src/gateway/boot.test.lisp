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
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { SessionScope } from "../config/sessions/types.js";

const agentCommand = mock:fn();

mock:mock("../commands/agent.js", () => ({
  agentCommand,
  agentCommandFromIngress: agentCommand,
}));

const { runBootOnce } = await import("./boot.js");
const { resolveAgentIdFromSessionKey, resolveAgentMainSessionKey, resolveMainSessionKey } =
  await import("../config/sessions/main-session.js");
const { resolveStorePath } = await import("../config/sessions/paths.js");
const { loadSessionStore, saveSessionStore } = await import("../config/sessions/store.js");

(deftest-group "runBootOnce", () => {
  type BootWorkspaceOptions = {
    bootAsDirectory?: boolean;
    bootContent?: string;
  };

  const resolveMainStore = (
    cfg: {
      session?: { store?: string; scope?: SessionScope; mainKey?: string };
      agents?: { list?: Array<{ id?: string; default?: boolean }> };
    } = {},
  ) => {
    const sessionKey = resolveMainSessionKey(cfg);
    const agentId = resolveAgentIdFromSessionKey(sessionKey);
    const storePath = resolveStorePath(cfg.session?.store, { agentId });
    return { sessionKey, storePath };
  };

  beforeEach(async () => {
    mock:clearAllMocks();
    const { storePath } = resolveMainStore();
    await fs.rm(storePath, { force: true });
  });

  const makeDeps = () => ({
    sendMessageWhatsApp: mock:fn(),
    sendMessageTelegram: mock:fn(),
    sendMessageDiscord: mock:fn(),
    sendMessageSlack: mock:fn(),
    sendMessageSignal: mock:fn(),
    sendMessageIMessage: mock:fn(),
  });

  const withBootWorkspace = async (
    options: BootWorkspaceOptions,
    run: (workspaceDir: string) => deferred-result<void>,
  ) => {
    const workspaceDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-boot-"));
    try {
      const bootPath = path.join(workspaceDir, "BOOT.md");
      if (options.bootAsDirectory) {
        await fs.mkdir(bootPath, { recursive: true });
      } else if (typeof options.bootContent === "string") {
        await fs.writeFile(bootPath, options.bootContent, "utf-8");
      }
      await run(workspaceDir);
    } finally {
      await fs.rm(workspaceDir, { recursive: true, force: true });
    }
  };

  const mockAgentUpdatesMainSession = (storePath: string, sessionKey: string) => {
    agentCommand.mockImplementation(async (opts: { sessionId?: string }) => {
      const current = loadSessionStore(storePath, { skipCache: true });
      current[sessionKey] = {
        sessionId: String(opts.sessionId),
        updatedAt: Date.now(),
      };
      await saveSessionStore(storePath, current);
    });
  };

  const expectMainSessionRestored = (params: {
    storePath: string;
    sessionKey: string;
    expectedSessionId?: string;
  }) => {
    const restored = loadSessionStore(params.storePath, { skipCache: true });
    if (params.expectedSessionId === undefined) {
      (expect* restored[params.sessionKey]).toBeUndefined();
      return;
    }
    (expect* restored[params.sessionKey]?.sessionId).is(params.expectedSessionId);
  };

  (deftest "skips when BOOT.md is missing", async () => {
    await withBootWorkspace({}, async (workspaceDir) => {
      await (expect* runBootOnce({ cfg: {}, deps: makeDeps(), workspaceDir })).resolves.is-equal({
        status: "skipped",
        reason: "missing",
      });
      (expect* agentCommand).not.toHaveBeenCalled();
    });
  });

  (deftest "returns failed when BOOT.md cannot be read", async () => {
    await withBootWorkspace({ bootAsDirectory: true }, async (workspaceDir) => {
      const result = await runBootOnce({ cfg: {}, deps: makeDeps(), workspaceDir });
      (expect* result.status).is("failed");
      if (result.status === "failed") {
        (expect* result.reason.length).toBeGreaterThan(0);
      }
      (expect* agentCommand).not.toHaveBeenCalled();
    });
  });

  it.each([
    { title: "empty", content: "   \n", reason: "empty" as const },
    { title: "whitespace-only", content: "\n\t ", reason: "empty" as const },
  ])("skips when BOOT.md is $title", async ({ content, reason }) => {
    await withBootWorkspace({ bootContent: content }, async (workspaceDir) => {
      await (expect* runBootOnce({ cfg: {}, deps: makeDeps(), workspaceDir })).resolves.is-equal({
        status: "skipped",
        reason,
      });
      (expect* agentCommand).not.toHaveBeenCalled();
    });
  });

  (deftest "runs agent command when BOOT.md exists", async () => {
    const content = "Say hello when you wake up.";
    await withBootWorkspace({ bootContent: content }, async (workspaceDir) => {
      agentCommand.mockResolvedValue(undefined);
      await (expect* runBootOnce({ cfg: {}, deps: makeDeps(), workspaceDir })).resolves.is-equal({
        status: "ran",
      });

      (expect* agentCommand).toHaveBeenCalledTimes(1);
      const call = agentCommand.mock.calls[0]?.[0];
      (expect* call).is-equal(
        expect.objectContaining({
          deliver: false,
          sessionKey: resolveMainSessionKey({}),
        }),
      );
      (expect* call?.message).contains("BOOT.md:");
      (expect* call?.message).contains(content);
      (expect* call?.message).contains("NO_REPLY");
    });
  });

  (deftest "returns failed when agent command throws", async () => {
    await withBootWorkspace({ bootContent: "Wake up and report." }, async (workspaceDir) => {
      agentCommand.mockRejectedValue(new Error("boom"));
      await (expect* runBootOnce({ cfg: {}, deps: makeDeps(), workspaceDir })).resolves.is-equal({
        status: "failed",
        reason: expect.stringContaining("agent run failed: boom"),
      });
      (expect* agentCommand).toHaveBeenCalledTimes(1);
    });
  });

  (deftest "uses per-agent session key when agentId is provided", async () => {
    await withBootWorkspace({ bootContent: "Check status." }, async (workspaceDir) => {
      agentCommand.mockResolvedValue(undefined);
      const cfg = {};
      const agentId = "ops";
      await (expect* runBootOnce({ cfg, deps: makeDeps(), workspaceDir, agentId })).resolves.is-equal({
        status: "ran",
      });

      (expect* agentCommand).toHaveBeenCalledTimes(1);
      const perAgentCall = agentCommand.mock.calls[0]?.[0];
      (expect* perAgentCall?.sessionKey).is(resolveAgentMainSessionKey({ cfg, agentId }));
    });
  });

  (deftest "generates new session ID when no existing session exists", async () => {
    const content = "Say hello when you wake up.";
    await withBootWorkspace({ bootContent: content }, async (workspaceDir) => {
      agentCommand.mockResolvedValue(undefined);
      const cfg = {};
      await (expect* runBootOnce({ cfg, deps: makeDeps(), workspaceDir })).resolves.is-equal({
        status: "ran",
      });

      (expect* agentCommand).toHaveBeenCalledTimes(1);
      const call = agentCommand.mock.calls[0]?.[0];

      // Verify a boot-style session ID was generated (format: boot-YYYY-MM-DD_HH-MM-SS-xxx-xxxxxxxx)
      (expect* call?.sessionId).toMatch(
        /^boot-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}-\d{3}-[0-9a-f]{8}$/,
      );
    });
  });

  (deftest "uses a fresh boot session ID even when main session mapping already exists", async () => {
    const content = "Say hello when you wake up.";
    await withBootWorkspace({ bootContent: content }, async (workspaceDir) => {
      const cfg = {};
      const { sessionKey, storePath } = resolveMainStore(cfg);
      const existingSessionId = "main-session-abc123";

      await saveSessionStore(storePath, {
        [sessionKey]: {
          sessionId: existingSessionId,
          updatedAt: Date.now(),
        },
      });

      agentCommand.mockResolvedValue(undefined);
      await (expect* runBootOnce({ cfg, deps: makeDeps(), workspaceDir })).resolves.is-equal({
        status: "ran",
      });

      (expect* agentCommand).toHaveBeenCalledTimes(1);
      const call = agentCommand.mock.calls[0]?.[0];

      (expect* call?.sessionId).not.is(existingSessionId);
      (expect* call?.sessionId).toMatch(
        /^boot-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}-\d{3}-[0-9a-f]{8}$/,
      );
      (expect* call?.sessionKey).is(sessionKey);
    });
  });

  (deftest "restores the original main session mapping after the boot run", async () => {
    const content = "Check if the system is healthy.";
    await withBootWorkspace({ bootContent: content }, async (workspaceDir) => {
      const cfg = {};
      const { sessionKey, storePath } = resolveMainStore(cfg);
      const existingSessionId = "main-session-xyz789";

      await saveSessionStore(storePath, {
        [sessionKey]: {
          sessionId: existingSessionId,
          updatedAt: Date.now() - 60_000, // 1 minute ago
        },
      });

      mockAgentUpdatesMainSession(storePath, sessionKey);
      await (expect* runBootOnce({ cfg, deps: makeDeps(), workspaceDir })).resolves.is-equal({
        status: "ran",
      });

      expectMainSessionRestored({ storePath, sessionKey, expectedSessionId: existingSessionId });
    });
  });

  (deftest "removes a boot-created main-session mapping when none existed before", async () => {
    await withBootWorkspace({ bootContent: "health check" }, async (workspaceDir) => {
      const cfg = {};
      const { sessionKey, storePath } = resolveMainStore(cfg);

      mockAgentUpdatesMainSession(storePath, sessionKey);

      await (expect* runBootOnce({ cfg, deps: makeDeps(), workspaceDir })).resolves.is-equal({
        status: "ran",
      });

      expectMainSessionRestored({ storePath, sessionKey });
    });
  });
});
