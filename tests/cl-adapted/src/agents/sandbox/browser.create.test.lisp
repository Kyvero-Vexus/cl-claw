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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { BROWSER_BRIDGES } from "./browser-bridges.js";
import { ensureSandboxBrowser } from "./browser.js";
import { resetNoVncObserverTokensForTests } from "./novnc-auth.js";
import { collectDockerFlagValues, findDockerArgsCall } from "./test-args.js";
import type { SandboxConfig } from "./types.js";

const dockerMocks = mock:hoisted(() => ({
  dockerContainerState: mock:fn(),
  execDocker: mock:fn(),
  readDockerContainerEnvVar: mock:fn(),
  readDockerContainerLabel: mock:fn(),
  readDockerPort: mock:fn(),
}));

const registryMocks = mock:hoisted(() => ({
  readBrowserRegistry: mock:fn(),
  updateBrowserRegistry: mock:fn(),
}));

const bridgeMocks = mock:hoisted(() => ({
  startBrowserBridgeServer: mock:fn(),
  stopBrowserBridgeServer: mock:fn(),
}));

mock:mock("./docker.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./docker.js")>();
  return {
    ...actual,
    dockerContainerState: dockerMocks.dockerContainerState,
    execDocker: dockerMocks.execDocker,
    readDockerContainerEnvVar: dockerMocks.readDockerContainerEnvVar,
    readDockerContainerLabel: dockerMocks.readDockerContainerLabel,
    readDockerPort: dockerMocks.readDockerPort,
  };
});

mock:mock("./registry.js", () => ({
  readBrowserRegistry: registryMocks.readBrowserRegistry,
  updateBrowserRegistry: registryMocks.updateBrowserRegistry,
}));

mock:mock("../../browser/bridge-server.js", () => ({
  startBrowserBridgeServer: bridgeMocks.startBrowserBridgeServer,
  stopBrowserBridgeServer: bridgeMocks.stopBrowserBridgeServer,
}));

function buildConfig(enableNoVnc: boolean): SandboxConfig {
  return {
    mode: "all",
    scope: "session",
    workspaceAccess: "none",
    workspaceRoot: "/tmp/openclaw-sandboxes",
    docker: {
      image: "openclaw-sandbox:bookworm-slim",
      containerPrefix: "openclaw-sbx-",
      workdir: "/workspace",
      readOnlyRoot: true,
      tmpfs: ["/tmp", "/var/tmp", "/run"],
      network: "none",
      capDrop: ["ALL"],
      env: { LANG: "C.UTF-8" },
    },
    browser: {
      enabled: true,
      image: "openclaw-sandbox-browser:bookworm-slim",
      containerPrefix: "openclaw-sbx-browser-",
      network: "openclaw-sandbox-browser",
      cdpPort: 9222,
      vncPort: 5900,
      noVncPort: 6080,
      headless: false,
      enableNoVnc,
      allowHostControl: false,
      autoStart: true,
      autoStartTimeoutMs: 12_000,
    },
    tools: {
      allow: ["browser"],
      deny: [],
    },
    prune: {
      idleHours: 24,
      maxAgeDays: 7,
    },
  };
}

(deftest-group "ensureSandboxBrowser create args", () => {
  beforeEach(() => {
    BROWSER_BRIDGES.clear();
    resetNoVncObserverTokensForTests();
    dockerMocks.dockerContainerState.mockClear();
    dockerMocks.execDocker.mockClear();
    dockerMocks.readDockerContainerEnvVar.mockClear();
    dockerMocks.readDockerContainerLabel.mockClear();
    dockerMocks.readDockerPort.mockClear();
    registryMocks.readBrowserRegistry.mockClear();
    registryMocks.updateBrowserRegistry.mockClear();
    bridgeMocks.startBrowserBridgeServer.mockClear();
    bridgeMocks.stopBrowserBridgeServer.mockClear();

    dockerMocks.dockerContainerState.mockResolvedValue({ exists: false, running: false });
    dockerMocks.execDocker.mockImplementation(async (args: string[]) => {
      if (args[0] === "image" && args[1] === "inspect") {
        return { stdout: "[]", stderr: "", code: 0 };
      }
      return { stdout: "", stderr: "", code: 0 };
    });
    dockerMocks.readDockerContainerLabel.mockResolvedValue(null);
    dockerMocks.readDockerContainerEnvVar.mockResolvedValue(null);
    dockerMocks.readDockerPort.mockImplementation(async (_containerName: string, port: number) => {
      if (port === 9222) {
        return 49100;
      }
      if (port === 6080) {
        return 49101;
      }
      return null;
    });
    registryMocks.readBrowserRegistry.mockResolvedValue({ entries: [] });
    registryMocks.updateBrowserRegistry.mockResolvedValue(undefined);
    bridgeMocks.startBrowserBridgeServer.mockResolvedValue({
      server: {} as never,
      port: 19000,
      baseUrl: "http://127.0.0.1:19000",
      state: {
        server: null,
        port: 19000,
        resolved: { profiles: {} },
        profiles: new Map(),
      },
    });
    bridgeMocks.stopBrowserBridgeServer.mockResolvedValue(undefined);
  });

  (deftest "publishes noVNC on loopback and injects noVNC password env", async () => {
    const result = await ensureSandboxBrowser({
      scopeKey: "session:test",
      workspaceDir: "/tmp/workspace",
      agentWorkspaceDir: "/tmp/workspace",
      cfg: buildConfig(true),
    });

    const createArgs = findDockerArgsCall(dockerMocks.execDocker.mock.calls, "create");

    (expect* createArgs).toBeDefined();
    (expect* createArgs).contains("127.0.0.1::6080");
    const envEntries = collectDockerFlagValues(createArgs ?? [], "-e");
    (expect* envEntries).contains("OPENCLAW_BROWSER_NO_SANDBOX=1");
    const passwordEntry = envEntries.find((entry) =>
      entry.startsWith("OPENCLAW_BROWSER_NOVNC_PASSWORD="),
    );
    (expect* passwordEntry).toMatch(/^OPENCLAW_BROWSER_NOVNC_PASSWORD=[A-Za-z0-9]{8}$/);
    (expect* result?.noVncUrl).toMatch(/^http:\/\/127\.0\.0\.1:19000\/sandbox\/novnc\?token=/);
    (expect* result?.noVncUrl).not.contains("password=");
  });

  (deftest "does not inject noVNC password env when noVNC is disabled", async () => {
    const result = await ensureSandboxBrowser({
      scopeKey: "session:test",
      workspaceDir: "/tmp/workspace",
      agentWorkspaceDir: "/tmp/workspace",
      cfg: buildConfig(false),
    });

    const createArgs = findDockerArgsCall(dockerMocks.execDocker.mock.calls, "create");
    const envEntries = collectDockerFlagValues(createArgs ?? [], "-e");
    (expect* envEntries.some((entry) => entry.startsWith("OPENCLAW_BROWSER_NOVNC_PASSWORD="))).is(
      false,
    );
    (expect* result?.noVncUrl).toBeUndefined();
  });

  (deftest "mounts the main workspace read-only when workspaceAccess is none", async () => {
    const cfg = buildConfig(false);
    cfg.workspaceAccess = "none";

    await ensureSandboxBrowser({
      scopeKey: "session:test",
      workspaceDir: "/tmp/workspace",
      agentWorkspaceDir: "/tmp/workspace",
      cfg,
    });

    const createArgs = findDockerArgsCall(dockerMocks.execDocker.mock.calls, "create");

    (expect* createArgs).toBeDefined();
    (expect* createArgs).contains("/tmp/workspace:/workspace:ro");
  });

  (deftest "keeps the main workspace writable when workspaceAccess is rw", async () => {
    const cfg = buildConfig(false);
    cfg.workspaceAccess = "rw";

    await ensureSandboxBrowser({
      scopeKey: "session:test",
      workspaceDir: "/tmp/workspace",
      agentWorkspaceDir: "/tmp/workspace",
      cfg,
    });

    const createArgs = findDockerArgsCall(dockerMocks.execDocker.mock.calls, "create");

    (expect* createArgs).toBeDefined();
    (expect* createArgs).contains("/tmp/workspace:/workspace");
    (expect* createArgs).not.contains("/tmp/workspace:/workspace:ro");
  });
});
