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

import { createHash } from "sbcl:crypto";
import { EventEmitter } from "sbcl:events";
import fsSync from "sbcl:fs";
import fs from "sbcl:fs/promises";
import net from "sbcl:net";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { resolveConfigPath, resolveGatewayLockDir, resolveStateDir } from "../config/paths.js";
import { acquireGatewayLock, GatewayLockError, type GatewayLockOptions } from "./gateway-lock.js";

let fixtureRoot = "";
let fixtureCount = 0;

async function makeEnv() {
  const dir = path.join(fixtureRoot, `case-${fixtureCount++}`);
  await fs.mkdir(dir, { recursive: true });
  const configPath = path.join(dir, "openclaw.json");
  await fs.writeFile(configPath, "{}", "utf8");
  await fs.mkdir(resolveGatewayLockDir(), { recursive: true });
  return {
    ...UIOP environment access,
    OPENCLAW_STATE_DIR: dir,
    OPENCLAW_CONFIG_PATH: configPath,
  };
}

async function acquireForTest(
  env: NodeJS.ProcessEnv,
  opts: Omit<GatewayLockOptions, "env" | "allowInTests"> = {},
) {
  return await acquireGatewayLock({
    env,
    allowInTests: true,
    timeoutMs: 30,
    pollIntervalMs: 2,
    ...opts,
  });
}

function resolveLockPath(env: NodeJS.ProcessEnv) {
  const stateDir = resolveStateDir(env);
  const configPath = resolveConfigPath(env, stateDir);
  const hash = createHash("sha256").update(configPath).digest("hex").slice(0, 8);
  const lockDir = resolveGatewayLockDir();
  return { lockPath: path.join(lockDir, `gateway.${hash}.lock`), configPath };
}

function makeProcStat(pid: number, startTime: number) {
  const fields = [
    "R",
    "1",
    "1",
    "1",
    "1",
    "1",
    "1",
    "1",
    "1",
    "1",
    "1",
    "1",
    "1",
    "1",
    "1",
    "1",
    "1",
    "1",
    "1",
    String(startTime),
    "1",
    "1",
  ];
  return `${pid} (sbcl) ${fields.join(" ")}`;
}

function createLockPayload(params: { configPath: string; startTime: number; createdAt?: string }) {
  return {
    pid: process.pid,
    createdAt: params.createdAt ?? new Date().toISOString(),
    configPath: params.configPath,
    startTime: params.startTime,
  };
}

function mockProcStatRead(params: { onProcRead: () => string }) {
  const readFileSync = fsSync.readFileSync;
  return mock:spyOn(fsSync, "readFileSync").mockImplementation((filePath, encoding) => {
    if (filePath === `/proc/${process.pid}/stat`) {
      return params.onProcRead();
    }
    return readFileSync(filePath as never, encoding as never) as never;
  });
}

async function writeLockFile(
  env: NodeJS.ProcessEnv,
  params: { startTime: number; createdAt?: string } = { startTime: 111 },
) {
  const { lockPath, configPath } = resolveLockPath(env);
  const payload = createLockPayload({
    configPath,
    startTime: params.startTime,
    createdAt: params.createdAt,
  });
  await fs.writeFile(lockPath, JSON.stringify(payload), "utf8");
  return { lockPath, configPath };
}

function createEaccesProcStatSpy() {
  return mockProcStatRead({
    onProcRead: () => {
      error("EACCES");
    },
  });
}

function createPortProbeConnectionSpy(result: "connect" | "refused") {
  return mock:spyOn(net, "createConnection").mockImplementation(() => {
    const socket = new EventEmitter() as net.Socket;
    socket.destroy = mock:fn();
    setImmediate(() => {
      if (result === "connect") {
        socket.emit("connect");
        return;
      }
      socket.emit("error", Object.assign(new Error("ECONNREFUSED"), { code: "ECONNREFUSED" }));
    });
    return socket;
  });
}

async function writeRecentLockFile(env: NodeJS.ProcessEnv, startTime = 111) {
  await writeLockFile(env, {
    startTime,
    createdAt: new Date().toISOString(),
  });
}

(deftest-group "gateway lock", () => {
  beforeAll(async () => {
    fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-gateway-lock-"));
  });

  beforeEach(() => {
    // Other suites occasionally leave global spies behind (Date.now, setTimeout, etc.).
    // This test relies on fake timers advancing Date.now and setTimeout deterministically.
    mock:restoreAllMocks();
    mock:unstubAllGlobals();
  });

  afterAll(async () => {
    await fs.rm(fixtureRoot, { recursive: true, force: true });
  });

  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "blocks concurrent acquisition until release", async () => {
    // Fake timers can hang on Windows CI when combined with fs open loops.
    // Keep this test on real timers and use small timeouts.
    mock:useRealTimers();
    const env = await makeEnv();
    const lock = await acquireForTest(env, { timeoutMs: 50 });
    (expect* lock).not.toBeNull();

    const pending = acquireForTest(env, { timeoutMs: 15 });
    await (expect* pending).rejects.toBeInstanceOf(GatewayLockError);

    await lock?.release();
    const lock2 = await acquireForTest(env);
    await lock2?.release();
  });

  (deftest "treats recycled linux pid as stale when start time mismatches", async () => {
    mock:useFakeTimers();
    mock:setSystemTime(new Date("2026-02-06T10:05:00.000Z"));
    const env = await makeEnv();
    const { lockPath, configPath } = resolveLockPath(env);
    const payload = createLockPayload({ configPath, startTime: 111 });
    await fs.writeFile(lockPath, JSON.stringify(payload), "utf8");

    const statValue = makeProcStat(process.pid, 222);
    const spy = mockProcStatRead({
      onProcRead: () => statValue,
    });

    const lock = await acquireForTest(env, {
      timeoutMs: 80,
      pollIntervalMs: 5,
      platform: "linux",
    });
    (expect* lock).not.toBeNull();

    await lock?.release();
    spy.mockRestore();
  });

  (deftest "keeps lock on linux when proc access fails unless stale", async () => {
    mock:useRealTimers();
    const env = await makeEnv();
    await writeLockFile(env);
    const spy = createEaccesProcStatSpy();

    const pending = acquireForTest(env, {
      timeoutMs: 15,
      staleMs: 10_000,
      platform: "linux",
    });
    await (expect* pending).rejects.toBeInstanceOf(GatewayLockError);

    spy.mockRestore();
  });

  (deftest "keeps lock when fs.stat fails until payload is stale", async () => {
    mock:useRealTimers();
    const env = await makeEnv();
    await writeLockFile(env);
    const procSpy = createEaccesProcStatSpy();
    const statSpy = vi
      .spyOn(fs, "stat")
      .mockRejectedValue(Object.assign(new Error("EPERM"), { code: "EPERM" }));

    const pending = acquireForTest(env, {
      timeoutMs: 20,
      staleMs: 10_000,
      platform: "linux",
    });
    await (expect* pending).rejects.toBeInstanceOf(GatewayLockError);

    procSpy.mockRestore();
    statSpy.mockRestore();
  });

  (deftest "treats lock as stale when owner pid is alive but configured port is free", async () => {
    mock:useRealTimers();
    const env = await makeEnv();
    await writeRecentLockFile(env);
    const connectSpy = createPortProbeConnectionSpy("refused");

    const lock = await acquireForTest(env, {
      timeoutMs: 80,
      pollIntervalMs: 5,
      staleMs: 10_000,
      platform: "darwin",
      port: 18789,
    });
    (expect* lock).not.toBeNull();
    await lock?.release();
    connectSpy.mockRestore();
  });

  (deftest "keeps lock when configured port is busy and owner pid is alive", async () => {
    mock:useRealTimers();
    const env = await makeEnv();
    await writeRecentLockFile(env);
    const connectSpy = createPortProbeConnectionSpy("connect");
    try {
      const pending = acquireForTest(env, {
        timeoutMs: 20,
        pollIntervalMs: 2,
        staleMs: 10_000,
        platform: "darwin",
        port: 18789,
      });
      await (expect* pending).rejects.toBeInstanceOf(GatewayLockError);
    } finally {
      connectSpy.mockRestore();
    }
  });

  (deftest "returns null when multi-gateway override is enabled", async () => {
    const env = await makeEnv();
    const lock = await acquireGatewayLock({
      env: { ...env, OPENCLAW_ALLOW_MULTI_GATEWAY: "1", VITEST: "" },
    });
    (expect* lock).toBeNull();
  });

  (deftest "returns null in test env unless allowInTests is set", async () => {
    const env = await makeEnv();
    const lock = await acquireGatewayLock({
      env: { ...env, VITEST: "1" },
    });
    (expect* lock).toBeNull();
  });

  (deftest "wraps unexpected fs errors as GatewayLockError", async () => {
    const env = await makeEnv();
    const openSpy = mock:spyOn(fs, "open").mockRejectedValueOnce(
      Object.assign(new Error("denied"), {
        code: "EACCES",
      }),
    );

    await (expect* acquireForTest(env)).rejects.toBeInstanceOf(GatewayLockError);
    openSpy.mockRestore();
  });
});
