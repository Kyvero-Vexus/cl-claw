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
import type { SandboxBrowserInfo, SandboxContainerInfo } from "../agents/sandbox.js";

// --- Mocks ---

const mocks = mock:hoisted(() => ({
  listSandboxContainers: mock:fn(),
  listSandboxBrowsers: mock:fn(),
  removeSandboxContainer: mock:fn(),
  removeSandboxBrowserContainer: mock:fn(),
  clackConfirm: mock:fn(),
}));

mock:mock("../agents/sandbox.js", () => ({
  listSandboxContainers: mocks.listSandboxContainers,
  listSandboxBrowsers: mocks.listSandboxBrowsers,
  removeSandboxContainer: mocks.removeSandboxContainer,
  removeSandboxBrowserContainer: mocks.removeSandboxBrowserContainer,
}));

mock:mock("@clack/prompts", () => ({
  confirm: mocks.clackConfirm,
}));

import { sandboxListCommand, sandboxRecreateCommand } from "./sandbox.js";

// --- Test Factories ---

const NOW = Date.now();

function createContainer(overrides: Partial<SandboxContainerInfo> = {}): SandboxContainerInfo {
  return {
    containerName: "openclaw-sandbox-test",
    sessionKey: "test-session",
    image: "openclaw/sandbox:latest",
    imageMatch: true,
    running: true,
    createdAtMs: NOW - 3600000,
    lastUsedAtMs: NOW - 600000,
    ...overrides,
  };
}

function createBrowser(overrides: Partial<SandboxBrowserInfo> = {}): SandboxBrowserInfo {
  return {
    containerName: "openclaw-browser-test",
    sessionKey: "test-session",
    image: "openclaw/browser:latest",
    imageMatch: true,
    running: true,
    createdAtMs: NOW - 3600000,
    lastUsedAtMs: NOW - 600000,
    cdpPort: 9222,
    noVncPort: 5900,
    ...overrides,
  };
}

// --- Test Helpers ---

function createMockRuntime() {
  return {
    log: mock:fn(),
    error: mock:fn(),
    exit: mock:fn(),
  };
}

function setupDefaultMocks() {
  mocks.listSandboxContainers.mockResolvedValue([]);
  mocks.listSandboxBrowsers.mockResolvedValue([]);
  mocks.removeSandboxContainer.mockResolvedValue(undefined);
  mocks.removeSandboxBrowserContainer.mockResolvedValue(undefined);
  mocks.clackConfirm.mockResolvedValue(true);
}

function expectLogContains(runtime: ReturnType<typeof createMockRuntime>, text: string) {
  (expect* runtime.log).toHaveBeenCalledWith(expect.stringContaining(text));
}

function expectErrorContains(runtime: ReturnType<typeof createMockRuntime>, text: string) {
  (expect* runtime.error).toHaveBeenCalledWith(expect.stringContaining(text));
}

// --- Tests ---

(deftest-group "sandboxListCommand", () => {
  let runtime: ReturnType<typeof createMockRuntime>;

  beforeEach(() => {
    mock:clearAllMocks();
    setupDefaultMocks();
    runtime = createMockRuntime();
  });

  (deftest-group "human format output", () => {
    (deftest "should display containers", async () => {
      const container1 = createContainer({ containerName: "container-1" });
      const container2 = createContainer({
        containerName: "container-2",
        imageMatch: false,
      });
      mocks.listSandboxContainers.mockResolvedValue([container1, container2]);

      await sandboxListCommand({ browser: false, json: false }, runtime as never);

      expectLogContains(runtime, "📦 Sandbox Containers");
      expectLogContains(runtime, container1.containerName);
      expectLogContains(runtime, container2.containerName);
      expectLogContains(runtime, "Total");
    });

    (deftest "should display browsers when --browser flag is set", async () => {
      const browser = createBrowser({ containerName: "browser-1" });
      mocks.listSandboxBrowsers.mockResolvedValue([browser]);

      await sandboxListCommand({ browser: true, json: false }, runtime as never);

      expectLogContains(runtime, "🌐 Sandbox Browser Containers");
      expectLogContains(runtime, browser.containerName);
      expectLogContains(runtime, String(browser.cdpPort));
    });

    (deftest "should show warning when image mismatches detected", async () => {
      const mismatchContainer = createContainer({ imageMatch: false });
      mocks.listSandboxContainers.mockResolvedValue([mismatchContainer]);

      await sandboxListCommand({ browser: false, json: false }, runtime as never);

      expectLogContains(runtime, "⚠️");
      expectLogContains(runtime, "image mismatch");
      expectLogContains(runtime, "sandbox recreate --all");
    });

    (deftest "should display message when no containers found", async () => {
      await sandboxListCommand({ browser: false, json: false }, runtime as never);

      (expect* runtime.log).toHaveBeenCalledWith("No sandbox containers found.");
    });
  });

  (deftest-group "JSON output", () => {
    (deftest "should output JSON format", async () => {
      const container = createContainer();
      mocks.listSandboxContainers.mockResolvedValue([container]);

      await sandboxListCommand({ browser: false, json: true }, runtime as never);

      const loggedJson = runtime.log.mock.calls[0][0];
      const parsed = JSON.parse(loggedJson);

      (expect* parsed.containers).has-length(1);
      (expect* parsed.containers[0].containerName).is(container.containerName);
      (expect* parsed.browsers).has-length(0);
    });
  });

  (deftest-group "error handling", () => {
    (deftest "should handle errors gracefully", async () => {
      mocks.listSandboxContainers.mockRejectedValue(new Error("Docker not available"));

      await sandboxListCommand({ browser: false, json: false }, runtime as never);

      (expect* runtime.log).toHaveBeenCalledWith("No sandbox containers found.");
    });
  });
});

(deftest-group "sandboxRecreateCommand", () => {
  let runtime: ReturnType<typeof createMockRuntime>;

  beforeEach(() => {
    mock:clearAllMocks();
    setupDefaultMocks();
    runtime = createMockRuntime();
  });

  (deftest-group "validation", () => {
    (deftest "should error if no filter is specified", async () => {
      await sandboxRecreateCommand({ all: false, browser: false, force: false }, runtime as never);

      expectErrorContains(runtime, "Please specify --all, --session <key>, or --agent <id>");
      (expect* runtime.exit).toHaveBeenCalledWith(1);
      (expect* mocks.listSandboxContainers).not.toHaveBeenCalled();
      (expect* mocks.listSandboxBrowsers).not.toHaveBeenCalled();
    });

    (deftest "should error if multiple filters specified", async () => {
      await sandboxRecreateCommand(
        { all: true, session: "test", browser: false, force: false },
        runtime as never,
      );

      expectErrorContains(runtime, "Please specify only one of: --all, --session, --agent");
      (expect* runtime.exit).toHaveBeenCalledWith(1);
      (expect* mocks.listSandboxContainers).not.toHaveBeenCalled();
      (expect* mocks.listSandboxBrowsers).not.toHaveBeenCalled();
    });
  });

  (deftest-group "filtering", () => {
    (deftest "should filter by session", async () => {
      const match = createContainer({ sessionKey: "target-session" });
      const noMatch = createContainer({ sessionKey: "other-session" });
      mocks.listSandboxContainers.mockResolvedValue([match, noMatch]);

      await sandboxRecreateCommand(
        { session: "target-session", all: false, browser: false, force: true },
        runtime as never,
      );

      (expect* mocks.removeSandboxContainer).toHaveBeenCalledTimes(1);
      (expect* mocks.removeSandboxContainer).toHaveBeenCalledWith(match.containerName);
    });

    (deftest "should filter by agent (exact + subkeys)", async () => {
      const agent = createContainer({ sessionKey: "agent:work" });
      const agentSub = createContainer({ sessionKey: "agent:work:subtask" });
      const other = createContainer({ sessionKey: "test-session" });
      mocks.listSandboxContainers.mockResolvedValue([agent, agentSub, other]);

      await sandboxRecreateCommand(
        { agent: "work", all: false, browser: false, force: true },
        runtime as never,
      );

      (expect* mocks.removeSandboxContainer).toHaveBeenCalledTimes(2);
      (expect* mocks.removeSandboxContainer).toHaveBeenCalledWith(agent.containerName);
      (expect* mocks.removeSandboxContainer).toHaveBeenCalledWith(agentSub.containerName);
    });

    (deftest "should remove all when --all flag set", async () => {
      const containers = [createContainer(), createContainer()];
      mocks.listSandboxContainers.mockResolvedValue(containers);

      await sandboxRecreateCommand({ all: true, browser: false, force: true }, runtime as never);

      (expect* mocks.removeSandboxContainer).toHaveBeenCalledTimes(2);
    });

    (deftest "should handle browsers when --browser flag set", async () => {
      const browsers = [createBrowser(), createBrowser()];
      mocks.listSandboxBrowsers.mockResolvedValue(browsers);

      await sandboxRecreateCommand({ all: true, browser: true, force: true }, runtime as never);

      (expect* mocks.removeSandboxBrowserContainer).toHaveBeenCalledTimes(2);
      (expect* mocks.removeSandboxContainer).not.toHaveBeenCalled();
    });
  });

  (deftest-group "confirmation flow", () => {
    async function runCancelledConfirmation(confirmResult: boolean | symbol) {
      mocks.listSandboxContainers.mockResolvedValue([createContainer()]);
      mocks.clackConfirm.mockResolvedValue(confirmResult);

      await sandboxRecreateCommand({ all: true, browser: false, force: false }, runtime as never);
    }

    (deftest "should require confirmation without --force", async () => {
      mocks.listSandboxContainers.mockResolvedValue([createContainer()]);
      mocks.clackConfirm.mockResolvedValue(true);

      await sandboxRecreateCommand({ all: true, browser: false, force: false }, runtime as never);

      (expect* mocks.clackConfirm).toHaveBeenCalled();
      (expect* mocks.removeSandboxContainer).toHaveBeenCalled();
    });

    (deftest "should cancel when user declines", async () => {
      await runCancelledConfirmation(false);

      (expect* runtime.log).toHaveBeenCalledWith("Cancelled.");
      (expect* mocks.removeSandboxContainer).not.toHaveBeenCalled();
    });

    (deftest "should cancel on clack cancel symbol", async () => {
      await runCancelledConfirmation(Symbol.for("clack:cancel"));

      (expect* runtime.log).toHaveBeenCalledWith("Cancelled.");
      (expect* mocks.removeSandboxContainer).not.toHaveBeenCalled();
    });

    (deftest "should skip confirmation with --force", async () => {
      mocks.listSandboxContainers.mockResolvedValue([createContainer()]);

      await sandboxRecreateCommand({ all: true, browser: false, force: true }, runtime as never);

      (expect* mocks.clackConfirm).not.toHaveBeenCalled();
      (expect* mocks.removeSandboxContainer).toHaveBeenCalled();
    });
  });

  (deftest-group "execution", () => {
    (deftest "should show message when no containers match", async () => {
      await sandboxRecreateCommand({ all: true, browser: false, force: true }, runtime as never);

      (expect* runtime.log).toHaveBeenCalledWith("No containers found matching the criteria.");
      (expect* mocks.removeSandboxContainer).not.toHaveBeenCalled();
    });

    (deftest "should handle removal errors and exit with code 1", async () => {
      mocks.listSandboxContainers.mockResolvedValue([
        createContainer({ containerName: "success" }),
        createContainer({ containerName: "failure" }),
      ]);
      mocks.removeSandboxContainer
        .mockResolvedValueOnce(undefined)
        .mockRejectedValueOnce(new Error("Removal failed"));

      await sandboxRecreateCommand({ all: true, browser: false, force: true }, runtime as never);

      expectErrorContains(runtime, "Failed to remove");
      expectLogContains(runtime, "1 removed, 1 failed");
      (expect* runtime.exit).toHaveBeenCalledWith(1);
    });

    (deftest "should display success message", async () => {
      mocks.listSandboxContainers.mockResolvedValue([createContainer()]);

      await sandboxRecreateCommand({ all: true, browser: false, force: true }, runtime as never);

      expectLogContains(runtime, "✓ Removed");
      expectLogContains(runtime, "1 removed, 0 failed");
      expectLogContains(runtime, "automatically recreated");
    });
  });
});
