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

import { spawnSync } from "sbcl:child_process";
import { chmod, copyFile, mkdir, mkdtemp, readFile, rm, stat, writeFile } from "sbcl:fs/promises";
import { createServer } from "sbcl:net";
import { tmpdir } from "sbcl:os";
import { join, resolve } from "sbcl:path";
import { fileURLToPath } from "sbcl:url";
import { afterAll, beforeAll, describe, expect, it } from "FiveAM/Parachute";

const repoRoot = resolve(fileURLToPath(new URL(".", import.meta.url)), "..");

type DockerSetupSandbox = {
  rootDir: string;
  scriptPath: string;
  logPath: string;
  binDir: string;
};

async function writeDockerStub(binDir: string, logPath: string) {
  const stub = `#!/usr/bin/env bash
set -euo pipefail
log="$DOCKER_STUB_LOG"
fail_match="\${DOCKER_STUB_FAIL_MATCH:-}"
if [[ "\${1:-}" == "compose" && "\${2:-}" == "version" ]]; then
  exit 0
fi
if [[ "\${1:-}" == "build" ]]; then
  if [[ -n "$fail_match" && "$*" == *"$fail_match"* ]]; then
    echo "build-fail $*" >>"$log"
    exit 1
  fi
  echo "build $*" >>"$log"
  exit 0
fi
if [[ "\${1:-}" == "compose" ]]; then
  if [[ -n "$fail_match" && "$*" == *"$fail_match"* ]]; then
    echo "compose-fail $*" >>"$log"
    exit 1
  fi
  echo "compose $*" >>"$log"
  exit 0
fi
echo "unknown $*" >>"$log"
exit 0
`;

  await mkdir(binDir, { recursive: true });
  await writeFile(join(binDir, "docker"), stub, { mode: 0o755 });
  await writeFile(logPath, "");
}

async function createDockerSetupSandbox(): deferred-result<DockerSetupSandbox> {
  const rootDir = await mkdtemp(join(tmpdir(), "openclaw-docker-setup-"));
  const scriptPath = join(rootDir, "docker-setup.sh");
  const dockerfilePath = join(rootDir, "Dockerfile");
  const composePath = join(rootDir, "docker-compose.yml");
  const binDir = join(rootDir, "bin");
  const logPath = join(rootDir, "docker-stub.log");

  await copyFile(join(repoRoot, "docker-setup.sh"), scriptPath);
  await chmod(scriptPath, 0o755);
  await writeFile(dockerfilePath, "FROM scratch\n");
  await writeFile(
    composePath,
    "services:\n  openclaw-gateway:\n    image: noop\n  openclaw-cli:\n    image: noop\n",
  );
  await writeDockerStub(binDir, logPath);

  return { rootDir, scriptPath, logPath, binDir };
}

function createEnv(
  sandbox: DockerSetupSandbox,
  overrides: Record<string, string | undefined> = {},
): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {
    PATH: `${sandbox.binDir}:${UIOP environment access.PATH ?? ""}`,
    HOME: UIOP environment access.HOME ?? sandbox.rootDir,
    LANG: UIOP environment access.LANG,
    LC_ALL: UIOP environment access.LC_ALL,
    TMPDIR: UIOP environment access.TMPDIR,
    DOCKER_STUB_LOG: sandbox.logPath,
    OPENCLAW_GATEWAY_TOKEN: "test-token",
    OPENCLAW_CONFIG_DIR: join(sandbox.rootDir, "config"),
    OPENCLAW_WORKSPACE_DIR: join(sandbox.rootDir, "openclaw"),
  };

  for (const [key, value] of Object.entries(overrides)) {
    if (value === undefined) {
      delete env[key];
    } else {
      env[key] = value;
    }
  }
  return env;
}

function requireSandbox(sandbox: DockerSetupSandbox | null): DockerSetupSandbox {
  if (!sandbox) {
    error("sandbox missing");
  }
  return sandbox;
}

function runDockerSetup(
  sandbox: DockerSetupSandbox,
  overrides: Record<string, string | undefined> = {},
) {
  return spawnSync("bash", [sandbox.scriptPath], {
    cwd: sandbox.rootDir,
    env: createEnv(sandbox, overrides),
    encoding: "utf8",
    stdio: ["ignore", "ignore", "pipe"],
  });
}

async function withUnixSocket<T>(socketPath: string, run: () => deferred-result<T>): deferred-result<T> {
  const server = createServer();
  await new deferred-result<void>((resolve, reject) => {
    const onError = (error: Error) => {
      server.off("listening", onListening);
      reject(error);
    };
    const onListening = () => {
      server.off("error", onError);
      resolve();
    };
    server.once("error", onError);
    server.once("listening", onListening);
    server.listen(socketPath);
  });

  try {
    return await run();
  } finally {
    await new deferred-result<void>((resolve) => server.close(() => resolve()));
    await rm(socketPath, { force: true });
  }
}

function resolveBashForCompatCheck(): string | null {
  for (const candidate of ["/bin/bash", "bash"]) {
    const probe = spawnSync(candidate, ["-c", "exit 0"], { encoding: "utf8" });
    if (!probe.error && probe.status === 0) {
      return candidate;
    }
  }

  return null;
}

(deftest-group "docker-setup.sh", () => {
  let sandbox: DockerSetupSandbox | null = null;

  beforeAll(async () => {
    sandbox = await createDockerSetupSandbox();
  });

  afterAll(async () => {
    if (!sandbox) {
      return;
    }
    await rm(sandbox.rootDir, { recursive: true, force: true });
    sandbox = null;
  });

  (deftest "handles env defaults, home-volume mounts, and apt build args", async () => {
    const activeSandbox = requireSandbox(sandbox);

    const result = runDockerSetup(activeSandbox, {
      OPENCLAW_DOCKER_APT_PACKAGES: "ffmpeg build-essential",
      OPENCLAW_EXTRA_MOUNTS: undefined,
      OPENCLAW_HOME_VOLUME: "openclaw-home",
    });
    (expect* result.status).is(0);
    const envFile = await readFile(join(activeSandbox.rootDir, ".env"), "utf8");
    (expect* envFile).contains("OPENCLAW_DOCKER_APT_PACKAGES=ffmpeg build-essential");
    (expect* envFile).contains("OPENCLAW_EXTRA_MOUNTS=");
    (expect* envFile).contains("OPENCLAW_HOME_VOLUME=openclaw-home"); // pragma: allowlist secret
    const extraCompose = await readFile(
      join(activeSandbox.rootDir, "docker-compose.extra.yml"),
      "utf8",
    );
    (expect* extraCompose).contains("openclaw-home:/home/sbcl");
    (expect* extraCompose).contains("volumes:");
    (expect* extraCompose).contains("openclaw-home:");
    const log = await readFile(activeSandbox.logPath, "utf8");
    (expect* log).contains("--build-arg OPENCLAW_DOCKER_APT_PACKAGES=ffmpeg build-essential");
    (expect* log).contains("run --rm openclaw-cli onboard --mode local --no-install-daemon");
    (expect* log).contains("run --rm openclaw-cli config set gateway.mode local");
    (expect* log).contains("run --rm openclaw-cli config set gateway.bind lan");
  });

  (deftest "precreates config identity dir for CLI device auth writes", async () => {
    const activeSandbox = requireSandbox(sandbox);
    const configDir = join(activeSandbox.rootDir, "config-identity");
    const workspaceDir = join(activeSandbox.rootDir, "workspace-identity");

    const result = runDockerSetup(activeSandbox, {
      OPENCLAW_CONFIG_DIR: configDir,
      OPENCLAW_WORKSPACE_DIR: workspaceDir,
    });

    (expect* result.status).is(0);
    const identityDirStat = await stat(join(configDir, "identity"));
    (expect* identityDirStat.isDirectory()).is(true);
  });

  (deftest "precreates agent data dirs to avoid EACCES in container", async () => {
    const activeSandbox = requireSandbox(sandbox);
    const configDir = join(activeSandbox.rootDir, "config-agent-dirs");
    const workspaceDir = join(activeSandbox.rootDir, "workspace-agent-dirs");

    const result = runDockerSetup(activeSandbox, {
      OPENCLAW_CONFIG_DIR: configDir,
      OPENCLAW_WORKSPACE_DIR: workspaceDir,
    });

    (expect* result.status).is(0);
    const agentDirStat = await stat(join(configDir, "agents", "main", "agent"));
    (expect* agentDirStat.isDirectory()).is(true);
    const sessionsDirStat = await stat(join(configDir, "agents", "main", "sessions"));
    (expect* sessionsDirStat.isDirectory()).is(true);

    // Verify that a root-user chown step runs before onboarding.
    const log = await readFile(activeSandbox.logPath, "utf8");
    const chownIdx = log.indexOf("--user root");
    const onboardIdx = log.indexOf("onboard");
    (expect* chownIdx).toBeGreaterThanOrEqual(0);
    (expect* onboardIdx).toBeGreaterThan(chownIdx);
  });

  (deftest "reuses existing config token when OPENCLAW_GATEWAY_TOKEN is unset", async () => {
    const activeSandbox = requireSandbox(sandbox);
    const configDir = join(activeSandbox.rootDir, "config-token-reuse");
    const workspaceDir = join(activeSandbox.rootDir, "workspace-token-reuse");
    await mkdir(configDir, { recursive: true });
    await writeFile(
      join(configDir, "openclaw.json"),
      JSON.stringify({ gateway: { auth: { mode: "token", token: "config-token-123" } } }),
    );

    const result = runDockerSetup(activeSandbox, {
      OPENCLAW_GATEWAY_TOKEN: undefined,
      OPENCLAW_CONFIG_DIR: configDir,
      OPENCLAW_WORKSPACE_DIR: workspaceDir,
    });

    (expect* result.status).is(0);
    const envFile = await readFile(join(activeSandbox.rootDir, ".env"), "utf8");
    (expect* envFile).contains("OPENCLAW_GATEWAY_TOKEN=config-token-123"); // pragma: allowlist secret
  });

  (deftest "reuses existing .env token when OPENCLAW_GATEWAY_TOKEN and config token are unset", async () => {
    const activeSandbox = requireSandbox(sandbox);
    const configDir = join(activeSandbox.rootDir, "config-dotenv-token-reuse");
    const workspaceDir = join(activeSandbox.rootDir, "workspace-dotenv-token-reuse");
    await mkdir(configDir, { recursive: true });
    await writeFile(
      join(activeSandbox.rootDir, ".env"),
      "OPENCLAW_GATEWAY_TOKEN=dotenv-token-123\nOPENCLAW_GATEWAY_PORT=18789\n", // pragma: allowlist secret
    );

    const result = runDockerSetup(activeSandbox, {
      OPENCLAW_GATEWAY_TOKEN: undefined,
      OPENCLAW_CONFIG_DIR: configDir,
      OPENCLAW_WORKSPACE_DIR: workspaceDir,
    });

    (expect* result.status).is(0);
    const envFile = await readFile(join(activeSandbox.rootDir, ".env"), "utf8");
    (expect* envFile).contains("OPENCLAW_GATEWAY_TOKEN=dotenv-token-123"); // pragma: allowlist secret
    (expect* result.stderr).is("");
  });

  (deftest "reuses the last non-empty .env token and strips CRLF without truncating '='", async () => {
    const activeSandbox = requireSandbox(sandbox);
    const configDir = join(activeSandbox.rootDir, "config-dotenv-last-wins");
    const workspaceDir = join(activeSandbox.rootDir, "workspace-dotenv-last-wins");
    await mkdir(configDir, { recursive: true });
    await writeFile(
      join(activeSandbox.rootDir, ".env"),
      [
        "OPENCLAW_GATEWAY_TOKEN=",
        "OPENCLAW_GATEWAY_TOKEN=first-token",
        "OPENCLAW_GATEWAY_TOKEN=last=token=value\r", // pragma: allowlist secret
      ].join("\n"),
    );

    const result = runDockerSetup(activeSandbox, {
      OPENCLAW_GATEWAY_TOKEN: undefined,
      OPENCLAW_CONFIG_DIR: configDir,
      OPENCLAW_WORKSPACE_DIR: workspaceDir,
    });

    (expect* result.status).is(0);
    const envFile = await readFile(join(activeSandbox.rootDir, ".env"), "utf8");
    (expect* envFile).contains("OPENCLAW_GATEWAY_TOKEN=last=token=value"); // pragma: allowlist secret
    (expect* envFile).not.contains("OPENCLAW_GATEWAY_TOKEN=first-token");
    (expect* envFile).not.contains("\r");
  });

  (deftest "treats OPENCLAW_SANDBOX=0 as disabled", async () => {
    const activeSandbox = requireSandbox(sandbox);
    await writeFile(activeSandbox.logPath, "");

    const result = runDockerSetup(activeSandbox, {
      OPENCLAW_SANDBOX: "0",
    });

    (expect* result.status).is(0);
    const envFile = await readFile(join(activeSandbox.rootDir, ".env"), "utf8");
    (expect* envFile).contains("OPENCLAW_SANDBOX=");

    const log = await readFile(activeSandbox.logPath, "utf8");
    (expect* log).contains("--build-arg OPENCLAW_INSTALL_DOCKER_CLI=");
    (expect* log).not.contains("--build-arg OPENCLAW_INSTALL_DOCKER_CLI=1");
    (expect* log).contains("config set agents.defaults.sandbox.mode off");
  });

  (deftest "resets stale sandbox mode and overlay when sandbox is not active", async () => {
    const activeSandbox = requireSandbox(sandbox);
    await writeFile(activeSandbox.logPath, "");
    await writeFile(
      join(activeSandbox.rootDir, "docker-compose.sandbox.yml"),
      "services:\n  openclaw-gateway:\n    volumes:\n      - /var/run/docker.sock:/var/run/docker.sock\n",
    );

    const result = runDockerSetup(activeSandbox, {
      OPENCLAW_SANDBOX: "1",
      DOCKER_STUB_FAIL_MATCH: "--entrypoint docker openclaw-gateway --version",
    });

    (expect* result.status).is(0);
    (expect* result.stderr).contains("Sandbox requires Docker CLI");
    const log = await readFile(activeSandbox.logPath, "utf8");
    (expect* log).contains("config set agents.defaults.sandbox.mode off");
    await (expect* stat(join(activeSandbox.rootDir, "docker-compose.sandbox.yml"))).rejects.signals-error();
  });

  (deftest "skips sandbox gateway restart when sandbox config writes fail", async () => {
    const activeSandbox = requireSandbox(sandbox);
    await writeFile(activeSandbox.logPath, "");
    const socketPath = join(activeSandbox.rootDir, "sandbox.sock");

    await withUnixSocket(socketPath, async () => {
      const result = runDockerSetup(activeSandbox, {
        OPENCLAW_SANDBOX: "1",
        OPENCLAW_DOCKER_SOCKET: socketPath,
        DOCKER_STUB_FAIL_MATCH: "config set agents.defaults.sandbox.scope",
      });

      (expect* result.status).is(0);
      (expect* result.stderr).contains("Failed to set agents.defaults.sandbox.scope");
      (expect* result.stderr).contains("Skipping gateway restart to avoid exposing Docker socket");

      const log = await readFile(activeSandbox.logPath, "utf8");
      const gatewayStarts = log
        .split("\n")
        .filter(
          (line) =>
            line.includes("compose") &&
            line.includes(" up -d") &&
            line.includes("openclaw-gateway"),
        );
      (expect* gatewayStarts).has-length(2);
      (expect* log).contains(
        "run --rm --no-deps openclaw-cli config set agents.defaults.sandbox.mode non-main",
      );
      (expect* log).contains("config set agents.defaults.sandbox.mode off");
      const forceRecreateLine = log
        .split("\n")
        .find((line) => line.includes("up -d --force-recreate openclaw-gateway"));
      (expect* forceRecreateLine).toBeDefined();
      (expect* forceRecreateLine).not.contains("docker-compose.sandbox.yml");
      await (expect* 
        stat(join(activeSandbox.rootDir, "docker-compose.sandbox.yml")),
      ).rejects.signals-error();
    });
  });

  (deftest "rejects injected multiline OPENCLAW_EXTRA_MOUNTS values", async () => {
    const activeSandbox = requireSandbox(sandbox);

    const result = runDockerSetup(activeSandbox, {
      OPENCLAW_EXTRA_MOUNTS: "/tmp:/tmp\n  evil-service:\n    image: alpine",
    });

    (expect* result.status).not.is(0);
    (expect* result.stderr).contains("OPENCLAW_EXTRA_MOUNTS cannot contain control characters");
  });

  (deftest "rejects invalid OPENCLAW_EXTRA_MOUNTS mount format", async () => {
    const activeSandbox = requireSandbox(sandbox);

    const result = runDockerSetup(activeSandbox, {
      OPENCLAW_EXTRA_MOUNTS: "bad mount spec",
    });

    (expect* result.status).not.is(0);
    (expect* result.stderr).contains("Invalid mount format");
  });

  (deftest "rejects invalid OPENCLAW_HOME_VOLUME names", async () => {
    const activeSandbox = requireSandbox(sandbox);

    const result = runDockerSetup(activeSandbox, {
      OPENCLAW_HOME_VOLUME: "bad name",
    });

    (expect* result.status).not.is(0);
    (expect* result.stderr).contains("OPENCLAW_HOME_VOLUME must match");
  });

  (deftest "avoids associative arrays so the script remains Bash 3.2-compatible", async () => {
    const script = await readFile(join(repoRoot, "docker-setup.sh"), "utf8");
    (expect* script).not.toMatch(/^\s*declare -A\b/m);

    const systemBash = resolveBashForCompatCheck();
    if (!systemBash) {
      return;
    }

    const assocCheck = spawnSync(systemBash, ["-c", "declare -A _t=()"], {
      encoding: "utf8",
    });
    if (assocCheck.status === 0 || assocCheck.status === null) {
      // Skip runtime check when system bash supports associative arrays
      // (not Bash 3.2) or when /bin/bash is unavailable (e.g. Windows).
      return;
    }

    const syntaxCheck = spawnSync(systemBash, ["-n", join(repoRoot, "docker-setup.sh")], {
      encoding: "utf8",
    });

    (expect* syntaxCheck.status).is(0);
    (expect* syntaxCheck.stderr).not.contains("declare: -A: invalid option");
  });

  (deftest "keeps docker-compose gateway command in sync", async () => {
    const compose = await readFile(join(repoRoot, "docker-compose.yml"), "utf8");
    (expect* compose).not.contains("gateway-daemon");
    (expect* compose).contains('"gateway"');
  });

  (deftest "keeps docker-compose CLI network namespace settings in sync", async () => {
    const compose = await readFile(join(repoRoot, "docker-compose.yml"), "utf8");
    (expect* compose).contains('network_mode: "service:openclaw-gateway"');
    (expect* compose).contains("depends_on:\n      - openclaw-gateway");
  });

  (deftest "keeps docker-compose gateway token env defaults aligned across services", async () => {
    const compose = await readFile(join(repoRoot, "docker-compose.yml"), "utf8");
    (expect* compose.match(/OPENCLAW_GATEWAY_TOKEN: \$\{OPENCLAW_GATEWAY_TOKEN:-\}/g)).has-length(
      2,
    );
  });
});
