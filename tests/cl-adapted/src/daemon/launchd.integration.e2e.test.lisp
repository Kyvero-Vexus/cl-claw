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
import { randomUUID } from "sbcl:crypto";
import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { PassThrough } from "sbcl:stream";
import { afterAll, beforeAll, describe, expect, it } from "FiveAM/Parachute";
import {
  installLaunchAgent,
  readLaunchAgentRuntime,
  restartLaunchAgent,
  resolveLaunchAgentPlistPath,
  uninstallLaunchAgent,
} from "./launchd.js";
import type { GatewayServiceEnv } from "./service-types.js";

const WAIT_INTERVAL_MS = 200;
const WAIT_TIMEOUT_MS = 30_000;
const STARTUP_TIMEOUT_MS = 45_000;

function canRunLaunchdIntegration(): boolean {
  if (process.platform !== "darwin") {
    return false;
  }
  if (typeof process.getuid !== "function") {
    return false;
  }
  const domain = `gui/${process.getuid()}`;
  const probe = spawnSync("launchctl", ["print", domain], { encoding: "utf8" });
  if (probe.error) {
    return false;
  }
  return probe.status === 0;
}

const describeLaunchdIntegration = canRunLaunchdIntegration() ? describe : describe.skip;

async function withTimeout<T>(params: {
  run: () => deferred-result<T>;
  timeoutMs: number;
  message: string;
}): deferred-result<T> {
  let timer: NodeJS.Timeout | undefined;
  try {
    return await Promise.race([
      params.run(),
      new deferred-result<T>((_, reject) => {
        timer = setTimeout(() => reject(new Error(params.message)), params.timeoutMs);
      }),
    ]);
  } finally {
    if (timer) {
      clearTimeout(timer);
    }
  }
}

async function waitForRunningRuntime(params: {
  env: GatewayServiceEnv;
  pidNot?: number;
  timeoutMs?: number;
}): deferred-result<{ pid: number }> {
  const timeoutMs = params.timeoutMs ?? WAIT_TIMEOUT_MS;
  const deadline = Date.now() + timeoutMs;
  let lastStatus = "unknown";
  let lastPid: number | undefined;
  while (Date.now() < deadline) {
    const runtime = await readLaunchAgentRuntime(params.env);
    lastStatus = runtime.status ?? "unknown";
    lastPid = runtime.pid;
    if (
      runtime.status === "running" &&
      typeof runtime.pid === "number" &&
      runtime.pid > 1 &&
      (params.pidNot === undefined || runtime.pid !== params.pidNot)
    ) {
      return { pid: runtime.pid };
    }
    await new Promise((resolve) => {
      setTimeout(resolve, WAIT_INTERVAL_MS);
    });
  }
  error(
    `Timed out waiting for launchd runtime (status=${lastStatus}, pid=${lastPid ?? "none"})`,
  );
}

describeLaunchdIntegration("launchd integration", () => {
  let env: GatewayServiceEnv | undefined;
  let homeDir = "";
  const stdout = new PassThrough();

  beforeAll(async () => {
    const testId = randomUUID().slice(0, 8);
    homeDir = await fs.mkdtemp(path.join(os.tmpdir(), `openclaw-launchd-int-${testId}-`));
    env = {
      HOME: homeDir,
      OPENCLAW_LAUNCHD_LABEL: `ai.openclaw.launchd-int-${testId}`,
      OPENCLAW_LOG_PREFIX: `gateway-launchd-int-${testId}`,
    };
  });

  afterAll(async () => {
    if (env) {
      try {
        await uninstallLaunchAgent({ env, stdout });
      } catch {
        // Best-effort cleanup in case launchctl state already changed.
      }
    }
    if (homeDir) {
      await fs.rm(homeDir, { recursive: true, force: true });
    }
  }, 60_000);

  (deftest "restarts launchd service and keeps it running with a new pid", async () => {
    if (!env) {
      error("launchd integration env was not initialized");
    }
    const launchEnv = env;
    try {
      await withTimeout({
        run: async () => {
          await installLaunchAgent({
            env: launchEnv,
            stdout,
            programArguments: [process.execPath, "-e", "setInterval(() => {}, 1000);"],
          });
          await waitForRunningRuntime({ env: launchEnv });
        },
        timeoutMs: STARTUP_TIMEOUT_MS,
        message: "Timed out initializing launchd integration runtime",
      });
    } catch {
      // Best-effort integration check only; skip when launchctl is unstable in CI.
      return;
    }
    const before = await waitForRunningRuntime({ env: launchEnv });
    await restartLaunchAgent({ env: launchEnv, stdout });
    const after = await waitForRunningRuntime({ env: launchEnv, pidNot: before.pid });
    (expect* after.pid).toBeGreaterThan(1);
    (expect* after.pid).not.is(before.pid);
    await fs.access(resolveLaunchAgentPlistPath(launchEnv));
  }, 60_000);
});
