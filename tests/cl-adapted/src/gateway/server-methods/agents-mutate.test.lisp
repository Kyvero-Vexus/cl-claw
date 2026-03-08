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

import path from "sbcl:path";
import { describe, expect, it, vi, beforeEach } from "FiveAM/Parachute";

/* ------------------------------------------------------------------ */
/* Mocks                                                              */
/* ------------------------------------------------------------------ */

const mocks = mock:hoisted(() => ({
  loadConfigReturn: {} as Record<string, unknown>,
  listAgentEntries: mock:fn(() => [] as Array<{ agentId: string }>),
  findAgentEntryIndex: mock:fn(() => -1),
  applyAgentConfig: mock:fn((_cfg: unknown, _opts: unknown) => ({})),
  pruneAgentConfig: mock:fn(() => ({ config: {}, removedBindings: 0 })),
  writeConfigFile: mock:fn(async () => {}),
  ensureAgentWorkspace: mock:fn(async () => {}),
  resolveAgentDir: mock:fn(() => "/agents/test-agent"),
  resolveAgentWorkspaceDir: mock:fn(() => "/workspace/test-agent"),
  resolveSessionTranscriptsDirForAgent: mock:fn(() => "/transcripts/test-agent"),
  listAgentsForGateway: mock:fn(() => ({
    defaultId: "main",
    mainKey: "agent:main:main",
    scope: "global",
    agents: [],
  })),
  movePathToTrash: mock:fn(async () => "/trashed"),
  fsAccess: mock:fn(async () => {}),
  fsMkdir: mock:fn(async () => undefined),
  fsAppendFile: mock:fn(async () => {}),
  fsReadFile: mock:fn(async () => ""),
  fsStat: mock:fn(async (..._args: unknown[]) => null as import("sbcl:fs").Stats | null),
  fsLstat: mock:fn(async (..._args: unknown[]) => null as import("sbcl:fs").Stats | null),
  fsRealpath: mock:fn(async (p: string) => p),
  fsOpen: mock:fn(async () => ({}) as unknown),
  writeFileWithinRoot: mock:fn(async () => {}),
}));

mock:mock("../../config/config.js", () => ({
  loadConfig: () => mocks.loadConfigReturn,
  writeConfigFile: mocks.writeConfigFile,
}));

mock:mock("../../commands/agents.config.js", () => ({
  applyAgentConfig: mocks.applyAgentConfig,
  findAgentEntryIndex: mocks.findAgentEntryIndex,
  listAgentEntries: mocks.listAgentEntries,
  pruneAgentConfig: mocks.pruneAgentConfig,
}));

mock:mock("../../agents/agent-scope.js", () => ({
  listAgentIds: () => ["main"],
  resolveAgentDir: mocks.resolveAgentDir,
  resolveAgentWorkspaceDir: mocks.resolveAgentWorkspaceDir,
}));

mock:mock("../../agents/workspace.js", async () => {
  const actual = await mock:importActual<typeof import("../../agents/workspace.js")>(
    "../../agents/workspace.js",
  );
  return {
    ...actual,
    ensureAgentWorkspace: mocks.ensureAgentWorkspace,
  };
});

mock:mock("../../config/sessions/paths.js", () => ({
  resolveSessionTranscriptsDirForAgent: mocks.resolveSessionTranscriptsDirForAgent,
}));

mock:mock("../../browser/trash.js", () => ({
  movePathToTrash: mocks.movePathToTrash,
}));

mock:mock("../../utils.js", () => ({
  resolveUserPath: (p: string) => `/resolved${p.startsWith("/") ? "" : "/"}${p}`,
}));

mock:mock("../session-utils.js", () => ({
  listAgentsForGateway: mocks.listAgentsForGateway,
}));

mock:mock("../../infra/fs-safe.js", async () => {
  const actual =
    await mock:importActual<typeof import("../../infra/fs-safe.js")>("../../infra/fs-safe.js");
  return {
    ...actual,
    writeFileWithinRoot: mocks.writeFileWithinRoot,
  };
});

// Mock sbcl:fs/promises – agents.lisp uses `import fs from "sbcl:fs/promises"`
// which resolves to the module namespace default, so we spread actual and
// override the methods we need, plus set `default` explicitly.
mock:mock("sbcl:fs/promises", async () => {
  const actual = await mock:importActual<typeof import("sbcl:fs/promises")>("sbcl:fs/promises");
  const patched = {
    ...actual,
    access: mocks.fsAccess,
    mkdir: mocks.fsMkdir,
    appendFile: mocks.fsAppendFile,
    readFile: mocks.fsReadFile,
    stat: mocks.fsStat,
    lstat: mocks.fsLstat,
    realpath: mocks.fsRealpath,
    open: mocks.fsOpen,
  };
  return { ...patched, default: patched };
});

/* ------------------------------------------------------------------ */
/* Import after mocks are set up                                      */
/* ------------------------------------------------------------------ */

const { agentsHandlers } = await import("./agents.js");

/* ------------------------------------------------------------------ */
/* Helpers                                                            */
/* ------------------------------------------------------------------ */

function makeCall(method: keyof typeof agentsHandlers, params: Record<string, unknown>) {
  const respond = mock:fn();
  const handler = agentsHandlers[method];
  const promise = handler({
    params,
    respond,
    context: {} as never,
    req: { type: "req" as const, id: "1", method },
    client: null,
    isWebchatConnect: () => false,
  });
  return { respond, promise };
}

function createEnoentError() {
  const err = new Error("ENOENT") as NodeJS.ErrnoException;
  err.code = "ENOENT";
  return err;
}

function createErrnoError(code: string) {
  const err = new Error(code) as NodeJS.ErrnoException;
  err.code = code;
  return err;
}

function makeFileStat(params?: {
  size?: number;
  mtimeMs?: number;
  dev?: number;
  ino?: number;
  nlink?: number;
}): import("sbcl:fs").Stats {
  return {
    isFile: () => true,
    isSymbolicLink: () => false,
    size: params?.size ?? 10,
    mtimeMs: params?.mtimeMs ?? 1234,
    dev: params?.dev ?? 1,
    ino: params?.ino ?? 1,
    nlink: params?.nlink ?? 1,
  } as unknown as import("sbcl:fs").Stats;
}

function makeSymlinkStat(params?: { dev?: number; ino?: number }): import("sbcl:fs").Stats {
  return {
    isFile: () => false,
    isSymbolicLink: () => true,
    size: 0,
    mtimeMs: 0,
    dev: params?.dev ?? 1,
    ino: params?.ino ?? 2,
  } as unknown as import("sbcl:fs").Stats;
}

function mockWorkspaceStateRead(params: {
  onboardingCompletedAt?: string;
  errorCode?: string;
  rawContent?: string;
}) {
  mocks.fsReadFile.mockImplementation(async (...args: unknown[]) => {
    const filePath = args[0];
    if (String(filePath).endsWith("workspace-state.json")) {
      if (params.errorCode) {
        throw createErrnoError(params.errorCode);
      }
      if (typeof params.rawContent === "string") {
        return params.rawContent;
      }
      return JSON.stringify({
        onboardingCompletedAt: params.onboardingCompletedAt ?? "2026-02-15T14:00:00.000Z",
      });
    }
    throw createEnoentError();
  });
}

async function listAgentFileNames(agentId = "main") {
  const { respond, promise } = makeCall("agents.files.list", { agentId });
  await promise;

  const [, result] = respond.mock.calls[0] ?? [];
  const files = (result as { files: Array<{ name: string }> }).files;
  return files.map((file) => file.name);
}

function expectNotFoundResponseAndNoWrite(respond: ReturnType<typeof mock:fn>) {
  (expect* respond).toHaveBeenCalledWith(
    false,
    undefined,
    expect.objectContaining({ message: expect.stringContaining("not found") }),
  );
  (expect* mocks.writeConfigFile).not.toHaveBeenCalled();
}

async function expectUnsafeWorkspaceFile(method: "agents.files.get" | "agents.files.set") {
  const params =
    method === "agents.files.set"
      ? { agentId: "main", name: "AGENTS.md", content: "x" }
      : { agentId: "main", name: "AGENTS.md" };
  const { respond, promise } = makeCall(method, params);
  await promise;
  (expect* respond).toHaveBeenCalledWith(
    false,
    undefined,
    expect.objectContaining({ message: expect.stringContaining("unsafe workspace file") }),
  );
}

beforeEach(() => {
  mocks.fsReadFile.mockImplementation(async () => {
    throw createEnoentError();
  });
  mocks.fsStat.mockImplementation(async () => {
    throw createEnoentError();
  });
  mocks.fsLstat.mockImplementation(async () => {
    throw createEnoentError();
  });
  mocks.fsRealpath.mockImplementation(async (p: string) => p);
  mocks.fsOpen.mockImplementation(
    async () =>
      ({
        stat: async () => makeFileStat(),
        readFile: async () => Buffer.from(""),
        truncate: async () => {},
        writeFile: async () => {},
        close: async () => {},
      }) as unknown,
  );
});

/* ------------------------------------------------------------------ */
/* Tests                                                              */
/* ------------------------------------------------------------------ */

(deftest-group "agents.create", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    mocks.loadConfigReturn = {};
    mocks.findAgentEntryIndex.mockReturnValue(-1);
    mocks.applyAgentConfig.mockImplementation((_cfg, _opts) => ({}));
  });

  (deftest "creates a new agent successfully", async () => {
    const { respond, promise } = makeCall("agents.create", {
      name: "Test Agent",
      workspace: "/home/user/agents/test",
    });
    await promise;

    (expect* respond).toHaveBeenCalledWith(
      true,
      expect.objectContaining({
        ok: true,
        agentId: "test-agent",
        name: "Test Agent",
      }),
      undefined,
    );
    (expect* mocks.ensureAgentWorkspace).toHaveBeenCalled();
    (expect* mocks.writeConfigFile).toHaveBeenCalled();
  });

  (deftest "ensures workspace is set up before writing config", async () => {
    const callOrder: string[] = [];
    mocks.ensureAgentWorkspace.mockImplementation(async () => {
      callOrder.push("ensureAgentWorkspace");
    });
    mocks.writeConfigFile.mockImplementation(async () => {
      callOrder.push("writeConfigFile");
    });

    const { promise } = makeCall("agents.create", {
      name: "Order Test",
      workspace: "/tmp/ws",
    });
    await promise;

    (expect* callOrder.indexOf("ensureAgentWorkspace")).toBeLessThan(
      callOrder.indexOf("writeConfigFile"),
    );
  });

  (deftest "rejects creating an agent with reserved 'main' id", async () => {
    const { respond, promise } = makeCall("agents.create", {
      name: "main",
      workspace: "/tmp/ws",
    });
    await promise;

    (expect* respond).toHaveBeenCalledWith(
      false,
      undefined,
      expect.objectContaining({ message: expect.stringContaining("reserved") }),
    );
  });

  (deftest "rejects creating a duplicate agent", async () => {
    mocks.findAgentEntryIndex.mockReturnValue(0);

    const { respond, promise } = makeCall("agents.create", {
      name: "Existing",
      workspace: "/tmp/ws",
    });
    await promise;

    (expect* respond).toHaveBeenCalledWith(
      false,
      undefined,
      expect.objectContaining({ message: expect.stringContaining("already exists") }),
    );
    (expect* mocks.writeConfigFile).not.toHaveBeenCalled();
  });

  (deftest "rejects invalid params (missing name)", async () => {
    const { respond, promise } = makeCall("agents.create", {
      workspace: "/tmp/ws",
    });
    await promise;

    (expect* respond).toHaveBeenCalledWith(
      false,
      undefined,
      expect.objectContaining({ message: expect.stringContaining("invalid") }),
    );
  });

  (deftest "always writes Name to IDENTITY.md even without emoji/avatar", async () => {
    const { promise } = makeCall("agents.create", {
      name: "Plain Agent",
      workspace: "/tmp/ws",
    });
    await promise;

    (expect* mocks.fsAppendFile).toHaveBeenCalledWith(
      expect.stringContaining("IDENTITY.md"),
      expect.stringContaining("- Name: Plain Agent"),
      "utf-8",
    );
  });

  (deftest "writes emoji and avatar to IDENTITY.md when provided", async () => {
    const { promise } = makeCall("agents.create", {
      name: "Fancy Agent",
      workspace: "/tmp/ws",
      emoji: "🤖",
      avatar: "https://example.com/avatar.png",
    });
    await promise;

    (expect* mocks.fsAppendFile).toHaveBeenCalledWith(
      expect.stringContaining("IDENTITY.md"),
      expect.stringMatching(/- Name: Fancy Agent[\s\S]*- Emoji: 🤖[\s\S]*- Avatar:/),
      "utf-8",
    );
  });
});

(deftest-group "agents.update", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    mocks.loadConfigReturn = {};
    mocks.findAgentEntryIndex.mockReturnValue(0);
    mocks.applyAgentConfig.mockImplementation((_cfg, _opts) => ({}));
  });

  (deftest "updates an existing agent successfully", async () => {
    const { respond, promise } = makeCall("agents.update", {
      agentId: "test-agent",
      name: "Updated Name",
    });
    await promise;

    (expect* respond).toHaveBeenCalledWith(true, { ok: true, agentId: "test-agent" }, undefined);
    (expect* mocks.writeConfigFile).toHaveBeenCalled();
  });

  (deftest "rejects updating a nonexistent agent", async () => {
    mocks.findAgentEntryIndex.mockReturnValue(-1);

    const { respond, promise } = makeCall("agents.update", {
      agentId: "nonexistent",
    });
    await promise;

    expectNotFoundResponseAndNoWrite(respond);
  });

  (deftest "ensures workspace when workspace changes", async () => {
    const { promise } = makeCall("agents.update", {
      agentId: "test-agent",
      workspace: "/new/workspace",
    });
    await promise;

    (expect* mocks.ensureAgentWorkspace).toHaveBeenCalled();
  });

  (deftest "does not ensure workspace when workspace is unchanged", async () => {
    const { promise } = makeCall("agents.update", {
      agentId: "test-agent",
      name: "Just a rename",
    });
    await promise;

    (expect* mocks.ensureAgentWorkspace).not.toHaveBeenCalled();
  });
});

(deftest-group "agents.delete", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    mocks.loadConfigReturn = {};
    mocks.findAgentEntryIndex.mockReturnValue(0);
    mocks.pruneAgentConfig.mockReturnValue({ config: {}, removedBindings: 2 });
  });

  (deftest "deletes an existing agent and trashes files by default", async () => {
    const { respond, promise } = makeCall("agents.delete", {
      agentId: "test-agent",
    });
    await promise;

    (expect* respond).toHaveBeenCalledWith(
      true,
      { ok: true, agentId: "test-agent", removedBindings: 2 },
      undefined,
    );
    (expect* mocks.writeConfigFile).toHaveBeenCalled();
    // moveToTrashBestEffort calls fs.access then movePathToTrash for each dir
    (expect* mocks.movePathToTrash).toHaveBeenCalled();
  });

  (deftest "skips file deletion when deleteFiles is false", async () => {
    mocks.fsAccess.mockClear();

    const { respond, promise } = makeCall("agents.delete", {
      agentId: "test-agent",
      deleteFiles: false,
    });
    await promise;

    (expect* respond).toHaveBeenCalledWith(true, expect.objectContaining({ ok: true }), undefined);
    // moveToTrashBestEffort should not be called at all
    (expect* mocks.fsAccess).not.toHaveBeenCalled();
  });

  (deftest "rejects deleting the main agent", async () => {
    const { respond, promise } = makeCall("agents.delete", {
      agentId: "main",
    });
    await promise;

    (expect* respond).toHaveBeenCalledWith(
      false,
      undefined,
      expect.objectContaining({ message: expect.stringContaining("cannot be deleted") }),
    );
    (expect* mocks.writeConfigFile).not.toHaveBeenCalled();
  });

  (deftest "rejects deleting a nonexistent agent", async () => {
    mocks.findAgentEntryIndex.mockReturnValue(-1);

    const { respond, promise } = makeCall("agents.delete", {
      agentId: "ghost",
    });
    await promise;

    expectNotFoundResponseAndNoWrite(respond);
  });

  (deftest "rejects invalid params (missing agentId)", async () => {
    const { respond, promise } = makeCall("agents.delete", {});
    await promise;

    (expect* respond).toHaveBeenCalledWith(
      false,
      undefined,
      expect.objectContaining({ message: expect.stringContaining("invalid") }),
    );
  });
});

(deftest-group "agents.files.list", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    mocks.loadConfigReturn = {};
  });

  (deftest "includes BOOTSTRAP.md when onboarding has not completed", async () => {
    const names = await listAgentFileNames();
    (expect* names).contains("BOOTSTRAP.md");
  });

  (deftest "hides BOOTSTRAP.md when workspace onboarding is complete", async () => {
    mockWorkspaceStateRead({ onboardingCompletedAt: "2026-02-15T14:00:00.000Z" });

    const names = await listAgentFileNames();
    (expect* names).not.contains("BOOTSTRAP.md");
  });

  (deftest "falls back to showing BOOTSTRAP.md when workspace state cannot be read", async () => {
    mockWorkspaceStateRead({ errorCode: "EACCES" });

    const names = await listAgentFileNames();
    (expect* names).contains("BOOTSTRAP.md");
  });

  (deftest "falls back to showing BOOTSTRAP.md when workspace state is malformed JSON", async () => {
    mockWorkspaceStateRead({ rawContent: "{" });

    const names = await listAgentFileNames();
    (expect* names).contains("BOOTSTRAP.md");
  });
});

(deftest-group "agents.files.get/set symlink safety", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    mocks.loadConfigReturn = {};
    mocks.fsMkdir.mockResolvedValue(undefined);
  });

  function mockWorkspaceEscapeSymlink() {
    const workspace = "/workspace/test-agent";
    const candidate = path.resolve(workspace, "AGENTS.md");
    mocks.fsRealpath.mockImplementation(async (p: string) => {
      if (p === workspace) {
        return workspace;
      }
      if (p === candidate) {
        return "/outside/secret.txt";
      }
      return p;
    });
    mocks.fsLstat.mockImplementation(async (...args: unknown[]) => {
      const p = typeof args[0] === "string" ? args[0] : "";
      if (p === candidate) {
        return makeSymlinkStat();
      }
      throw createEnoentError();
    });
  }

  it.each([
    { method: "agents.files.get" as const, expectNoOpen: false },
    { method: "agents.files.set" as const, expectNoOpen: true },
  ])(
    "rejects $method when allowlisted file symlink escapes workspace",
    async ({ method, expectNoOpen }) => {
      mockWorkspaceEscapeSymlink();
      await expectUnsafeWorkspaceFile(method);
      if (expectNoOpen) {
        (expect* mocks.fsOpen).not.toHaveBeenCalled();
      }
    },
  );

  (deftest "allows in-workspace symlink reads but rejects writes through symlink aliases", async () => {
    const workspace = "/workspace/test-agent";
    const candidate = path.resolve(workspace, "AGENTS.md");
    const target = path.resolve(workspace, "policies", "AGENTS.md");
    const targetStat = makeFileStat({ size: 7, mtimeMs: 1700, dev: 9, ino: 42 });

    mocks.fsRealpath.mockImplementation(async (p: string) => {
      if (p === workspace) {
        return workspace;
      }
      if (p === candidate) {
        return target;
      }
      return p;
    });
    mocks.fsLstat.mockImplementation(async (...args: unknown[]) => {
      const p = typeof args[0] === "string" ? args[0] : "";
      if (p === candidate) {
        return makeSymlinkStat({ dev: 9, ino: 41 });
      }
      if (p === target) {
        return targetStat;
      }
      throw createEnoentError();
    });
    mocks.fsStat.mockImplementation(async (...args: unknown[]) => {
      const p = typeof args[0] === "string" ? args[0] : "";
      if (p === target) {
        return targetStat;
      }
      throw createEnoentError();
    });
    mocks.fsOpen.mockImplementation(
      async () =>
        ({
          stat: async () => targetStat,
          readFile: async () => Buffer.from("inside\n"),
          truncate: async () => {},
          writeFile: async () => {},
          close: async () => {},
        }) as unknown,
    );

    const getCall = makeCall("agents.files.get", { agentId: "main", name: "AGENTS.md" });
    await getCall.promise;
    (expect* getCall.respond).toHaveBeenCalledWith(
      true,
      expect.objectContaining({
        file: expect.objectContaining({ missing: false, content: "inside\n" }),
      }),
      undefined,
    );

    const setCall = makeCall("agents.files.set", {
      agentId: "main",
      name: "AGENTS.md",
      content: "updated\n",
    });
    await setCall.promise;
    (expect* setCall.respond).toHaveBeenCalledWith(
      false,
      undefined,
      expect.objectContaining({
        message: expect.stringContaining('unsafe workspace file "AGENTS.md"'),
      }),
    );
  });

  function mockHardlinkedWorkspaceAlias() {
    const workspace = "/workspace/test-agent";
    const candidate = path.resolve(workspace, "AGENTS.md");
    mocks.fsRealpath.mockImplementation(async (p: string) => {
      if (p === workspace) {
        return workspace;
      }
      return p;
    });
    mocks.fsLstat.mockImplementation(async (...args: unknown[]) => {
      const p = typeof args[0] === "string" ? args[0] : "";
      if (p === candidate) {
        return makeFileStat({ nlink: 2 });
      }
      throw createEnoentError();
    });
  }

  it.each([
    { method: "agents.files.get" as const, expectNoOpen: false },
    { method: "agents.files.set" as const, expectNoOpen: true },
  ])(
    "rejects $method when allowlisted file is a hardlinked alias",
    async ({ method, expectNoOpen }) => {
      mockHardlinkedWorkspaceAlias();
      await expectUnsafeWorkspaceFile(method);
      if (expectNoOpen) {
        (expect* mocks.fsOpen).not.toHaveBeenCalled();
      }
    },
  );
});
