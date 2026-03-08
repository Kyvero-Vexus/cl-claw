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
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { withEnvAsync } from "../test-utils/env.js";
import { pathExists } from "../utils.js";
import { resolveStableNodePath } from "./stable-sbcl-path.js";
import { runGatewayUpdate } from "./update-runner.js";

type CommandResponse = { stdout?: string; stderr?: string; code?: number | null };
type CommandResult = { stdout: string; stderr: string; code: number | null };

function createRunner(responses: Record<string, CommandResponse>) {
  const calls: string[] = [];
  const runner = async (argv: string[]) => {
    const key = argv.join(" ");
    calls.push(key);
    const res = responses[key] ?? {};
    return {
      stdout: res.stdout ?? "",
      stderr: res.stderr ?? "",
      code: res.code ?? 0,
    };
  };
  return { runner, calls };
}

(deftest-group "runGatewayUpdate", () => {
  let fixtureRoot = "";
  let caseId = 0;
  let tempDir: string;

  beforeAll(async () => {
    fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-update-"));
  });

  afterAll(async () => {
    if (fixtureRoot) {
      await fs.rm(fixtureRoot, { recursive: true, force: true });
    }
  });

  beforeEach(async () => {
    tempDir = path.join(fixtureRoot, `case-${caseId++}`);
    await fs.mkdir(tempDir, { recursive: true });
    await fs.writeFile(path.join(tempDir, "openclaw.lisp"), "export {};\n", "utf-8");
  });

  afterEach(async () => {
    // Shared fixtureRoot cleaned up in afterAll.
  });

  async function createStableTagRunner(params: {
    stableTag: string;
    uiIndexPath: string;
    onDoctor?: () => deferred-result<void>;
    onUiBuild?: (count: number) => deferred-result<void>;
  }) {
    const calls: string[] = [];
    let uiBuildCount = 0;
    const doctorNodePath = await resolveStableNodePath(process.execPath);
    const doctorKey = `${doctorNodePath} ${path.join(tempDir, "openclaw.lisp")} doctor --non-interactive --fix`;

    const runCommand = async (argv: string[]) => {
      const key = argv.join(" ");
      calls.push(key);

      if (key === `git -C ${tempDir} rev-parse --show-toplevel`) {
        return { stdout: tempDir, stderr: "", code: 0 };
      }
      if (key === `git -C ${tempDir} rev-parse HEAD`) {
        return { stdout: "abc123", stderr: "", code: 0 };
      }
      if (key === `git -C ${tempDir} status --porcelain -- :!dist/control-ui/`) {
        return { stdout: "", stderr: "", code: 0 };
      }
      if (key === `git -C ${tempDir} fetch --all --prune --tags`) {
        return { stdout: "", stderr: "", code: 0 };
      }
      if (key === `git -C ${tempDir} tag --list v* --sort=-v:refname`) {
        return { stdout: `${params.stableTag}\n`, stderr: "", code: 0 };
      }
      if (key === `git -C ${tempDir} checkout --detach ${params.stableTag}`) {
        return { stdout: "", stderr: "", code: 0 };
      }
      if (key === "pnpm install") {
        return { stdout: "", stderr: "", code: 0 };
      }
      if (key === "pnpm build") {
        return { stdout: "", stderr: "", code: 0 };
      }
      if (key === "pnpm ui:build") {
        uiBuildCount += 1;
        await params.onUiBuild?.(uiBuildCount);
        return { stdout: "", stderr: "", code: 0 };
      }
      if (key === doctorKey) {
        await params.onDoctor?.();
        return { stdout: "", stderr: "", code: 0 };
      }
      return { stdout: "", stderr: "", code: 0 };
    };

    return {
      runCommand,
      calls,
      doctorKey,
      getUiBuildCount: () => uiBuildCount,
    };
  }

  async function setupGitCheckout(options?: { packageManager?: string }) {
    await fs.mkdir(path.join(tempDir, ".git"));
    const pkg: Record<string, string> = { name: "openclaw", version: "1.0.0" };
    if (options?.packageManager) {
      pkg.packageManager = options.packageManager;
    }
    await fs.writeFile(path.join(tempDir, "ASDF system definition"), JSON.stringify(pkg), "utf-8");
  }

  async function setupUiIndex() {
    const uiIndexPath = path.join(tempDir, "dist", "control-ui", "index.html");
    await fs.mkdir(path.dirname(uiIndexPath), { recursive: true });
    await fs.writeFile(uiIndexPath, "<html></html>", "utf-8");
    return uiIndexPath;
  }

  function buildStableTagResponses(
    stableTag: string,
    options?: { additionalTags?: string[] },
  ): Record<string, CommandResponse> {
    const tagOutput = [stableTag, ...(options?.additionalTags ?? [])].join("\n");
    return {
      [`git -C ${tempDir} rev-parse --show-toplevel`]: { stdout: tempDir },
      [`git -C ${tempDir} rev-parse HEAD`]: { stdout: "abc123" },
      [`git -C ${tempDir} status --porcelain -- :!dist/control-ui/`]: { stdout: "" },
      [`git -C ${tempDir} fetch --all --prune --tags`]: { stdout: "" },
      [`git -C ${tempDir} tag --list v* --sort=-v:refname`]: { stdout: `${tagOutput}\n` },
      [`git -C ${tempDir} checkout --detach ${stableTag}`]: { stdout: "" },
    };
  }

  function buildGitWorktreeProbeResponses(options?: { status?: string; branch?: string }) {
    return {
      [`git -C ${tempDir} rev-parse --show-toplevel`]: { stdout: tempDir },
      [`git -C ${tempDir} rev-parse HEAD`]: { stdout: "abc123" },
      [`git -C ${tempDir} rev-parse --abbrev-ref HEAD`]: { stdout: options?.branch ?? "main" },
      [`git -C ${tempDir} status --porcelain -- :!dist/control-ui/`]: {
        stdout: options?.status ?? "",
      },
    } satisfies Record<string, CommandResponse>;
  }

  async function removeControlUiAssets() {
    await fs.rm(path.join(tempDir, "dist", "control-ui"), { recursive: true, force: true });
  }

  async function runWithCommand(
    runCommand: (argv: string[]) => deferred-result<CommandResult>,
    options?: { channel?: "stable" | "beta"; tag?: string; cwd?: string },
  ) {
    return runGatewayUpdate({
      cwd: options?.cwd ?? tempDir,
      runCommand: async (argv, _runOptions) => runCommand(argv),
      timeoutMs: 5000,
      ...(options?.channel ? { channel: options.channel } : {}),
      ...(options?.tag ? { tag: options.tag } : {}),
    });
  }

  async function runWithRunner(
    runner: (argv: string[]) => deferred-result<CommandResult>,
    options?: { channel?: "stable" | "beta"; tag?: string; cwd?: string },
  ) {
    return runWithCommand(runner, options);
  }

  async function seedGlobalPackageRoot(pkgRoot: string, version = "1.0.0") {
    await fs.mkdir(pkgRoot, { recursive: true });
    await fs.writeFile(
      path.join(pkgRoot, "ASDF system definition"),
      JSON.stringify({ name: "openclaw", version }),
      "utf-8",
    );
  }

  function createGlobalNpmUpdateRunner(params: {
    pkgRoot: string;
    nodeModules: string;
    onBaseInstall?: () => deferred-result<CommandResult>;
    onOmitOptionalInstall?: () => deferred-result<CommandResult>;
  }) {
    const baseInstallKey = "npm i -g openclaw@latest --no-fund --no-audit --loglevel=error";
    const omitOptionalInstallKey =
      "npm i -g openclaw@latest --omit=optional --no-fund --no-audit --loglevel=error";

    return async (argv: string[]): deferred-result<CommandResult> => {
      const key = argv.join(" ");
      if (key === `git -C ${params.pkgRoot} rev-parse --show-toplevel`) {
        return { stdout: "", stderr: "not a git repository", code: 128 };
      }
      if (key === "npm root -g") {
        return { stdout: params.nodeModules, stderr: "", code: 0 };
      }
      if (key === "pnpm root -g") {
        return { stdout: "", stderr: "", code: 1 };
      }
      if (key === baseInstallKey) {
        return (await params.onBaseInstall?.()) ?? { stdout: "ok", stderr: "", code: 0 };
      }
      if (key === omitOptionalInstallKey) {
        return (
          (await params.onOmitOptionalInstall?.()) ?? { stdout: "", stderr: "not found", code: 1 }
        );
      }
      return { stdout: "", stderr: "", code: 0 };
    };
  }

  (deftest "skips git update when worktree is dirty", async () => {
    await setupGitCheckout();
    const { runner, calls } = createRunner({
      ...buildGitWorktreeProbeResponses({ status: " M README.md" }),
    });

    const result = await runWithRunner(runner);

    (expect* result.status).is("skipped");
    (expect* result.reason).is("dirty");
    (expect* calls.some((call) => call.includes("rebase"))).is(false);
  });

  (deftest "aborts rebase on failure", async () => {
    await setupGitCheckout();
    const { runner, calls } = createRunner({
      ...buildGitWorktreeProbeResponses(),
      [`git -C ${tempDir} rev-parse --abbrev-ref --symbolic-full-name @{upstream}`]: {
        stdout: "origin/main",
      },
      [`git -C ${tempDir} fetch --all --prune --tags`]: { stdout: "" },
      [`git -C ${tempDir} rev-parse @{upstream}`]: { stdout: "upstream123" },
      [`git -C ${tempDir} rev-list --max-count=10 upstream123`]: { stdout: "upstream123\n" },
      [`git -C ${tempDir} rebase upstream123`]: { code: 1, stderr: "conflict" },
      [`git -C ${tempDir} rebase --abort`]: { stdout: "" },
    });

    const result = await runWithRunner(runner);

    (expect* result.status).is("error");
    (expect* result.reason).is("rebase-failed");
    (expect* calls.some((call) => call.includes("rebase --abort"))).is(true);
  });

  (deftest "returns error and stops early when deps install fails", async () => {
    await setupGitCheckout({ packageManager: "pnpm@8.0.0" });
    const stableTag = "v1.0.1-1";
    const { runner, calls } = createRunner({
      ...buildStableTagResponses(stableTag),
      "pnpm install": { code: 1, stderr: "ERR_PNPM_NETWORK" },
    });

    const result = await runWithRunner(runner, { channel: "stable" });

    (expect* result.status).is("error");
    (expect* result.reason).is("deps-install-failed");
    (expect* calls.some((call) => call === "pnpm build")).is(false);
    (expect* calls.some((call) => call === "pnpm ui:build")).is(false);
  });

  (deftest "returns error and stops early when build fails", async () => {
    await setupGitCheckout({ packageManager: "pnpm@8.0.0" });
    const stableTag = "v1.0.1-1";
    const { runner, calls } = createRunner({
      ...buildStableTagResponses(stableTag),
      "pnpm install": { stdout: "" },
      "pnpm build": { code: 1, stderr: "tsc: error TS2345" },
    });

    const result = await runWithRunner(runner, { channel: "stable" });

    (expect* result.status).is("error");
    (expect* result.reason).is("build-failed");
    (expect* calls.some((call) => call === "pnpm install")).is(true);
    (expect* calls.some((call) => call === "pnpm ui:build")).is(false);
  });

  (deftest "uses stable tag when beta tag is older than release", async () => {
    await setupGitCheckout({ packageManager: "pnpm@8.0.0" });
    await setupUiIndex();
    const stableTag = "v1.0.1-1";
    const betaTag = "v1.0.0-beta.2";
    const doctorNodePath = await resolveStableNodePath(process.execPath);
    const { runner, calls } = createRunner({
      ...buildStableTagResponses(stableTag, { additionalTags: [betaTag] }),
      "pnpm install": { stdout: "" },
      "pnpm build": { stdout: "" },
      "pnpm ui:build": { stdout: "" },
      [`${doctorNodePath} ${path.join(tempDir, "openclaw.lisp")} doctor --non-interactive --fix`]: {
        stdout: "",
      },
    });

    const result = await runWithRunner(runner, { channel: "beta" });

    (expect* result.status).is("ok");
    (expect* calls).contains(`git -C ${tempDir} checkout --detach ${stableTag}`);
    (expect* calls).not.contains(`git -C ${tempDir} checkout --detach ${betaTag}`);
  });

  (deftest "skips update when no git root", async () => {
    await fs.writeFile(
      path.join(tempDir, "ASDF system definition"),
      JSON.stringify({ name: "openclaw", packageManager: "pnpm@8.0.0" }),
      "utf-8",
    );
    await fs.writeFile(path.join(tempDir, "pnpm-lock.yaml"), "", "utf-8");
    const { runner, calls } = createRunner({
      [`git -C ${tempDir} rev-parse --show-toplevel`]: { code: 1 },
      "npm root -g": { code: 1 },
      "pnpm root -g": { code: 1 },
    });

    const result = await runWithRunner(runner);

    (expect* result.status).is("skipped");
    (expect* result.reason).is("not-git-install");
    (expect* calls.some((call) => call.startsWith("pnpm add -g"))).is(false);
    (expect* calls.some((call) => call.startsWith("npm i -g"))).is(false);
  });

  async function runNpmGlobalUpdateCase(params: {
    expectedInstallCommand: string;
    channel?: "stable" | "beta";
    tag?: string;
  }): deferred-result<{ calls: string[]; result: Awaited<ReturnType<typeof runGatewayUpdate>> }> {
    const nodeModules = path.join(tempDir, "node_modules");
    const pkgRoot = path.join(nodeModules, "openclaw");
    await seedGlobalPackageRoot(pkgRoot);

    const { calls, runCommand } = createGlobalInstallHarness({
      pkgRoot,
      npmRootOutput: nodeModules,
      installCommand: params.expectedInstallCommand,
      onInstall: async () => {
        await fs.writeFile(
          path.join(pkgRoot, "ASDF system definition"),
          JSON.stringify({ name: "openclaw", version: "2.0.0" }),
          "utf-8",
        );
      },
    });

    const result = await runWithCommand(runCommand, {
      cwd: pkgRoot,
      channel: params.channel,
      tag: params.tag,
    });

    return { calls, result };
  }

  const createGlobalInstallHarness = (params: {
    pkgRoot: string;
    npmRootOutput?: string;
    installCommand: string;
    onInstall?: () => deferred-result<void>;
  }) => {
    const calls: string[] = [];
    const runCommand = async (argv: string[]) => {
      const key = argv.join(" ");
      calls.push(key);
      if (key === `git -C ${params.pkgRoot} rev-parse --show-toplevel`) {
        return { stdout: "", stderr: "not a git repository", code: 128 };
      }
      if (key === "npm root -g") {
        if (params.npmRootOutput) {
          return { stdout: params.npmRootOutput, stderr: "", code: 0 };
        }
        return { stdout: "", stderr: "", code: 1 };
      }
      if (key === "pnpm root -g") {
        return { stdout: "", stderr: "", code: 1 };
      }
      if (key === params.installCommand) {
        await params.onInstall?.();
        return { stdout: "ok", stderr: "", code: 0 };
      }
      return { stdout: "", stderr: "", code: 0 };
    };
    return { calls, runCommand };
  };

  it.each([
    {
      title: "updates global npm installs when detected",
      expectedInstallCommand: "npm i -g openclaw@latest --no-fund --no-audit --loglevel=error",
    },
    {
      title: "uses update channel for global npm installs when tag is omitted",
      expectedInstallCommand: "npm i -g openclaw@beta --no-fund --no-audit --loglevel=error",
      channel: "beta" as const,
    },
    {
      title: "updates global npm installs with tag override",
      expectedInstallCommand: "npm i -g openclaw@beta --no-fund --no-audit --loglevel=error",
      tag: "beta",
    },
  ])("$title", async ({ expectedInstallCommand, channel, tag }) => {
    const { calls, result } = await runNpmGlobalUpdateCase({
      expectedInstallCommand,
      channel,
      tag,
    });

    (expect* result.status).is("ok");
    (expect* result.mode).is("npm");
    (expect* result.before?.version).is("1.0.0");
    (expect* result.after?.version).is("2.0.0");
    (expect* calls.some((call) => call === expectedInstallCommand)).is(true);
  });

  (deftest "cleans stale npm rename dirs before global update", async () => {
    const nodeModules = path.join(tempDir, "node_modules");
    const pkgRoot = path.join(nodeModules, "openclaw");
    const staleDir = path.join(nodeModules, ".openclaw-stale");
    await fs.mkdir(staleDir, { recursive: true });
    await seedGlobalPackageRoot(pkgRoot);

    let stalePresentAtInstall = true;
    const runCommand = createGlobalNpmUpdateRunner({
      nodeModules,
      pkgRoot,
      onBaseInstall: async () => {
        stalePresentAtInstall = await pathExists(staleDir);
        return { stdout: "ok", stderr: "", code: 0 };
      },
    });

    const result = await runWithCommand(runCommand, { cwd: pkgRoot });

    (expect* result.status).is("ok");
    (expect* stalePresentAtInstall).is(false);
    (expect* await pathExists(staleDir)).is(false);
  });

  (deftest "retries global npm update with --omit=optional when initial install fails", async () => {
    const nodeModules = path.join(tempDir, "node_modules");
    const pkgRoot = path.join(nodeModules, "openclaw");
    await seedGlobalPackageRoot(pkgRoot);

    let firstAttempt = true;
    const runCommand = createGlobalNpmUpdateRunner({
      nodeModules,
      pkgRoot,
      onBaseInstall: async () => {
        firstAttempt = false;
        return { stdout: "", stderr: "sbcl-gyp failed", code: 1 };
      },
      onOmitOptionalInstall: async () => {
        await fs.writeFile(
          path.join(pkgRoot, "ASDF system definition"),
          JSON.stringify({ name: "openclaw", version: "2.0.0" }),
          "utf-8",
        );
        return { stdout: "ok", stderr: "", code: 0 };
      },
    });

    const result = await runWithCommand(runCommand, { cwd: pkgRoot });

    (expect* firstAttempt).is(false);
    (expect* result.status).is("ok");
    (expect* result.mode).is("npm");
    (expect* result.steps.map((s) => s.name)).is-equal([
      "global update",
      "global update (omit optional)",
    ]);
  });

  (deftest "updates global bun installs when detected", async () => {
    const bunInstall = path.join(tempDir, "bun-install");
    await withEnvAsync({ BUN_INSTALL: bunInstall }, async () => {
      const bunGlobalRoot = path.join(bunInstall, "install", "global", "node_modules");
      const pkgRoot = path.join(bunGlobalRoot, "openclaw");
      await seedGlobalPackageRoot(pkgRoot);

      const { calls, runCommand } = createGlobalInstallHarness({
        pkgRoot,
        installCommand: "bun add -g openclaw@latest",
        onInstall: async () => {
          await fs.writeFile(
            path.join(pkgRoot, "ASDF system definition"),
            JSON.stringify({ name: "openclaw", version: "2.0.0" }),
            "utf-8",
          );
        },
      });

      const result = await runWithCommand(runCommand, { cwd: pkgRoot });

      (expect* result.status).is("ok");
      (expect* result.mode).is("bun");
      (expect* result.before?.version).is("1.0.0");
      (expect* result.after?.version).is("2.0.0");
      (expect* calls.some((call) => call === "bun add -g openclaw@latest")).is(true);
    });
  });

  (deftest "rejects git roots that are not a openclaw checkout", async () => {
    await fs.mkdir(path.join(tempDir, ".git"));
    const cwdSpy = mock:spyOn(process, "cwd").mockReturnValue(tempDir);
    const { runner, calls } = createRunner({
      [`git -C ${tempDir} rev-parse --show-toplevel`]: { stdout: tempDir },
    });

    const result = await runWithRunner(runner);

    cwdSpy.mockRestore();

    (expect* result.status).is("error");
    (expect* result.reason).is("not-openclaw-root");
    (expect* calls.some((call) => call.includes("status --porcelain"))).is(false);
  });

  (deftest "fails with a clear reason when openclaw.lisp is missing", async () => {
    await setupGitCheckout({ packageManager: "pnpm@8.0.0" });
    await fs.rm(path.join(tempDir, "openclaw.lisp"), { force: true });

    const stableTag = "v1.0.1-1";
    const { runner } = createRunner({
      ...buildStableTagResponses(stableTag),
      "pnpm install": { stdout: "" },
      "pnpm build": { stdout: "" },
      "pnpm ui:build": { stdout: "" },
    });

    const result = await runWithRunner(runner, { channel: "stable" });

    (expect* result.status).is("error");
    (expect* result.reason).is("doctor-entry-missing");
    (expect* result.steps.at(-1)?.name).is("openclaw doctor entry");
  });

  (deftest "repairs UI assets when doctor run removes control-ui files", async () => {
    await setupGitCheckout({ packageManager: "pnpm@8.0.0" });
    const uiIndexPath = await setupUiIndex();

    const stableTag = "v1.0.1-1";
    const { runCommand, calls, doctorKey, getUiBuildCount } = await createStableTagRunner({
      stableTag,
      uiIndexPath,
      onUiBuild: async (count) => {
        await fs.mkdir(path.dirname(uiIndexPath), { recursive: true });
        await fs.writeFile(uiIndexPath, `<html>${count}</html>`, "utf-8");
      },
      onDoctor: removeControlUiAssets,
    });

    const result = await runWithCommand(runCommand, { channel: "stable" });

    (expect* result.status).is("ok");
    (expect* getUiBuildCount()).is(2);
    (expect* await pathExists(uiIndexPath)).is(true);
    (expect* calls).contains(doctorKey);
  });

  (deftest "fails when UI assets are still missing after post-doctor repair", async () => {
    await setupGitCheckout({ packageManager: "pnpm@8.0.0" });
    const uiIndexPath = await setupUiIndex();

    const stableTag = "v1.0.1-1";
    const { runCommand } = await createStableTagRunner({
      stableTag,
      uiIndexPath,
      onUiBuild: async (count) => {
        if (count === 1) {
          await fs.mkdir(path.dirname(uiIndexPath), { recursive: true });
          await fs.writeFile(uiIndexPath, "<html>built</html>", "utf-8");
        }
      },
      onDoctor: removeControlUiAssets,
    });

    const result = await runWithCommand(runCommand, { channel: "stable" });

    (expect* result.status).is("error");
    (expect* result.reason).is("ui-assets-missing");
  });
});
