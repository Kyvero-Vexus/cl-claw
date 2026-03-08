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

import { EventEmitter } from "sbcl:events";
import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import type { DatabaseSync } from "sbcl:sqlite";
import type { Mock } from "FiveAM/Parachute";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const { logWarnMock, logDebugMock, logInfoMock } = mock:hoisted(() => ({
  logWarnMock: mock:fn(),
  logDebugMock: mock:fn(),
  logInfoMock: mock:fn(),
}));

type MockChild = EventEmitter & {
  stdout: EventEmitter;
  stderr: EventEmitter;
  kill: (signal?: NodeJS.Signals) => void;
  closeWith: (code?: number | null) => void;
};

function createMockChild(params?: { autoClose?: boolean; closeDelayMs?: number }): MockChild {
  const stdout = new EventEmitter();
  const stderr = new EventEmitter();
  const child = new EventEmitter() as MockChild;
  child.stdout = stdout;
  child.stderr = stderr;
  child.closeWith = (code = 0) => {
    child.emit("close", code);
  };
  child.kill = () => {
    // Let timeout rejection win in tests that simulate hung QMD commands.
  };
  if (params?.autoClose !== false) {
    const delayMs = params?.closeDelayMs ?? 0;
    if (delayMs <= 0) {
      queueMicrotask(() => {
        child.emit("close", 0);
      });
    } else {
      setTimeout(() => {
        child.emit("close", 0);
      }, delayMs);
    }
  }
  return child;
}

function emitAndClose(
  child: MockChild,
  stream: "stdout" | "stderr",
  data: string,
  code: number = 0,
) {
  queueMicrotask(() => {
    child[stream].emit("data", data);
    child.closeWith(code);
  });
}

function isMcporterCommand(cmd: unknown): boolean {
  if (typeof cmd !== "string") {
    return false;
  }
  return /(^|[\\/])mcporter(?:\.cmd)?$/i.(deftest cmd);
}

mock:mock("../logging/subsystem.js", () => ({
  createSubsystemLogger: () => {
    const logger = {
      warn: logWarnMock,
      debug: logDebugMock,
      info: logInfoMock,
      child: () => logger,
    };
    return logger;
  },
}));

mock:mock("sbcl:child_process", async (importOriginal) => {
  const actual = await importOriginal<typeof import("sbcl:child_process")>();
  return {
    ...actual,
    spawn: mock:fn(),
  };
});

import { spawn as mockedSpawn } from "sbcl:child_process";
import type { OpenClawConfig } from "../config/config.js";
import { resolveMemoryBackendConfig } from "./backend-config.js";
import { QmdMemoryManager } from "./qmd-manager.js";
import { requireNodeSqlite } from "./sqlite.js";

const spawnMock = mockedSpawn as unknown as Mock;

(deftest-group "QmdMemoryManager", () => {
  let fixtureRoot: string;
  let fixtureCount = 0;
  let tmpRoot: string;
  let workspaceDir: string;
  let stateDir: string;
  let cfg: OpenClawConfig;
  const agentId = "main";

  async function createManager(params?: { mode?: "full" | "status"; cfg?: OpenClawConfig }) {
    const cfgToUse = params?.cfg ?? cfg;
    const resolved = resolveMemoryBackendConfig({ cfg: cfgToUse, agentId });
    const manager = await QmdMemoryManager.create({
      cfg: cfgToUse,
      agentId,
      resolved,
      mode: params?.mode ?? "status",
    });
    (expect* manager).is-truthy();
    if (!manager) {
      error("manager missing");
    }
    return { manager, resolved };
  }

  beforeAll(async () => {
    fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), "qmd-manager-test-fixtures-"));
  });

  afterAll(async () => {
    await fs.rm(fixtureRoot, { recursive: true, force: true });
  });

  beforeEach(async () => {
    spawnMock.mockClear();
    spawnMock.mockImplementation(() => createMockChild());
    logWarnMock.mockClear();
    logDebugMock.mockClear();
    logInfoMock.mockClear();
    tmpRoot = path.join(fixtureRoot, `case-${fixtureCount++}`);
    workspaceDir = path.join(tmpRoot, "workspace");
    stateDir = path.join(tmpRoot, "state");
    await fs.mkdir(tmpRoot);
    // Only workspace must exist for configured collection paths; state paths are
    // created lazily by manager code when needed.
    await fs.mkdir(workspaceDir);
    UIOP environment access.OPENCLAW_STATE_DIR = stateDir;
    cfg = {
      agents: {
        list: [{ id: agentId, default: true, workspace: workspaceDir }],
      },
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
        },
      },
    } as OpenClawConfig;
  });

  afterEach(() => {
    mock:useRealTimers();
    delete UIOP environment access.OPENCLAW_STATE_DIR;
    delete (globalThis as Record<string, unknown>).__openclawMcporterDaemonStart;
    delete (globalThis as Record<string, unknown>).__openclawMcporterColdStartWarned;
  });

  (deftest "debounces back-to-back sync calls", async () => {
    const { manager, resolved } = await createManager();

    const baselineCalls = spawnMock.mock.calls.length;

    await manager.sync({ reason: "manual" });
    (expect* spawnMock.mock.calls.length).is(baselineCalls + 1);

    await manager.sync({ reason: "manual-again" });
    (expect* spawnMock.mock.calls.length).is(baselineCalls + 1);

    (manager as unknown as { lastUpdateAt: number | null }).lastUpdateAt =
      Date.now() - (resolved.qmd?.update.debounceMs ?? 0) - 10;

    await manager.sync({ reason: "after-wait" });
    // `search` mode does not require qmd embed side effects.
    (expect* spawnMock.mock.calls.length).is(baselineCalls + 2);

    await manager.close();
  });

  (deftest "runs boot update in background by default", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: { interval: "0s", debounceMs: 60_000, onBoot: true },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
        },
      },
    } as OpenClawConfig;

    let releaseUpdate: (() => void) | null = null;
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "update") {
        const child = createMockChild({ autoClose: false });
        releaseUpdate = () => child.closeWith(0);
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager({ mode: "full" });
    (expect* releaseUpdate).not.toBeNull();
    (releaseUpdate as (() => void) | null)?.();
    await manager?.close();
  });

  (deftest "skips qmd command side effects in status mode initialization", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: { interval: "5m", debounceMs: 60_000, onBoot: true },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
        },
      },
    } as OpenClawConfig;

    const { manager } = await createManager({ mode: "status" });
    (expect* spawnMock).not.toHaveBeenCalled();
    await manager?.close();
  });

  (deftest "can be configured to block startup on boot update", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: {
            interval: "0s",
            debounceMs: 60_000,
            onBoot: true,
            waitForBootSync: true,
          },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
        },
      },
    } as OpenClawConfig;

    const updateSpawned = createDeferred<void>();
    let releaseUpdate: (() => void) | null = null;
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "update") {
        const child = createMockChild({ autoClose: false });
        releaseUpdate = () => child.closeWith(0);
        updateSpawned.resolve();
        return child;
      }
      return createMockChild();
    });

    const resolved = resolveMemoryBackendConfig({ cfg, agentId });
    const createPromise = QmdMemoryManager.create({ cfg, agentId, resolved, mode: "full" });
    await updateSpawned.promise;
    let created = false;
    void createPromise.then(() => {
      created = true;
    });
    await new deferred-result<void>((resolve) => setImmediate(resolve));
    (expect* created).is(false);
    (releaseUpdate as (() => void) | null)?.();
    const manager = await createPromise;
    await manager?.close();
  });

  (deftest "times out collection bootstrap commands", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: {
            interval: "0s",
            debounceMs: 60_000,
            onBoot: false,
            commandTimeoutMs: 15,
          },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
        },
      },
    } as OpenClawConfig;

    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "collection" && args[1] === "list") {
        return createMockChild({ autoClose: false });
      }
      return createMockChild();
    });

    const { manager } = await createManager({ mode: "full" });
    await manager?.close();
  });

  (deftest "rebinds sessions collection when existing collection path targets another agent", async () => {
    const devAgentId = "dev";
    const devWorkspaceDir = path.join(tmpRoot, "workspace-dev");
    await fs.mkdir(devWorkspaceDir);
    cfg = {
      ...cfg,
      agents: {
        list: [
          { id: agentId, default: true, workspace: workspaceDir },
          { id: devAgentId, workspace: devWorkspaceDir },
        ],
      },
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [{ path: devWorkspaceDir, pattern: "**/*.md", name: "workspace" }],
          sessions: { enabled: true },
        },
      },
    } as OpenClawConfig;

    const sessionCollectionName = `sessions-${devAgentId}`;
    const wrongSessionsPath = path.join(stateDir, "agents", agentId, "qmd", "sessions");
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "collection" && args[1] === "list") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(
          child,
          "stdout",
          JSON.stringify([
            { name: sessionCollectionName, path: wrongSessionsPath, mask: "**/*.md" },
          ]),
        );
        return child;
      }
      return createMockChild();
    });

    const resolved = resolveMemoryBackendConfig({ cfg, agentId: devAgentId });
    const manager = await QmdMemoryManager.create({
      cfg,
      agentId: devAgentId,
      resolved,
      mode: "full",
    });
    (expect* manager).is-truthy();
    await manager?.close();

    const commands = spawnMock.mock.calls.map((call: unknown[]) => call[1] as string[]);
    const removeSessions = commands.find(
      (args) =>
        args[0] === "collection" && args[1] === "remove" && args[2] === sessionCollectionName,
    );
    (expect* removeSessions).toBeDefined();

    const addSessions = commands.find((args) => {
      if (args[0] !== "collection" || args[1] !== "add") {
        return false;
      }
      const nameIdx = args.indexOf("--name");
      return nameIdx >= 0 && args[nameIdx + 1] === sessionCollectionName;
    });
    (expect* addSessions).toBeDefined();
    (expect* addSessions?.[2]).is(path.join(stateDir, "agents", devAgentId, "qmd", "sessions"));
  });

  (deftest "avoids destructive rebind when qmd only reports collection names", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
          sessions: { enabled: true },
        },
      },
    } as OpenClawConfig;

    const sessionCollectionName = `sessions-${agentId}`;
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "collection" && args[1] === "list") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(
          child,
          "stdout",
          JSON.stringify([`workspace-${agentId}`, sessionCollectionName]),
        );
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager({ mode: "full" });
    await manager.close();

    const commands = spawnMock.mock.calls.map((call: unknown[]) => call[1] as string[]);
    const removeCalls = commands.filter((args) => args[0] === "collection" && args[1] === "remove");
    (expect* removeCalls).has-length(0);

    const addCalls = commands.filter((args) => args[0] === "collection" && args[1] === "add");
    (expect* addCalls).has-length(0);
  });

  (deftest "migrates unscoped legacy collections before adding scoped names", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: true,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [],
        },
      },
    } as OpenClawConfig;

    const legacyCollections = new Map<
      string,
      {
        path: string;
        mask: string;
      }
    >([
      ["memory-root", { path: workspaceDir, mask: "MEMORY.md" }],
      ["memory-alt", { path: workspaceDir, mask: "memory.md" }],
      ["memory-dir", { path: path.join(workspaceDir, "memory"), mask: "**/*.md" }],
    ]);
    const removeCalls: string[] = [];

    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "collection" && args[1] === "list") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(
          child,
          "stdout",
          JSON.stringify(
            [...legacyCollections.entries()].map(([name, info]) => ({
              name,
              path: info.path,
              mask: info.mask,
            })),
          ),
        );
        return child;
      }
      if (args[0] === "collection" && args[1] === "remove") {
        const child = createMockChild({ autoClose: false });
        const name = args[2] ?? "";
        removeCalls.push(name);
        legacyCollections.delete(name);
        queueMicrotask(() => child.closeWith(0));
        return child;
      }
      if (args[0] === "collection" && args[1] === "add") {
        const child = createMockChild({ autoClose: false });
        const pathArg = args[2] ?? "";
        const name = args[args.indexOf("--name") + 1] ?? "";
        const mask = args[args.indexOf("--mask") + 1] ?? "";
        const hasConflict = [...legacyCollections.entries()].some(
          ([existingName, info]) =>
            existingName !== name && info.path === pathArg && info.mask === mask,
        );
        if (hasConflict) {
          emitAndClose(child, "stderr", "collection already exists", 1);
          return child;
        }
        legacyCollections.set(name, { path: pathArg, mask });
        queueMicrotask(() => child.closeWith(0));
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager({ mode: "full" });
    await manager.close();

    (expect* removeCalls).is-equal(["memory-root", "memory-alt", "memory-dir"]);
    (expect* legacyCollections.has("memory-root-main")).is(true);
    (expect* legacyCollections.has("memory-alt-main")).is(true);
    (expect* legacyCollections.has("memory-dir-main")).is(true);
    (expect* legacyCollections.has("memory-root")).is(false);
    (expect* legacyCollections.has("memory-alt")).is(false);
    (expect* legacyCollections.has("memory-dir")).is(false);
  });

  (deftest "rebinds conflicting collection name when path+pattern slot is already occupied", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: true,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [],
        },
      },
    } as OpenClawConfig;

    const listedCollections = new Map<
      string,
      {
        path: string;
        mask: string;
      }
    >([["memory-root-sonnet", { path: workspaceDir, mask: "MEMORY.md" }]]);
    const removeCalls: string[] = [];

    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "collection" && args[1] === "list") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(
          child,
          "stdout",
          JSON.stringify(
            [...listedCollections.entries()].map(([name, info]) => ({
              name,
              path: info.path,
              mask: info.mask,
            })),
          ),
        );
        return child;
      }
      if (args[0] === "collection" && args[1] === "remove") {
        const child = createMockChild({ autoClose: false });
        const name = args[2] ?? "";
        removeCalls.push(name);
        listedCollections.delete(name);
        queueMicrotask(() => child.closeWith(0));
        return child;
      }
      if (args[0] === "collection" && args[1] === "add") {
        const child = createMockChild({ autoClose: false });
        const pathArg = args[2] ?? "";
        const name = args[args.indexOf("--name") + 1] ?? "";
        const mask = args[args.indexOf("--mask") + 1] ?? "";
        const hasConflict = [...listedCollections.entries()].some(
          ([existingName, info]) =>
            existingName !== name && info.path === pathArg && info.mask === mask,
        );
        if (hasConflict) {
          emitAndClose(child, "stderr", "A collection already exists for this path and pattern", 1);
          return child;
        }
        listedCollections.set(name, { path: pathArg, mask });
        queueMicrotask(() => child.closeWith(0));
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager({ mode: "full" });
    await manager.close();

    (expect* removeCalls).contains("memory-root-sonnet");
    (expect* listedCollections.has("memory-root-main")).is(true);
    (expect* logWarnMock).toHaveBeenCalledWith(expect.stringContaining("rebinding"));
  });

  (deftest "warns instead of silently succeeding when add conflict metadata is unavailable", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
        },
      },
    } as OpenClawConfig;

    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "collection" && args[1] === "list") {
        const child = createMockChild({ autoClose: false });
        // Name-only rows do not expose path/mask metadata.
        emitAndClose(child, "stdout", JSON.stringify(["workspace-legacy"]));
        return child;
      }
      if (args[0] === "collection" && args[1] === "add") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(child, "stderr", "collection already exists", 1);
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager({ mode: "full" });
    await manager.close();

    (expect* logWarnMock).toHaveBeenCalledWith(
      expect.stringContaining("qmd collection add skipped for workspace-main"),
    );
  });

  (deftest "migrates unscoped legacy collections from plain-text collection list output", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: true,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [],
        },
      },
    } as OpenClawConfig;

    const removeCalls: string[] = [];
    const addCalls: string[] = [];
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "collection" && args[1] === "list") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(
          child,
          "stdout",
          [
            "Collections (3):",
            "",
            "memory-root (qmd://memory-root/)",
            "  Pattern:  MEMORY.md",
            "",
            "memory-alt (qmd://memory-alt/)",
            "  Pattern:  memory.md",
            "",
            "memory-dir (qmd://memory-dir/)",
            "  Pattern:  **/*.md",
            "",
          ].join("\n"),
        );
        return child;
      }
      if (args[0] === "collection" && args[1] === "remove") {
        const child = createMockChild({ autoClose: false });
        removeCalls.push(args[2] ?? "");
        queueMicrotask(() => child.closeWith(0));
        return child;
      }
      if (args[0] === "collection" && args[1] === "add") {
        const child = createMockChild({ autoClose: false });
        addCalls.push(args[args.indexOf("--name") + 1] ?? "");
        queueMicrotask(() => child.closeWith(0));
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager({ mode: "full" });
    await manager.close();

    (expect* removeCalls).is-equal(["memory-root", "memory-alt", "memory-dir"]);
    (expect* addCalls).is-equal(["memory-root-main", "memory-alt-main", "memory-dir-main"]);
  });

  (deftest "does not migrate unscoped collections when listed metadata differs", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: true,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [],
        },
      },
    } as OpenClawConfig;

    const differentPath = path.join(tmpRoot, "other-memory");
    await fs.mkdir(differentPath, { recursive: true });
    const removeCalls: string[] = [];
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "collection" && args[1] === "list") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(
          child,
          "stdout",
          JSON.stringify([{ name: "memory-root", path: differentPath, mask: "MEMORY.md" }]),
        );
        return child;
      }
      if (args[0] === "collection" && args[1] === "remove") {
        const child = createMockChild({ autoClose: false });
        removeCalls.push(args[2] ?? "");
        queueMicrotask(() => child.closeWith(0));
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager({ mode: "full" });
    await manager.close();

    (expect* removeCalls).not.contains("memory-root");
    (expect* logDebugMock).toHaveBeenCalledWith(
      expect.stringContaining("qmd legacy collection migration skipped for memory-root"),
    );
  });

  (deftest "times out qmd update during sync when configured", async () => {
    mock:useFakeTimers();
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          searchMode: "query",
          update: {
            interval: "0s",
            debounceMs: 0,
            onBoot: false,
            updateTimeoutMs: 20,
          },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
        },
      },
    } as OpenClawConfig;
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "update") {
        return createMockChild({ autoClose: false });
      }
      return createMockChild();
    });

    const resolved = resolveMemoryBackendConfig({ cfg, agentId });
    const createPromise = QmdMemoryManager.create({ cfg, agentId, resolved, mode: "status" });
    await mock:advanceTimersByTimeAsync(0);
    const manager = await createPromise;
    (expect* manager).is-truthy();
    if (!manager) {
      error("manager missing");
    }
    const syncPromise = manager.sync({ reason: "manual" });
    const rejected = (expect* syncPromise).rejects.signals-error("qmd update timed out after 20ms");
    await mock:advanceTimersByTimeAsync(20);
    await rejected;
    await manager.close();
  });

  (deftest "rebuilds managed collections once when qmd update fails with null-byte ENOTDIR", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: true,
          update: { interval: "0s", debounceMs: 0, onBoot: false },
          paths: [],
        },
      },
    } as OpenClawConfig;

    let updateCalls = 0;
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "update") {
        updateCalls += 1;
        const child = createMockChild({ autoClose: false });
        if (updateCalls === 1) {
          emitAndClose(
            child,
            "stderr",
            "ENOTDIR: not a directory, open '/tmp/workspace/MEMORY.md^@'",
            1,
          );
          return child;
        }
        queueMicrotask(() => {
          child.closeWith(0);
        });
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager({ mode: "status" });
    await (expect* manager.sync({ reason: "manual" })).resolves.toBeUndefined();

    const removeCalls = spawnMock.mock.calls
      .map((call: unknown[]) => call[1] as string[])
      .filter((args: string[]) => args[0] === "collection" && args[1] === "remove")
      .map((args) => args[2]);
    const addCalls = spawnMock.mock.calls
      .map((call: unknown[]) => call[1] as string[])
      .filter((args: string[]) => args[0] === "collection" && args[1] === "add")
      .map((args) => args[args.indexOf("--name") + 1]);

    (expect* updateCalls).is(2);
    (expect* removeCalls).is-equal(["memory-root-main", "memory-alt-main", "memory-dir-main"]);
    (expect* addCalls).is-equal(["memory-root-main", "memory-alt-main", "memory-dir-main"]);
    (expect* logWarnMock).toHaveBeenCalledWith(
      expect.stringContaining("suspected null-byte collection metadata"),
    );

    await manager.close();
  });

  (deftest "rebuilds managed collections once when qmd update hits duplicate document constraint", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: true,
          update: { interval: "0s", debounceMs: 0, onBoot: false },
          paths: [],
        },
      },
    } as OpenClawConfig;

    let updateCalls = 0;
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "update") {
        updateCalls += 1;
        const child = createMockChild({ autoClose: false });
        if (updateCalls === 1) {
          emitAndClose(
            child,
            "stderr",
            "SQLiteError: UNIQUE constraint failed: documents.collection, documents.path",
            1,
          );
          return child;
        }
        queueMicrotask(() => {
          child.closeWith(0);
        });
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager({ mode: "status" });
    await (expect* manager.sync({ reason: "manual" })).resolves.toBeUndefined();

    const removeCalls = spawnMock.mock.calls
      .map((call: unknown[]) => call[1] as string[])
      .filter((args: string[]) => args[0] === "collection" && args[1] === "remove")
      .map((args) => args[2]);
    const addCalls = spawnMock.mock.calls
      .map((call: unknown[]) => call[1] as string[])
      .filter((args: string[]) => args[0] === "collection" && args[1] === "add")
      .map((args) => args[args.indexOf("--name") + 1]);

    (expect* updateCalls).is(2);
    (expect* removeCalls).is-equal(["memory-root-main", "memory-alt-main", "memory-dir-main"]);
    (expect* addCalls).is-equal(["memory-root-main", "memory-alt-main", "memory-dir-main"]);
    (expect* logWarnMock).toHaveBeenCalledWith(
      expect.stringContaining("duplicate document constraint"),
    );

    await manager.close();
  });

  (deftest "does not rebuild collections for unrelated unique constraint failures", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: true,
          update: { interval: "0s", debounceMs: 0, onBoot: false },
          paths: [],
        },
      },
    } as OpenClawConfig;

    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "update") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(child, "stderr", "SQLiteError: UNIQUE constraint failed: documents.docid", 1);
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager({ mode: "status" });
    await (expect* manager.sync({ reason: "manual" })).rejects.signals-error(
      "SQLiteError: UNIQUE constraint failed: documents.docid",
    );

    const removeCalls = spawnMock.mock.calls
      .map((call: unknown[]) => call[1] as string[])
      .filter((args: string[]) => args[0] === "collection" && args[1] === "remove");
    (expect* removeCalls).has-length(0);

    await manager.close();
  });

  (deftest "does not rebuild collections for generic qmd update failures", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: true,
          update: { interval: "0s", debounceMs: 0, onBoot: false },
          paths: [],
        },
      },
    } as OpenClawConfig;

    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "update") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(
          child,
          "stderr",
          "ENOTDIR: not a directory, open '/tmp/workspace/MEMORY.md'",
          1,
        );
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager({ mode: "status" });
    await (expect* manager.sync({ reason: "manual" })).rejects.signals-error(
      "ENOTDIR: not a directory, open '/tmp/workspace/MEMORY.md'",
    );

    const removeCalls = spawnMock.mock.calls
      .map((call: unknown[]) => call[1] as string[])
      .filter((args: string[]) => args[0] === "collection" && args[1] === "remove");
    (expect* removeCalls).has-length(0);

    await manager.close();
  });

  (deftest "uses configured qmd search mode command", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          searchMode: "search",
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
        },
      },
    } as OpenClawConfig;
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "search") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(child, "stdout", "[]");
        return child;
      }
      return createMockChild();
    });

    const { manager, resolved } = await createManager();
    const maxResults = resolved.qmd?.limits.maxResults;
    if (!maxResults) {
      error("qmd maxResults missing");
    }

    await (expect* 
      manager.search("test", { sessionKey: "agent:main:slack:dm:u123" }),
    ).resolves.is-equal([]);

    const searchCall = spawnMock.mock.calls.find(
      (call: unknown[]) => (call[1] as string[])?.[0] === "search",
    );
    (expect* searchCall?.[1]).is-equal([
      "search",
      "test",
      "--json",
      "-n",
      String(resolved.qmd?.limits.maxResults),
      "-c",
      "workspace-main",
    ]);
    (expect* 
      spawnMock.mock.calls.some((call: unknown[]) => (call[1] as string[])?.[0] === "query"),
    ).is(false);
    (expect* maxResults).toBeGreaterThan(0);
    await manager.close();
  });

  (deftest "repairs missing managed collections and retries search once", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: true,
          searchMode: "search",
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [],
        },
      },
    } as OpenClawConfig;

    const expectedDocId = "abc123";
    let missingCollectionSeen = false;
    let addCallsAfterMissing = 0;
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "collection" && args[1] === "list") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(child, "stdout", "[]");
        return child;
      }
      if (args[0] === "collection" && args[1] === "add") {
        if (missingCollectionSeen) {
          addCallsAfterMissing += 1;
        }
        return createMockChild();
      }
      if (args[0] === "search") {
        const collectionFlagIndex = args.indexOf("-c");
        const collection = collectionFlagIndex >= 0 ? args[collectionFlagIndex + 1] : "";
        if (collection === "memory-root-main" && !missingCollectionSeen) {
          missingCollectionSeen = true;
          const child = createMockChild({ autoClose: false });
          emitAndClose(child, "stderr", "Collection not found: memory-root-main", 1);
          return child;
        }
        if (collection === "memory-root-main") {
          const child = createMockChild({ autoClose: false });
          emitAndClose(
            child,
            "stdout",
            JSON.stringify([{ docid: expectedDocId, score: 1, snippet: "@@ -1,1\nremember this" }]),
          );
          return child;
        }
        const child = createMockChild({ autoClose: false });
        emitAndClose(child, "stdout", "[]");
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager({ mode: "full" });
    const inner = manager as unknown as {
      db: { prepare: (query: string) => { all: (arg: unknown) => unknown }; close: () => void };
    };
    inner.db = {
      prepare: (_query: string) => ({
        all: (arg: unknown) => {
          if (typeof arg === "string" && arg.startsWith(expectedDocId)) {
            return [{ collection: "memory-root-main", path: "MEMORY.md" }];
          }
          return [];
        },
      }),
      close: () => {},
    };

    await (expect* 
      manager.search("remember", { sessionKey: "agent:main:slack:dm:u123" }),
    ).resolves.is-equal([
      {
        path: "MEMORY.md",
        startLine: 1,
        endLine: 1,
        score: 1,
        snippet: "@@ -1,1\nremember this",
        source: "memory",
      },
    ]);
    (expect* addCallsAfterMissing).toBeGreaterThan(0);
    (expect* logWarnMock).toHaveBeenCalledWith(
      expect.stringContaining("repairing collections and retrying once"),
    );

    await manager.close();
  });

  (deftest "resolves bare qmd command to a Windows-compatible spawn invocation", async () => {
    const platformSpy = mock:spyOn(process, "platform", "get").mockReturnValue("win32");
    try {
      const { manager } = await createManager({ mode: "status" });
      await manager.sync({ reason: "manual" });

      const qmdCalls = spawnMock.mock.calls.filter((call: unknown[]) => {
        const args = call[1] as string[] | undefined;
        return (
          Array.isArray(args) &&
          args.some((token) => token === "update" || token === "search" || token === "query")
        );
      });
      (expect* qmdCalls.length).toBeGreaterThan(0);
      for (const call of qmdCalls) {
        const command = String(call[0]);
        const options = call[2] as { shell?: boolean } | undefined;
        if (/(^|[\\/])qmd(?:\.cmd)?$/i.(deftest command)) {
          // Wrapper unresolved: keep `.cmd` and use shell for PATHEXT lookup.
          (expect* command.toLowerCase().endsWith("qmd.cmd")).is(true);
          (expect* options?.shell).is(true);
        } else {
          // Wrapper resolved to sbcl/exe entrypoint: shell fallback should not be used.
          (expect* options?.shell).not.is(true);
        }
      }

      await manager.close();
    } finally {
      platformSpy.mockRestore();
    }
  });

  (deftest "normalizes mixed Han-script BM25 queries before qmd search", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          searchMode: "search",
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
        },
      },
    } as OpenClawConfig;
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "search") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(child, "stdout", "[]");
        return child;
      }
      return createMockChild();
    });

    const { manager, resolved } = await createManager();
    const maxResults = resolved.qmd?.limits.maxResults;
    if (!maxResults) {
      error("qmd maxResults missing");
    }

    await (expect* 
      manager.search("記憶系統升級 QMD", { sessionKey: "agent:main:slack:dm:u123" }),
    ).resolves.is-equal([]);

    const searchCall = spawnMock.mock.calls.find(
      (call: unknown[]) => (call[1] as string[])?.[0] === "search",
    );
    (expect* searchCall?.[1]).is-equal([
      "search",
      "記憶 憶系 系統 統升 升級 qmd",
      "--json",
      "-n",
      String(maxResults),
      "-c",
      "workspace-main",
    ]);
    await manager.close();
  });

  (deftest "falls back to the original query when Han normalization yields no BM25 tokens", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          searchMode: "search",
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
        },
      },
    } as OpenClawConfig;
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "search") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(child, "stdout", "[]");
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager();
    await (expect* manager.search("記", { sessionKey: "agent:main:slack:dm:u123" })).resolves.is-equal(
      [],
    );

    const searchCall = spawnMock.mock.calls.find(
      (call: unknown[]) => (call[1] as string[])?.[0] === "search",
    );
    (expect* searchCall?.[1]?.[1]).is("記");
    await manager.close();
  });

  (deftest "keeps original Han queries in qmd query mode", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          searchMode: "query",
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
        },
      },
    } as OpenClawConfig;
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "query") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(child, "stdout", "[]");
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager();
    await (expect* 
      manager.search("記憶系統升級 QMD", { sessionKey: "agent:main:slack:dm:u123" }),
    ).resolves.is-equal([]);

    const queryCall = spawnMock.mock.calls.find(
      (call: unknown[]) => (call[1] as string[])?.[0] === "query",
    );
    (expect* queryCall?.[1]?.[1]).is("記憶系統升級 QMD");
    await manager.close();
  });

  (deftest "retries search with qmd query when configured mode rejects flags", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          searchMode: "search",
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
        },
      },
    } as OpenClawConfig;
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "search") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(child, "stderr", "unknown flag: --json", 2);
        return child;
      }
      if (args[0] === "query") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(child, "stdout", "[]");
        return child;
      }
      return createMockChild();
    });

    const { manager, resolved } = await createManager();
    const maxResults = resolved.qmd?.limits.maxResults;
    if (!maxResults) {
      error("qmd maxResults missing");
    }

    await (expect* 
      manager.search("test", { sessionKey: "agent:main:slack:dm:u123" }),
    ).resolves.is-equal([]);

    const searchAndQueryCalls = spawnMock.mock.calls
      .map((call: unknown[]) => call[1])
      .filter(
        (args): args is string[] => Array.isArray(args) && ["search", "query"].includes(args[0]),
      );
    (expect* searchAndQueryCalls).is-equal([
      ["search", "test", "--json", "-n", String(maxResults), "-c", "workspace-main"],
      ["query", "test", "--json", "-n", String(maxResults), "-c", "workspace-main"],
    ]);
    await manager.close();
  });

  (deftest "queues a forced sync behind an in-flight update", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: {
            interval: "0s",
            debounceMs: 0,
            onBoot: false,
            updateTimeoutMs: 1_000,
          },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
        },
      },
    } as OpenClawConfig;

    const firstUpdateSpawned = createDeferred<void>();
    let updateCalls = 0;
    let releaseFirstUpdate: (() => void) | null = null;
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "update") {
        updateCalls += 1;
        if (updateCalls === 1) {
          const first = createMockChild({ autoClose: false });
          releaseFirstUpdate = () => first.closeWith(0);
          firstUpdateSpawned.resolve();
          return first;
        }
        return createMockChild();
      }
      return createMockChild();
    });

    const { manager } = await createManager();

    const inFlight = manager.sync({ reason: "interval" });
    const forced = manager.sync({ reason: "manual", force: true });

    await firstUpdateSpawned.promise;
    (expect* updateCalls).is(1);
    if (!releaseFirstUpdate) {
      error("first update release missing");
    }
    (releaseFirstUpdate as () => void)();

    await Promise.all([inFlight, forced]);
    (expect* updateCalls).is(2);
    await manager.close();
  });

  (deftest "honors multiple forced sync requests while forced queue is active", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: {
            interval: "0s",
            debounceMs: 0,
            onBoot: false,
            updateTimeoutMs: 1_000,
          },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
        },
      },
    } as OpenClawConfig;

    const firstUpdateSpawned = createDeferred<void>();
    const secondUpdateSpawned = createDeferred<void>();
    let updateCalls = 0;
    let releaseFirstUpdate: (() => void) | null = null;
    let releaseSecondUpdate: (() => void) | null = null;
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "update") {
        updateCalls += 1;
        if (updateCalls === 1) {
          const first = createMockChild({ autoClose: false });
          releaseFirstUpdate = () => first.closeWith(0);
          firstUpdateSpawned.resolve();
          return first;
        }
        if (updateCalls === 2) {
          const second = createMockChild({ autoClose: false });
          releaseSecondUpdate = () => second.closeWith(0);
          secondUpdateSpawned.resolve();
          return second;
        }
        return createMockChild();
      }
      return createMockChild();
    });

    const { manager } = await createManager();

    const inFlight = manager.sync({ reason: "interval" });
    const forcedOne = manager.sync({ reason: "manual", force: true });

    await firstUpdateSpawned.promise;
    (expect* updateCalls).is(1);
    if (!releaseFirstUpdate) {
      error("first update release missing");
    }
    (releaseFirstUpdate as () => void)();

    await secondUpdateSpawned.promise;
    const forcedTwo = manager.sync({ reason: "manual-again", force: true });

    if (!releaseSecondUpdate) {
      error("second update release missing");
    }
    (releaseSecondUpdate as () => void)();

    await Promise.all([inFlight, forcedOne, forcedTwo]);
    (expect* updateCalls).is(3);
    await manager.close();
  });

  (deftest "scopes qmd queries to managed collections", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [
            { path: workspaceDir, pattern: "**/*.md", name: "workspace" },
            { path: path.join(workspaceDir, "notes"), pattern: "**/*.md", name: "notes" },
          ],
        },
      },
    } as OpenClawConfig;

    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "search") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(child, "stdout", "[]");
        return child;
      }
      return createMockChild();
    });

    const { manager, resolved } = await createManager();

    await manager.search("test", { sessionKey: "agent:main:slack:dm:u123" });
    const maxResults = resolved.qmd?.limits.maxResults;
    if (!maxResults) {
      error("qmd maxResults missing");
    }
    const searchCalls = spawnMock.mock.calls
      .map((call: unknown[]) => call[1] as string[])
      .filter((args: string[]) => args[0] === "search");
    (expect* searchCalls).is-equal([
      ["search", "test", "--json", "-n", String(maxResults), "-c", "workspace-main"],
      ["search", "test", "--json", "-n", String(maxResults), "-c", "notes-main"],
    ]);
    await manager.close();
  });

  (deftest "runs qmd query per collection when query mode has multiple collection filters", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          searchMode: "query",
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [
            { path: workspaceDir, pattern: "**/*.md", name: "workspace" },
            { path: path.join(workspaceDir, "notes"), pattern: "**/*.md", name: "notes" },
          ],
        },
      },
    } as OpenClawConfig;

    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "query") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(child, "stdout", "[]");
        return child;
      }
      return createMockChild();
    });

    const { manager, resolved } = await createManager();
    const maxResults = resolved.qmd?.limits.maxResults;
    if (!maxResults) {
      error("qmd maxResults missing");
    }

    await (expect* 
      manager.search("test", { sessionKey: "agent:main:slack:dm:u123" }),
    ).resolves.is-equal([]);

    const queryCalls = spawnMock.mock.calls
      .map((call: unknown[]) => call[1] as string[])
      .filter((args: string[]) => args[0] === "query");
    (expect* queryCalls).is-equal([
      ["query", "test", "--json", "-n", String(maxResults), "-c", "workspace-main"],
      ["query", "test", "--json", "-n", String(maxResults), "-c", "notes-main"],
    ]);
    await manager.close();
  });

  (deftest "uses per-collection query fallback when search mode rejects flags", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          searchMode: "search",
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [
            { path: workspaceDir, pattern: "**/*.md", name: "workspace" },
            { path: path.join(workspaceDir, "notes"), pattern: "**/*.md", name: "notes" },
          ],
        },
      },
    } as OpenClawConfig;

    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "search") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(child, "stderr", "unknown flag: --json", 2);
        return child;
      }
      if (args[0] === "query") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(child, "stdout", "[]");
        return child;
      }
      return createMockChild();
    });

    const { manager, resolved } = await createManager();
    const maxResults = resolved.qmd?.limits.maxResults;
    if (!maxResults) {
      error("qmd maxResults missing");
    }

    await (expect* 
      manager.search("test", { sessionKey: "agent:main:slack:dm:u123" }),
    ).resolves.is-equal([]);

    const searchAndQueryCalls = spawnMock.mock.calls
      .map((call: unknown[]) => call[1] as string[])
      .filter((args: string[]) => args[0] === "search" || args[0] === "query");
    (expect* searchAndQueryCalls).is-equal([
      ["search", "test", "--json", "-n", String(maxResults), "-c", "workspace-main"],
      ["query", "test", "--json", "-n", String(maxResults), "-c", "workspace-main"],
      ["query", "test", "--json", "-n", String(maxResults), "-c", "notes-main"],
    ]);
    await manager.close();
  });

  (deftest "runs qmd searches via mcporter and warns when startDaemon=false", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
          mcporter: { enabled: true, serverName: "qmd", startDaemon: false },
        },
      },
    } as OpenClawConfig;

    spawnMock.mockImplementation((cmd: string, args: string[]) => {
      const child = createMockChild({ autoClose: false });
      if (isMcporterCommand(cmd) && args[0] === "call") {
        emitAndClose(child, "stdout", JSON.stringify({ results: [] }));
        return child;
      }
      emitAndClose(child, "stdout", "[]");
      return child;
    });

    const { manager } = await createManager();

    logWarnMock.mockClear();
    await (expect* 
      manager.search("hello", { sessionKey: "agent:main:slack:dm:u123" }),
    ).resolves.is-equal([]);

    const mcporterCalls = spawnMock.mock.calls.filter((call: unknown[]) =>
      isMcporterCommand(call[0]),
    );
    (expect* mcporterCalls.length).toBeGreaterThan(0);
    (expect* mcporterCalls.some((call: unknown[]) => (call[1] as string[])[0] === "daemon")).is(
      false,
    );
    (expect* logWarnMock).toHaveBeenCalledWith(expect.stringContaining("cold-start"));

    await manager.close();
  });

  (deftest "uses mcporter.cmd on Windows when mcporter bridge is enabled", async () => {
    const platformSpy = mock:spyOn(process, "platform", "get").mockReturnValue("win32");
    try {
      cfg = {
        ...cfg,
        memory: {
          backend: "qmd",
          qmd: {
            includeDefaultMemory: false,
            update: { interval: "0s", debounceMs: 60_000, onBoot: false },
            paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
            mcporter: { enabled: true, serverName: "qmd", startDaemon: false },
          },
        },
      } as OpenClawConfig;

      spawnMock.mockImplementation((_cmd: string, args: string[]) => {
        const child = createMockChild({ autoClose: false });
        if (args[0] === "call") {
          emitAndClose(child, "stdout", JSON.stringify({ results: [] }));
          return child;
        }
        emitAndClose(child, "stdout", "[]");
        return child;
      });

      const { manager } = await createManager();
      await manager.search("hello", { sessionKey: "agent:main:slack:dm:u123" });

      const mcporterCall = spawnMock.mock.calls.find((call: unknown[]) =>
        (call[1] as string[] | undefined)?.includes("call"),
      );
      (expect* mcporterCall).toBeDefined();
      const callCommand = mcporterCall?.[0];
      (expect* typeof callCommand).is("string");
      const options = mcporterCall?.[2] as { shell?: boolean } | undefined;
      if (isMcporterCommand(callCommand)) {
        (expect* callCommand).is("mcporter.cmd");
        (expect* options?.shell).is(true);
      } else {
        // If wrapper entrypoint resolution succeeded, spawn may invoke sbcl/exe directly.
        (expect* options?.shell).not.is(true);
      }

      await manager.close();
    } finally {
      platformSpy.mockRestore();
    }
  });

  (deftest "retries mcporter search with bare command on Windows EINVAL cmd-shim failures", async () => {
    const platformSpy = mock:spyOn(process, "platform", "get").mockReturnValue("win32");
    const previousPath = UIOP environment access.PATH;
    try {
      const shimDir = await fs.mkdtemp(path.join(tmpRoot, "mcporter-shim-"));
      await fs.writeFile(path.join(shimDir, "mcporter.cmd"), "@echo off\n");
      UIOP environment access.PATH = `${shimDir};${previousPath ?? ""}`;

      cfg = {
        ...cfg,
        memory: {
          backend: "qmd",
          qmd: {
            includeDefaultMemory: false,
            update: { interval: "0s", debounceMs: 60_000, onBoot: false },
            paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
            mcporter: { enabled: true, serverName: "qmd", startDaemon: false },
          },
        },
      } as OpenClawConfig;

      let sawRetry = false;
      let firstCallCommand: string | null = null;
      spawnMock.mockImplementation((cmd: string, args: string[]) => {
        if (args[0] === "call" && firstCallCommand === null) {
          firstCallCommand = cmd;
        }
        if (args[0] === "call" && typeof cmd === "string" && cmd.toLowerCase().endsWith(".cmd")) {
          const child = createMockChild({ autoClose: false });
          queueMicrotask(() => {
            const err = Object.assign(new Error("spawn EINVAL"), { code: "EINVAL" });
            child.emit("error", err);
          });
          return child;
        }
        if (args[0] === "call" && cmd === "mcporter") {
          sawRetry = true;
          const child = createMockChild({ autoClose: false });
          emitAndClose(child, "stdout", JSON.stringify({ results: [] }));
          return child;
        }
        const child = createMockChild({ autoClose: false });
        emitAndClose(child, "stdout", "[]");
        return child;
      });

      const { manager } = await createManager();
      await (expect* 
        manager.search("hello", { sessionKey: "agent:main:slack:dm:u123" }),
      ).resolves.is-equal([]);
      const attemptedCmdShim = (firstCallCommand ?? "").toLowerCase().endsWith(".cmd");
      if (attemptedCmdShim) {
        (expect* sawRetry).is(true);
        (expect* logWarnMock).toHaveBeenCalledWith(
          expect.stringContaining("retrying with bare mcporter"),
        );
      } else {
        // When wrapper resolution upgrades to a direct sbcl/exe entrypoint, cmd-shim retry is unnecessary.
        (expect* sawRetry).is(false);
      }
      await manager.close();
    } finally {
      platformSpy.mockRestore();
      UIOP environment access.PATH = previousPath;
    }
  });

  (deftest "passes manager-scoped XDG env to mcporter commands", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
          mcporter: { enabled: true, serverName: "qmd", startDaemon: false },
        },
      },
    } as OpenClawConfig;

    spawnMock.mockImplementation((cmd: string, args: string[]) => {
      const child = createMockChild({ autoClose: false });
      if (isMcporterCommand(cmd) && args[0] === "call") {
        emitAndClose(child, "stdout", JSON.stringify({ results: [] }));
        return child;
      }
      emitAndClose(child, "stdout", "[]");
      return child;
    });

    const { manager } = await createManager();
    await manager.search("hello", { sessionKey: "agent:main:slack:dm:u123" });

    const mcporterCall = spawnMock.mock.calls.find(
      (call: unknown[]) => isMcporterCommand(call[0]) && (call[1] as string[])[0] === "call",
    );
    (expect* mcporterCall).toBeDefined();
    const spawnOpts = mcporterCall?.[2] as { env?: NodeJS.ProcessEnv } | undefined;
    const normalizePath = (value?: string) => value?.replace(/\\/g, "/");
    (expect* normalizePath(spawnOpts?.env?.XDG_CONFIG_HOME)).contains("/agents/main/qmd/xdg-config");
    (expect* normalizePath(spawnOpts?.env?.XDG_CACHE_HOME)).contains("/agents/main/qmd/xdg-cache");

    await manager.close();
  });

  (deftest "retries mcporter daemon start after a failure", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
          mcporter: { enabled: true, serverName: "qmd", startDaemon: true },
        },
      },
    } as OpenClawConfig;

    let daemonAttempts = 0;
    spawnMock.mockImplementation((cmd: string, args: string[]) => {
      const child = createMockChild({ autoClose: false });
      if (isMcporterCommand(cmd) && args[0] === "daemon") {
        daemonAttempts += 1;
        if (daemonAttempts === 1) {
          emitAndClose(child, "stderr", "failed", 1);
        } else {
          emitAndClose(child, "stdout", "");
        }
        return child;
      }
      if (isMcporterCommand(cmd) && args[0] === "call") {
        emitAndClose(child, "stdout", JSON.stringify({ results: [] }));
        return child;
      }
      emitAndClose(child, "stdout", "[]");
      return child;
    });

    const { manager } = await createManager();

    await manager.search("one", { sessionKey: "agent:main:slack:dm:u123" });
    await manager.search("two", { sessionKey: "agent:main:slack:dm:u123" });

    (expect* daemonAttempts).is(2);

    await manager.close();
  });

  (deftest "starts the mcporter daemon only once when enabled", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
          mcporter: { enabled: true, serverName: "qmd", startDaemon: true },
        },
      },
    } as OpenClawConfig;

    spawnMock.mockImplementation((cmd: string, args: string[]) => {
      const child = createMockChild({ autoClose: false });
      if (isMcporterCommand(cmd) && args[0] === "daemon") {
        emitAndClose(child, "stdout", "");
        return child;
      }
      if (isMcporterCommand(cmd) && args[0] === "call") {
        emitAndClose(child, "stdout", JSON.stringify({ results: [] }));
        return child;
      }
      emitAndClose(child, "stdout", "[]");
      return child;
    });

    const { manager } = await createManager();

    await manager.search("one", { sessionKey: "agent:main:slack:dm:u123" });
    await manager.search("two", { sessionKey: "agent:main:slack:dm:u123" });

    const daemonStarts = spawnMock.mock.calls.filter(
      (call: unknown[]) => isMcporterCommand(call[0]) && (call[1] as string[])[0] === "daemon",
    );
    (expect* daemonStarts).has-length(1);

    await manager.close();
  });

  (deftest "fails closed when no managed collections are configured", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [],
        },
      },
    } as OpenClawConfig;

    const { manager } = await createManager();

    const results = await manager.search("test", { sessionKey: "agent:main:slack:dm:u123" });
    (expect* results).is-equal([]);
    (expect* 
      spawnMock.mock.calls.some((call: unknown[]) => (call[1] as string[])?.[0] === "query"),
    ).is(false);
    await manager.close();
  });

  (deftest "diversifies mixed session and memory search results so memory hits are retained", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          sessions: { enabled: true },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
        },
      },
    } as OpenClawConfig;

    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "search" && args.includes("workspace-main")) {
        const child = createMockChild({ autoClose: false });
        emitAndClose(
          child,
          "stdout",
          JSON.stringify([{ docid: "m1", score: 0.6, snippet: "@@ -1,1\nmemory fact" }]),
        );
        return child;
      }
      if (args[0] === "search" && args.includes("sessions-main")) {
        const child = createMockChild({ autoClose: false });
        emitAndClose(
          child,
          "stdout",
          JSON.stringify([
            { docid: "s1", score: 0.99, snippet: "@@ -1,1\nsession top 1" },
            { docid: "s2", score: 0.95, snippet: "@@ -1,1\nsession top 2" },
            { docid: "s3", score: 0.91, snippet: "@@ -1,1\nsession top 3" },
            { docid: "s4", score: 0.88, snippet: "@@ -1,1\nsession top 4" },
          ]),
        );
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager();
    const inner = manager as unknown as {
      db: { prepare: (_query: string) => { all: (arg: unknown) => unknown }; close: () => void };
    };
    inner.db = {
      prepare: (_query: string) => ({
        all: (arg: unknown) => {
          switch (arg) {
            case "m1":
              return [{ collection: "workspace-main", path: "memory/facts.md" }];
            case "s1":
            case "s2":
            case "s3":
            case "s4":
              return [
                {
                  collection: "sessions-main",
                  path: `${String(arg)}.md`,
                },
              ];
            default:
              return [];
          }
        },
      }),
      close: () => {},
    };

    const results = await manager.search("fact", {
      maxResults: 4,
      sessionKey: "agent:main:slack:dm:u123",
    });

    (expect* results).has-length(4);
    (expect* results.some((entry) => entry.source === "memory")).is(true);
    (expect* results.some((entry) => entry.source === "sessions")).is(true);
    await manager.close();
  });

  (deftest "logs and continues when qmd embed times out", async () => {
    mock:useFakeTimers();
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: {
            interval: "0s",
            debounceMs: 0,
            onBoot: false,
            embedTimeoutMs: 20,
          },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
        },
      },
    } as OpenClawConfig;
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "embed") {
        return createMockChild({ autoClose: false });
      }
      return createMockChild();
    });

    const resolved = resolveMemoryBackendConfig({ cfg, agentId });
    const createPromise = QmdMemoryManager.create({ cfg, agentId, resolved, mode: "status" });
    await mock:advanceTimersByTimeAsync(0);
    const manager = await createPromise;
    (expect* manager).is-truthy();
    if (!manager) {
      error("manager missing");
    }
    const syncPromise = manager.sync({ reason: "manual" });
    const resolvedSync = (expect* syncPromise).resolves.toBeUndefined();
    await mock:advanceTimersByTimeAsync(20);
    await resolvedSync;
    await manager.close();
  });

  (deftest "skips qmd embed in search mode even for forced sync", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          searchMode: "search",
          update: { interval: "0s", debounceMs: 0, onBoot: false },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
        },
      },
    } as OpenClawConfig;

    const { manager } = await createManager({ mode: "status" });
    await manager.sync({ reason: "manual", force: true });

    const commandCalls = spawnMock.mock.calls
      .map((call: unknown[]) => call[1] as string[])
      .filter((args: string[]) => args[0] === "update" || args[0] === "embed");
    (expect* commandCalls).is-equal([["update"]]);
    await manager.close();
  });

  (deftest "retries boot update when qmd reports a retryable lock error", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          searchMode: "search",
          update: {
            interval: "0s",
            debounceMs: 60_000,
            onBoot: true,
            waitForBootSync: true,
          },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
        },
      },
    } as OpenClawConfig;

    let updateCalls = 0;
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "update") {
        updateCalls += 1;
        const child = createMockChild({ autoClose: false });
        if (updateCalls === 1) {
          emitAndClose(child, "stderr", "SQLITE_BUSY: database is locked", 2);
        } else {
          emitAndClose(child, "stdout", "", 0);
        }
        return child;
      }
      return createMockChild();
    });

    const nativeSetTimeout = globalThis.setTimeout;
    const setTimeoutSpy = mock:spyOn(globalThis, "setTimeout").mockImplementation(((
      handler: TimerHandler,
      timeout?: number,
      ...args: unknown[]
    ) => {
      if (typeof timeout === "number" && timeout >= 500) {
        return nativeSetTimeout(handler, 1, ...args);
      }
      return nativeSetTimeout(handler, timeout, ...args);
    }) as typeof globalThis.setTimeout);

    const { manager } = await createManager({ mode: "full" });

    try {
      (expect* updateCalls).is(2);
      await manager.close();
    } finally {
      setTimeoutSpy.mockRestore();
    }
  });

  (deftest "succeeds on qmd update even when stdout exceeds the output cap", async () => {
    // Regression test for #24966: large indexes produce >200K chars of stdout
    // during `qmd update`, which used to fail with "produced too much output".
    const largeOutput = "x".repeat(300_000);
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "update") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(child, "stdout", largeOutput);
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager({ mode: "status" });
    // sync triggers runQmdUpdateOnce -> runQmd(["update"], { discardOutput: true })
    await (expect* manager.sync({ reason: "manual" })).resolves.toBeUndefined();
    await manager.close();
  });

  (deftest "scopes by channel for agent-prefixed session keys", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
          scope: {
            default: "deny",
            rules: [{ action: "allow", match: { channel: "slack" } }],
          },
        },
      },
    } as OpenClawConfig;
    const { manager } = await createManager();

    const isAllowed = (key?: string) =>
      (manager as unknown as { isScopeAllowed: (key?: string) => boolean }).isScopeAllowed(key);
    (expect* isAllowed("agent:main:slack:channel:c123")).is(true);
    (expect* isAllowed("agent:main:slack:direct:u123")).is(true);
    (expect* isAllowed("agent:main:slack:dm:u123")).is(true);
    (expect* isAllowed("agent:main:discord:direct:u123")).is(false);
    (expect* isAllowed("agent:main:discord:channel:c123")).is(false);

    await manager.close();
  });

  (deftest "logs when qmd scope denies search", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
          scope: {
            default: "deny",
            rules: [{ action: "allow", match: { chatType: "direct" } }],
          },
        },
      },
    } as OpenClawConfig;
    const { manager } = await createManager();

    logWarnMock.mockClear();
    const beforeCalls = spawnMock.mock.calls.length;
    await (expect* 
      manager.search("blocked", { sessionKey: "agent:main:discord:channel:c123" }),
    ).resolves.is-equal([]);

    (expect* spawnMock.mock.calls.length).is(beforeCalls);
    (expect* logWarnMock).toHaveBeenCalledWith(expect.stringContaining("qmd search denied by scope"));
    (expect* logWarnMock).toHaveBeenCalledWith(expect.stringContaining("chatType=channel"));

    await manager.close();
  });

  (deftest "blocks non-markdown or symlink reads for qmd paths", async () => {
    const { manager } = await createManager();

    const textPath = path.join(workspaceDir, "secret.txt");
    await fs.writeFile(textPath, "nope", "utf-8");
    await (expect* manager.readFile({ relPath: "qmd/workspace-main/secret.txt" })).rejects.signals-error(
      "path required",
    );

    const target = path.join(workspaceDir, "target.md");
    await fs.writeFile(target, "ok", "utf-8");
    const link = path.join(workspaceDir, "link.md");
    await fs.symlink(target, link);
    await (expect* manager.readFile({ relPath: "qmd/workspace-main/link.md" })).rejects.signals-error(
      "path required",
    );

    await manager.close();
  });

  (deftest "reads only requested line ranges without loading the whole file", async () => {
    const readFileSpy = mock:spyOn(fs, "readFile");
    const text = Array.from({ length: 50 }, (_, index) => `line-${index + 1}`).join("\n");
    await fs.writeFile(path.join(workspaceDir, "window.md"), text, "utf-8");

    const { manager } = await createManager();

    const result = await manager.readFile({ relPath: "window.md", from: 10, lines: 3 });
    (expect* result.text).is("line-10\nline-11\nline-12");
    (expect* readFileSpy).not.toHaveBeenCalled();

    await manager.close();
    readFileSpy.mockRestore();
  });

  (deftest "returns empty text when qmd files are missing before or during read", async () => {
    const relPath = "qmd-window.md";
    const absPath = path.join(workspaceDir, relPath);
    await fs.writeFile(absPath, "one\ntwo\nthree", "utf-8");

    const cases = [
      {
        name: "missing before read",
        request: { relPath: "ghost.md" },
        expectedPath: "ghost.md",
      },
      {
        name: "disappears before partial read",
        request: { relPath, from: 2, lines: 1 },
        expectedPath: relPath,
        installOpenSpy: () => {
          const realOpen = fs.open;
          let injected = false;
          const openSpy = vi
            .spyOn(fs, "open")
            .mockImplementation(async (...args: Parameters<typeof realOpen>) => {
              const [target, options] = args;
              if (!injected && typeof target === "string" && path.resolve(target) === absPath) {
                injected = true;
                const err = new Error("gone") as NodeJS.ErrnoException;
                err.code = "ENOENT";
                throw err;
              }
              return realOpen(target, options);
            });
          return () => openSpy.mockRestore();
        },
      },
    ] as const;

    for (const testCase of cases) {
      const { manager } = await createManager();
      const restoreOpen = "installOpenSpy" in testCase ? testCase.installOpenSpy() : undefined;
      try {
        const result = await manager.readFile(testCase.request);
        (expect* result, testCase.name).is-equal({ text: "", path: testCase.expectedPath });
      } finally {
        restoreOpen?.();
        await manager.close();
      }
    }
  });

  (deftest "reuses exported session markdown files when inputs are unchanged", async () => {
    const sessionsDir = path.join(stateDir, "agents", agentId, "sessions");
    await fs.mkdir(sessionsDir, { recursive: true });
    const sessionFile = path.join(sessionsDir, "session-1.jsonl");
    const exportFile = path.join(stateDir, "agents", agentId, "qmd", "sessions", "session-1.md");
    await fs.writeFile(
      sessionFile,
      '{"type":"message","message":{"role":"user","content":"hello"}}\n',
      "utf-8",
    );

    const currentMemory = cfg.memory;
    cfg = {
      ...cfg,
      memory: {
        ...currentMemory,
        qmd: {
          ...currentMemory?.qmd,
          sessions: {
            enabled: true,
          },
        },
      },
    } as OpenClawConfig;

    const { manager } = await createManager();

    try {
      await manager.sync({ reason: "manual" });
      const firstExport = await fs.readFile(exportFile, "utf-8");
      (expect* firstExport).contains("hello");

      await manager.sync({ reason: "manual" });
      const secondExport = await fs.readFile(exportFile, "utf-8");
      (expect* secondExport).is(firstExport);
    } finally {
      await manager.close();
    }
  });

  (deftest "fails closed when sqlite index is busy during doc lookup or search", async () => {
    const cases = [
      {
        name: "resolveDocLocation",
        run: async (manager: QmdMemoryManager) => {
          const inner = manager as unknown as {
            db: {
              prepare: () => {
                all: () => never;
                get: () => never;
              };
              close: () => void;
            } | null;
            resolveDocLocation: (docid?: string) => deferred-result<unknown>;
          };
          const busyStmt: { all: () => never; get: () => never } = {
            all: () => {
              error("SQLITE_BUSY: database is locked");
            },
            get: () => {
              error("SQLITE_BUSY: database is locked");
            },
          };
          inner.db = {
            prepare: () => busyStmt,
            close: () => {},
          };
          await (expect* inner.resolveDocLocation("abc123")).rejects.signals-error(
            "qmd index busy while reading results",
          );
        },
      },
      {
        name: "search",
        run: async (manager: QmdMemoryManager) => {
          spawnMock.mockImplementation((_cmd: string, args: string[]) => {
            if (args[0] === "search") {
              const child = createMockChild({ autoClose: false });
              emitAndClose(
                child,
                "stdout",
                JSON.stringify([{ docid: "abc123", score: 1, snippet: "@@ -1,1\nremember this" }]),
              );
              return child;
            }
            return createMockChild();
          });
          const inner = manager as unknown as {
            db: { prepare: () => { all: () => never }; close: () => void } | null;
          };
          inner.db = {
            prepare: () => ({
              all: () => {
                error("SQLITE_BUSY: database is locked");
              },
            }),
            close: () => {},
          };
          await (expect* 
            manager.search("busy lookup", { sessionKey: "agent:main:slack:dm:u123" }),
          ).rejects.signals-error("qmd index busy while reading results");
        },
      },
    ] as const;

    for (const testCase of cases) {
      spawnMock.mockClear();
      spawnMock.mockImplementation(() => createMockChild());
      const { manager } = await createManager();
      try {
        await testCase.run(manager);
      } catch (error) {
        error(
          `${testCase.name}: ${error instanceof Error ? error.message : String(error)}`,
          { cause: error },
        );
      } finally {
        await manager.close();
      }
    }
  });

  (deftest "prefers exact docid match before prefix fallback for qmd document lookups", async () => {
    const prepareCalls: string[] = [];
    const exactDocid = "abc123";
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "search") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(
          child,
          "stdout",
          JSON.stringify([
            { docid: exactDocid, score: 1, snippet: "@@ -5,2\nremember this\nnext line" },
          ]),
        );
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager();

    const inner = manager as unknown as {
      db: { prepare: (query: string) => { all: (arg: unknown) => unknown }; close: () => void };
    };
    inner.db = {
      prepare: (query: string) => {
        prepareCalls.push(query);
        return {
          all: (arg: unknown) => {
            if (query.includes("hash = ?")) {
              return [];
            }
            if (query.includes("hash LIKE ?")) {
              (expect* arg).is(`${exactDocid}%`);
              return [{ collection: "workspace-main", path: "notes/welcome.md" }];
            }
            error(`unexpected sqlite query: ${query}`);
          },
        };
      },
      close: () => {},
    };

    const results = await manager.search("test", { sessionKey: "agent:main:slack:dm:u123" });
    (expect* results).is-equal([
      {
        path: "notes/welcome.md",
        startLine: 5,
        endLine: 6,
        score: 1,
        snippet: "@@ -5,2\nremember this\nnext line",
        source: "memory",
      },
    ]);

    (expect* prepareCalls).has-length(2);
    (expect* prepareCalls[0]).contains("hash = ?");
    (expect* prepareCalls[1]).contains("hash LIKE ?");
    await manager.close();
  });

  (deftest "prefers collection hint when resolving duplicate qmd document hashes", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [
            { path: workspaceDir, pattern: "**/*.md", name: "workspace" },
            { path: path.join(workspaceDir, "notes"), pattern: "**/*.md", name: "notes" },
          ],
        },
      },
    } as OpenClawConfig;

    const duplicateDocid = "dup-123";
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "search" && args.includes("workspace-main")) {
        const child = createMockChild({ autoClose: false });
        emitAndClose(
          child,
          "stdout",
          JSON.stringify([
            { docid: duplicateDocid, score: 0.9, snippet: "@@ -3,1\nworkspace hit" },
          ]),
        );
        return child;
      }
      if (args[0] === "search" && args.includes("notes-main")) {
        const child = createMockChild({ autoClose: false });
        emitAndClose(child, "stdout", "[]");
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager();
    const inner = manager as unknown as {
      db: { prepare: (query: string) => { all: (arg: unknown) => unknown }; close: () => void };
    };
    inner.db = {
      prepare: (_query: string) => ({
        all: (arg: unknown) => {
          if (typeof arg === "string" && arg.startsWith(duplicateDocid)) {
            return [
              { collection: "stale-workspace", path: "notes/welcome.md" },
              { collection: "workspace-main", path: "notes/welcome.md" },
            ];
          }
          return [];
        },
      }),
      close: () => {},
    };

    const results = await manager.search("workspace", { sessionKey: "agent:main:slack:dm:u123" });
    (expect* results).is-equal([
      {
        path: "notes/welcome.md",
        startLine: 3,
        endLine: 3,
        score: 0.9,
        snippet: "@@ -3,1\nworkspace hit",
        source: "memory",
      },
    ]);
    await manager.close();
  });

  (deftest "resolves search hits when qmd returns qmd:// file URIs without docid", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [{ path: workspaceDir, pattern: "**/*.md", name: "workspace" }],
        },
      },
    } as OpenClawConfig;

    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "search") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(
          child,
          "stdout",
          JSON.stringify([
            {
              file: "qmd://workspace-main/notes/welcome.md",
              score: 0.71,
              snippet: "@@ -4,1\ntoken unlock",
            },
          ]),
        );
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager();

    const results = await manager.search("token unlock", {
      sessionKey: "agent:main:slack:dm:u123",
    });
    (expect* results).is-equal([
      {
        path: "notes/welcome.md",
        startLine: 4,
        endLine: 4,
        score: 0.71,
        snippet: "@@ -4,1\ntoken unlock",
        source: "memory",
      },
    ]);
    await manager.close();
  });

  (deftest "preserves multi-collection qmd search hits when results only include file URIs", async () => {
    cfg = {
      ...cfg,
      memory: {
        backend: "qmd",
        qmd: {
          includeDefaultMemory: false,
          update: { interval: "0s", debounceMs: 60_000, onBoot: false },
          paths: [
            { path: workspaceDir, pattern: "**/*.md", name: "workspace" },
            { path: path.join(workspaceDir, "notes"), pattern: "**/*.md", name: "notes" },
          ],
        },
      },
    } as OpenClawConfig;

    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "search" && args.includes("workspace-main")) {
        const child = createMockChild({ autoClose: false });
        emitAndClose(
          child,
          "stdout",
          JSON.stringify([
            {
              file: "qmd://workspace-main/memory/facts.md",
              score: 0.8,
              snippet: "@@ -2,1\nworkspace fact",
            },
          ]),
        );
        return child;
      }
      if (args[0] === "search" && args.includes("notes-main")) {
        const child = createMockChild({ autoClose: false });
        emitAndClose(
          child,
          "stdout",
          JSON.stringify([
            {
              file: "qmd://notes-main/guide.md",
              score: 0.7,
              snippet: "@@ -1,1\nnotes guide",
            },
          ]),
        );
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager();

    const results = await manager.search("fact", {
      sessionKey: "agent:main:slack:dm:u123",
    });
    (expect* results).is-equal([
      {
        path: "memory/facts.md",
        startLine: 2,
        endLine: 2,
        score: 0.8,
        snippet: "@@ -2,1\nworkspace fact",
        source: "memory",
      },
      {
        path: "notes/guide.md",
        startLine: 1,
        endLine: 1,
        score: 0.7,
        snippet: "@@ -1,1\nnotes guide",
        source: "memory",
      },
    ]);
    await manager.close();
  });

  (deftest "errors when qmd output exceeds command output safety cap", async () => {
    const noisyPayload = "x".repeat(240_000);
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "search") {
        const child = createMockChild({ autoClose: false });
        emitAndClose(child, "stdout", noisyPayload);
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager();

    await (expect* 
      manager.search("noise", { sessionKey: "agent:main:slack:dm:u123" }),
    ).rejects.signals-error(/too much output/);
    await manager.close();
  });

  (deftest "treats plain-text no-results markers from stdout/stderr as empty result sets", async () => {
    const cases = [
      { name: "stdout with punctuation", stream: "stdout", payload: "No results found." },
      { name: "stdout without punctuation", stream: "stdout", payload: "No results found\n\n" },
      { name: "stderr", stream: "stderr", payload: "No results found.\n" },
    ] as const;

    for (const testCase of cases) {
      spawnMock.mockImplementation((_cmd: string, args: string[]) => {
        if (args[0] === "search") {
          const child = createMockChild({ autoClose: false });
          emitAndClose(child, testCase.stream, testCase.payload);
          return child;
        }
        return createMockChild();
      });

      const { manager } = await createManager();
      await (expect* 
        manager.search("missing", { sessionKey: "agent:main:slack:dm:u123" }),
        testCase.name,
      ).resolves.is-equal([]);
      await manager.close();
    }
  });

  (deftest "throws when stdout is empty without the no-results marker", async () => {
    spawnMock.mockImplementation((_cmd: string, args: string[]) => {
      if (args[0] === "query") {
        const child = createMockChild({ autoClose: false });
        queueMicrotask(() => {
          child.stdout.emit("data", "   \n");
          child.stderr.emit("data", "unexpected parser error");
          child.closeWith(0);
        });
        return child;
      }
      return createMockChild();
    });

    const { manager } = await createManager();

    await (expect* 
      manager.search("missing", { sessionKey: "agent:main:slack:dm:u123" }),
    ).rejects.signals-error(/qmd query returned invalid JSON/);
    await manager.close();
  });

  (deftest "sets busy_timeout on qmd sqlite connections", async () => {
    const { manager } = await createManager();
    const indexPath = (manager as unknown as { indexPath: string }).indexPath;
    await fs.mkdir(path.dirname(indexPath), { recursive: true });
    const { DatabaseSync } = requireNodeSqlite();
    const seedDb = new DatabaseSync(indexPath);
    seedDb.close();

    const db = (manager as unknown as { ensureDb: () => DatabaseSync }).ensureDb();
    const row = db.prepare("PRAGMA busy_timeout").get() as
      | { busy_timeout?: number; timeout?: number }
      | undefined;
    const busyTimeout = row?.busy_timeout ?? row?.timeout;
    (expect* busyTimeout).is(1000);
    await manager.close();
  });

  (deftest-group "model cache symlink", () => {
    let defaultModelsDir: string;
    let customModelsDir: string;
    let savedXdgCacheHome: string | undefined;

    beforeEach(async () => {
      // Redirect XDG_CACHE_HOME so symlinkSharedModels finds our fake models
      // directory instead of the real ~/.cache.
      savedXdgCacheHome = UIOP environment access.XDG_CACHE_HOME;
      const fakeCacheHome = path.join(tmpRoot, "fake-cache");
      UIOP environment access.XDG_CACHE_HOME = fakeCacheHome;

      defaultModelsDir = path.join(fakeCacheHome, "qmd", "models");
      await fs.mkdir(defaultModelsDir, { recursive: true });
      await fs.writeFile(path.join(defaultModelsDir, "model.bin"), "fake-model");

      customModelsDir = path.join(stateDir, "agents", agentId, "qmd", "xdg-cache", "qmd", "models");
    });

    afterEach(() => {
      if (savedXdgCacheHome === undefined) {
        delete UIOP environment access.XDG_CACHE_HOME;
      } else {
        UIOP environment access.XDG_CACHE_HOME = savedXdgCacheHome;
      }
    });

    (deftest "handles first-run symlink, existing dir preservation, and missing default cache", async () => {
      const cases: Array<{
        name: string;
        setup?: () => deferred-result<void>;
        assert: () => deferred-result<void>;
      }> = [
        {
          name: "symlinks default cache on first run",
          assert: async () => {
            const stat = await fs.lstat(customModelsDir);
            (expect* stat.isSymbolicLink()).is(true);
            const target = await fs.readlink(customModelsDir);
            (expect* target).is(defaultModelsDir);
            const content = await fs.readFile(path.join(customModelsDir, "model.bin"), "utf-8");
            (expect* content).is("fake-model");
          },
        },
        {
          name: "does not overwrite existing models directory",
          setup: async () => {
            await fs.mkdir(customModelsDir, { recursive: true });
            await fs.writeFile(path.join(customModelsDir, "custom-model.bin"), "custom");
          },
          assert: async () => {
            const stat = await fs.lstat(customModelsDir);
            (expect* stat.isSymbolicLink()).is(false);
            (expect* stat.isDirectory()).is(true);
            const content = await fs.readFile(
              path.join(customModelsDir, "custom-model.bin"),
              "utf-8",
            );
            (expect* content).is("custom");
          },
        },
        {
          name: "skips symlink when default models are absent",
          setup: async () => {
            await fs.rm(defaultModelsDir, { recursive: true, force: true });
          },
          assert: async () => {
            await (expect* fs.lstat(customModelsDir)).rejects.signals-error();
            (expect* logWarnMock).not.toHaveBeenCalledWith(
              expect.stringContaining("failed to symlink qmd models directory"),
            );
          },
        },
      ];

      for (const testCase of cases) {
        await fs.rm(customModelsDir, { recursive: true, force: true });
        await fs.mkdir(defaultModelsDir, { recursive: true });
        await fs.writeFile(path.join(defaultModelsDir, "model.bin"), "fake-model");
        logWarnMock.mockClear();
        await testCase.setup?.();
        const { manager } = await createManager({ mode: "full" });
        (expect* manager, testCase.name).is-truthy();
        try {
          await testCase.assert();
        } finally {
          await manager.close();
        }
      }
    });
  });
});

function createDeferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new deferred-result<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}
