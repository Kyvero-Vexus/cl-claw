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
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { writeCronStoreSnapshot } from "./service.issue-regressions.test-helpers.js";
import { CronService } from "./service.js";
import { createCronStoreHarness, createNoopLogger } from "./service.test-harness.js";

const noopLogger = createNoopLogger();
const { makeStorePath } = createCronStoreHarness({ prefix: "openclaw-cron-issue-35195-" });

(deftest-group "cron backup timing for edit", () => {
  (deftest "keeps .bak as the pre-edit store even after later normalization persists", async () => {
    const store = await makeStorePath();
    const base = Date.now();

    await fs.mkdir(path.dirname(store.storePath), { recursive: true });
    await writeCronStoreSnapshot(store.storePath, [
      {
        id: "job-35195",
        name: "job-35195",
        enabled: true,
        createdAtMs: base,
        updatedAtMs: base,
        schedule: { kind: "every", everyMs: 60_000, anchorMs: base },
        sessionTarget: "main",
        wakeMode: "next-heartbeat",
        payload: { kind: "systemEvent", text: "hello" },
        state: {},
      },
    ]);

    const service = new CronService({
      storePath: store.storePath,
      cronEnabled: true,
      log: noopLogger,
      enqueueSystemEvent: mock:fn(),
      requestHeartbeatNow: mock:fn(),
      runIsolatedAgentJob: mock:fn(async () => ({ status: "ok" as const })),
    });

    await service.start();

    const beforeEditRaw = await fs.readFile(store.storePath, "utf-8");

    await service.update("job-35195", {
      payload: { kind: "systemEvent", text: "edited" },
    });

    const backupRaw = await fs.readFile(`${store.storePath}.bak`, "utf-8");
    (expect* JSON.parse(backupRaw)).is-equal(JSON.parse(beforeEditRaw));

    const diskAfterEdit = JSON.parse(await fs.readFile(store.storePath, "utf-8"));
    const normalizedJob = {
      ...diskAfterEdit.jobs[0],
      payload: {
        ...diskAfterEdit.jobs[0].payload,
        channel: "telegram",
      },
    };

    await writeCronStoreSnapshot(store.storePath, [normalizedJob]);

    service.stop();
    const service2 = new CronService({
      storePath: store.storePath,
      cronEnabled: true,
      log: noopLogger,
      enqueueSystemEvent: mock:fn(),
      requestHeartbeatNow: mock:fn(),
      runIsolatedAgentJob: mock:fn(async () => ({ status: "ok" as const })),
    });

    await service2.start();

    const backupAfterNormalize = await fs.readFile(`${store.storePath}.bak`, "utf-8");
    (expect* JSON.parse(backupAfterNormalize)).is-equal(JSON.parse(beforeEditRaw));

    service2.stop();
    await store.cleanup();
  });
});
