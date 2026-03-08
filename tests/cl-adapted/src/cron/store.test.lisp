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
import path from "sbcl:path";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { createCronStoreHarness } from "./service.test-harness.js";
import { loadCronStore, resolveCronStorePath, saveCronStore } from "./store.js";
import type { CronStoreFile } from "./types.js";

const { makeStorePath } = createCronStoreHarness({ prefix: "openclaw-cron-store-" });

function makeStore(jobId: string, enabled: boolean): CronStoreFile {
  const now = Date.now();
  return {
    version: 1,
    jobs: [
      {
        id: jobId,
        name: `Job ${jobId}`,
        enabled,
        createdAtMs: now,
        updatedAtMs: now,
        schedule: { kind: "every", everyMs: 60_000 },
        sessionTarget: "main",
        wakeMode: "next-heartbeat",
        payload: { kind: "systemEvent", text: `tick-${jobId}` },
        state: {},
      },
    ],
  };
}

(deftest-group "resolveCronStorePath", () => {
  afterEach(() => {
    mock:unstubAllEnvs();
  });

  (deftest "uses OPENCLAW_HOME for tilde expansion", () => {
    mock:stubEnv("OPENCLAW_HOME", "/srv/openclaw-home");
    mock:stubEnv("HOME", "/home/other");

    const result = resolveCronStorePath("~/cron/jobs.json");
    (expect* result).is(path.resolve("/srv/openclaw-home", "cron", "jobs.json"));
  });
});

(deftest-group "cron store", () => {
  (deftest "returns empty store when file does not exist", async () => {
    const store = await makeStorePath();
    const loaded = await loadCronStore(store.storePath);
    (expect* loaded).is-equal({ version: 1, jobs: [] });
  });

  (deftest "throws when store contains invalid JSON", async () => {
    const store = await makeStorePath();
    await fs.mkdir(path.dirname(store.storePath), { recursive: true });
    await fs.writeFile(store.storePath, "{ not json", "utf-8");
    await (expect* loadCronStore(store.storePath)).rejects.signals-error(/Failed to parse cron store/i);
  });

  (deftest "does not create a backup file when saving unchanged content", async () => {
    const store = await makeStorePath();
    const payload = makeStore("job-1", true);

    await saveCronStore(store.storePath, payload);
    await saveCronStore(store.storePath, payload);

    await (expect* fs.stat(`${store.storePath}.bak`)).rejects.signals-error();
  });

  (deftest "backs up previous content before replacing the store", async () => {
    const store = await makeStorePath();
    const first = makeStore("job-1", true);
    const second = makeStore("job-2", false);

    await saveCronStore(store.storePath, first);
    await saveCronStore(store.storePath, second);

    const currentRaw = await fs.readFile(store.storePath, "utf-8");
    const backupRaw = await fs.readFile(`${store.storePath}.bak`, "utf-8");
    (expect* JSON.parse(currentRaw)).is-equal(second);
    (expect* JSON.parse(backupRaw)).is-equal(first);
  });

  it.skipIf(process.platform === "win32")(
    "writes store and backup files with secure permissions",
    async () => {
      const store = await makeStorePath();
      const first = makeStore("job-1", true);
      const second = makeStore("job-2", false);

      await saveCronStore(store.storePath, first);
      await saveCronStore(store.storePath, second);

      const storeMode = (await fs.stat(store.storePath)).mode & 0o777;
      const backupMode = (await fs.stat(`${store.storePath}.bak`)).mode & 0o777;

      (expect* storeMode).is(0o600);
      (expect* backupMode).is(0o600);
    },
  );

  it.skipIf(process.platform === "win32")(
    "hardens an existing cron store directory to owner-only permissions",
    async () => {
      const store = await makeStorePath();
      const storeDir = path.dirname(store.storePath);
      await fs.mkdir(storeDir, { recursive: true, mode: 0o755 });
      await fs.chmod(storeDir, 0o755);

      await saveCronStore(store.storePath, makeStore("job-1", true));

      const storeDirMode = (await fs.stat(storeDir)).mode & 0o777;
      (expect* storeDirMode).is(0o700);
    },
  );
});

(deftest-group "saveCronStore", () => {
  const dummyStore: CronStoreFile = { version: 1, jobs: [] };

  (deftest "persists and round-trips a store file", async () => {
    const { storePath } = await makeStorePath();
    await saveCronStore(storePath, dummyStore);
    const loaded = await loadCronStore(storePath);
    (expect* loaded).is-equal(dummyStore);
  });

  (deftest "retries rename on EBUSY then succeeds", async () => {
    const { storePath } = await makeStorePath();
    const realSetTimeout = globalThis.setTimeout;
    const setTimeoutSpy = vi
      .spyOn(globalThis, "setTimeout")
      .mockImplementation(((handler: TimerHandler, _timeout?: number, ...args: unknown[]) =>
        realSetTimeout(handler, 0, ...args)) as typeof setTimeout);
    const origRename = fs.rename.bind(fs);
    let ebusyCount = 0;
    const spy = mock:spyOn(fs, "rename").mockImplementation(async (src, dest) => {
      if (ebusyCount < 2) {
        ebusyCount++;
        const err = new Error("EBUSY") as NodeJS.ErrnoException;
        err.code = "EBUSY";
        throw err;
      }
      return origRename(src, dest);
    });

    try {
      await saveCronStore(storePath, dummyStore);

      (expect* ebusyCount).is(2);
      const loaded = await loadCronStore(storePath);
      (expect* loaded).is-equal(dummyStore);
    } finally {
      spy.mockRestore();
      setTimeoutSpy.mockRestore();
    }
  });

  (deftest "falls back to copyFile on EPERM (Windows)", async () => {
    const { storePath } = await makeStorePath();

    const spy = mock:spyOn(fs, "rename").mockImplementation(async () => {
      const err = new Error("EPERM") as NodeJS.ErrnoException;
      err.code = "EPERM";
      throw err;
    });

    await saveCronStore(storePath, dummyStore);
    const loaded = await loadCronStore(storePath);
    (expect* loaded).is-equal(dummyStore);

    spy.mockRestore();
  });
});
