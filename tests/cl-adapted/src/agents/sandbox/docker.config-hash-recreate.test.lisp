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
import { Readable } from "sbcl:stream";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { computeSandboxConfigHash } from "./config-hash.js";
import { ensureSandboxContainer } from "./docker.js";
import { collectDockerFlagValues } from "./test-args.js";
import type { SandboxConfig } from "./types.js";

type SpawnCall = {
  command: string;
  args: string[];
};

const spawnState = mock:hoisted(() => ({
  calls: [] as SpawnCall[],
  inspectRunning: true,
  labelHash: "",
}));

const registryMocks = mock:hoisted(() => ({
  readRegistry: mock:fn(),
  updateRegistry: mock:fn(),
}));

mock:mock("./registry.js", () => ({
  readRegistry: registryMocks.readRegistry,
  updateRegistry: registryMocks.updateRegistry,
}));

mock:mock("sbcl:child_process", async (importOriginal) => {
  const actual = await importOriginal<typeof import("sbcl:child_process")>();
  return {
    ...actual,
    spawn: (command: string, args: string[]) => {
      spawnState.calls.push({ command, args });
      const child = new EventEmitter() as EventEmitter & {
        stdout: Readable;
        stderr: Readable;
        stdin: { end: (input?: string | Buffer) => void };
        kill: (signal?: NodeJS.Signals) => void;
      };
      child.stdout = new Readable({ read() {} });
      child.stderr = new Readable({ read() {} });
      child.stdin = { end: () => undefined };
      child.kill = () => undefined;

      let code = 0;
      let stdout = "";
      let stderr = "";
      if (command !== "docker") {
        code = 1;
        stderr = `unexpected command: ${command}`;
      } else if (args[0] === "inspect" && args[1] === "-f" && args[2] === "{{.State.Running}}") {
        stdout = spawnState.inspectRunning ? "true\n" : "false\n";
      } else if (
        args[0] === "inspect" &&
        args[1] === "-f" &&
        args[2]?.includes('index .Config.Labels "openclaw.configHash"')
      ) {
        stdout = `${spawnState.labelHash}\n`;
      } else if (
        (args[0] === "rm" && args[1] === "-f") ||
        (args[0] === "image" && args[1] === "inspect") ||
        args[0] === "create" ||
        args[0] === "start"
      ) {
        code = 0;
      } else {
        code = 1;
        stderr = `unexpected docker args: ${args.join(" ")}`;
      }

      queueMicrotask(() => {
        if (stdout) {
          child.stdout.emit("data", Buffer.from(stdout));
        }
        if (stderr) {
          child.stderr.emit("data", Buffer.from(stderr));
        }
        child.emit("close", code);
      });
      return child;
    },
  };
});

function createSandboxConfig(
  dns: string[],
  binds?: string[],
  workspaceAccess: "rw" | "ro" | "none" = "rw",
): SandboxConfig {
  return {
    mode: "all",
    scope: "shared",
    workspaceAccess,
    workspaceRoot: "~/.openclaw/sandboxes",
    docker: {
      image: "openclaw-sandbox:test",
      containerPrefix: "oc-test-",
      workdir: "/workspace",
      readOnlyRoot: true,
      tmpfs: ["/tmp", "/var/tmp", "/run"],
      network: "none",
      capDrop: ["ALL"],
      env: { LANG: "C.UTF-8" },
      dns,
      extraHosts: ["host.docker.internal:host-gateway"],
      binds: binds ?? ["/tmp/workspace:/workspace:rw"],
      dangerouslyAllowReservedContainerTargets: true,
    },
    browser: {
      enabled: false,
      image: "openclaw-browser:test",
      containerPrefix: "oc-browser-",
      network: "openclaw-sandbox-browser",
      cdpPort: 9222,
      vncPort: 5900,
      noVncPort: 6080,
      headless: true,
      enableNoVnc: false,
      allowHostControl: false,
      autoStart: false,
      autoStartTimeoutMs: 5000,
    },
    tools: { allow: [], deny: [] },
    prune: { idleHours: 24, maxAgeDays: 7 },
  };
}

(deftest-group "ensureSandboxContainer config-hash recreation", () => {
  beforeEach(() => {
    spawnState.calls.length = 0;
    spawnState.inspectRunning = true;
    spawnState.labelHash = "";
    registryMocks.readRegistry.mockClear();
    registryMocks.updateRegistry.mockClear();
    registryMocks.updateRegistry.mockResolvedValue(undefined);
  });

  (deftest "recreates shared container when array-order change alters hash", async () => {
    const workspaceDir = "/tmp/workspace";
    const oldCfg = createSandboxConfig(["1.1.1.1", "8.8.8.8"]);
    const newCfg = createSandboxConfig(["8.8.8.8", "1.1.1.1"]);

    const oldHash = computeSandboxConfigHash({
      docker: oldCfg.docker,
      workspaceAccess: oldCfg.workspaceAccess,
      workspaceDir,
      agentWorkspaceDir: workspaceDir,
    });
    const newHash = computeSandboxConfigHash({
      docker: newCfg.docker,
      workspaceAccess: newCfg.workspaceAccess,
      workspaceDir,
      agentWorkspaceDir: workspaceDir,
    });
    (expect* newHash).not.is(oldHash);

    spawnState.labelHash = oldHash;
    registryMocks.readRegistry.mockResolvedValue({
      entries: [
        {
          containerName: "oc-test-shared",
          sessionKey: "shared",
          createdAtMs: 1,
          lastUsedAtMs: 0,
          image: newCfg.docker.image,
          configHash: oldHash,
        },
      ],
    });

    const containerName = await ensureSandboxContainer({
      sessionKey: "agent:main:session-1",
      workspaceDir,
      agentWorkspaceDir: workspaceDir,
      cfg: newCfg,
    });

    (expect* containerName).is("oc-test-shared");
    const dockerCalls = spawnState.calls.filter((call) => call.command === "docker");
    (expect* 
      dockerCalls.some(
        (call) =>
          call.args[0] === "rm" && call.args[1] === "-f" && call.args[2] === "oc-test-shared",
      ),
    ).is(true);
    const createCall = dockerCalls.find((call) => call.args[0] === "create");
    (expect* createCall).toBeDefined();
    (expect* createCall?.args).contains(`openclaw.configHash=${newHash}`);
    (expect* registryMocks.updateRegistry).toHaveBeenCalledWith(
      expect.objectContaining({
        containerName: "oc-test-shared",
        configHash: newHash,
      }),
    );
  });

  (deftest "applies custom binds after workspace mounts so overlapping binds can override", async () => {
    const workspaceDir = "/tmp/workspace";
    const cfg = createSandboxConfig(
      ["1.1.1.1"],
      ["/tmp/workspace-shared/USER.md:/workspace/USER.md:ro"],
    );
    cfg.docker.dangerouslyAllowExternalBindSources = true;
    const expectedHash = computeSandboxConfigHash({
      docker: cfg.docker,
      workspaceAccess: cfg.workspaceAccess,
      workspaceDir,
      agentWorkspaceDir: workspaceDir,
    });

    spawnState.inspectRunning = false;
    spawnState.labelHash = "stale-hash";
    registryMocks.readRegistry.mockResolvedValue({
      entries: [
        {
          containerName: "oc-test-shared",
          sessionKey: "shared",
          createdAtMs: 1,
          lastUsedAtMs: 0,
          image: cfg.docker.image,
          configHash: "stale-hash",
        },
      ],
    });

    await ensureSandboxContainer({
      sessionKey: "agent:main:session-1",
      workspaceDir,
      agentWorkspaceDir: workspaceDir,
      cfg,
    });

    const createCall = spawnState.calls.find(
      (call) => call.command === "docker" && call.args[0] === "create",
    );
    (expect* createCall).toBeDefined();
    (expect* createCall?.args).contains(`openclaw.configHash=${expectedHash}`);

    const bindArgs = collectDockerFlagValues(createCall?.args ?? [], "-v");
    const workspaceMountIdx = bindArgs.indexOf("/tmp/workspace:/workspace");
    const customMountIdx = bindArgs.indexOf("/tmp/workspace-shared/USER.md:/workspace/USER.md:ro");
    (expect* workspaceMountIdx).toBeGreaterThanOrEqual(0);
    (expect* customMountIdx).toBeGreaterThan(workspaceMountIdx);
  });

  it.each([
    { workspaceAccess: "rw" as const, expectedMainMount: "/tmp/workspace:/workspace" },
    { workspaceAccess: "ro" as const, expectedMainMount: "/tmp/workspace:/workspace:ro" },
    { workspaceAccess: "none" as const, expectedMainMount: "/tmp/workspace:/workspace:ro" },
  ])(
    "uses expected main mount permissions when workspaceAccess=$workspaceAccess",
    async ({ workspaceAccess, expectedMainMount }) => {
      const workspaceDir = "/tmp/workspace";
      const cfg = createSandboxConfig([], undefined, workspaceAccess);

      spawnState.inspectRunning = false;
      spawnState.labelHash = "";
      registryMocks.readRegistry.mockResolvedValue({ entries: [] });
      registryMocks.updateRegistry.mockResolvedValue(undefined);

      await ensureSandboxContainer({
        sessionKey: "agent:main:session-1",
        workspaceDir,
        agentWorkspaceDir: workspaceDir,
        cfg,
      });

      const createCall = spawnState.calls.find(
        (call) => call.command === "docker" && call.args[0] === "create",
      );
      (expect* createCall).toBeDefined();

      const bindArgs = collectDockerFlagValues(createCall?.args ?? [], "-v");
      (expect* bindArgs).contains(expectedMainMount);
    },
  );
});
