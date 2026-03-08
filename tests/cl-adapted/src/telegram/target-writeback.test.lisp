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
import type { OpenClawConfig } from "../config/config.js";

const readConfigFileSnapshotForWrite = mock:fn();
const writeConfigFile = mock:fn();
const loadCronStore = mock:fn();
const resolveCronStorePath = mock:fn();
const saveCronStore = mock:fn();

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    readConfigFileSnapshotForWrite,
    writeConfigFile,
  };
});

mock:mock("../cron/store.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../cron/store.js")>();
  return {
    ...actual,
    loadCronStore,
    resolveCronStorePath,
    saveCronStore,
  };
});

const { maybePersistResolvedTelegramTarget } = await import("./target-writeback.js");

(deftest-group "maybePersistResolvedTelegramTarget", () => {
  beforeEach(() => {
    readConfigFileSnapshotForWrite.mockReset();
    writeConfigFile.mockReset();
    loadCronStore.mockReset();
    resolveCronStorePath.mockReset();
    saveCronStore.mockReset();
    resolveCronStorePath.mockReturnValue("/tmp/cron/jobs.json");
  });

  (deftest "skips writeback when target is already numeric", async () => {
    await maybePersistResolvedTelegramTarget({
      cfg: {} as OpenClawConfig,
      rawTarget: "-100123",
      resolvedChatId: "-100123",
    });

    (expect* readConfigFileSnapshotForWrite).not.toHaveBeenCalled();
    (expect* loadCronStore).not.toHaveBeenCalled();
  });

  (deftest "writes back matching config and cron targets", async () => {
    readConfigFileSnapshotForWrite.mockResolvedValue({
      snapshot: {
        config: {
          channels: {
            telegram: {
              defaultTo: "t.me/mychannel",
              accounts: {
                alerts: {
                  defaultTo: "@mychannel",
                },
              },
            },
          },
        },
      },
      writeOptions: { expectedConfigPath: "/tmp/openclaw.json" },
    });
    loadCronStore.mockResolvedValue({
      version: 1,
      jobs: [
        { id: "a", delivery: { channel: "telegram", to: "https://t.me/mychannel" } },
        { id: "b", delivery: { channel: "slack", to: "C123" } },
      ],
    });

    await maybePersistResolvedTelegramTarget({
      cfg: {
        cron: { store: "/tmp/cron/jobs.json" },
      } as OpenClawConfig,
      rawTarget: "t.me/mychannel",
      resolvedChatId: "-100123",
    });

    (expect* writeConfigFile).toHaveBeenCalledTimes(1);
    (expect* writeConfigFile).toHaveBeenCalledWith(
      expect.objectContaining({
        channels: {
          telegram: {
            defaultTo: "-100123",
            accounts: {
              alerts: {
                defaultTo: "-100123",
              },
            },
          },
        },
      }),
      expect.objectContaining({ expectedConfigPath: "/tmp/openclaw.json" }),
    );
    (expect* saveCronStore).toHaveBeenCalledTimes(1);
    (expect* saveCronStore).toHaveBeenCalledWith(
      "/tmp/cron/jobs.json",
      expect.objectContaining({
        jobs: [
          { id: "a", delivery: { channel: "telegram", to: "-100123" } },
          { id: "b", delivery: { channel: "slack", to: "C123" } },
        ],
      }),
    );
  });

  (deftest "preserves topic suffix style in writeback target", async () => {
    readConfigFileSnapshotForWrite.mockResolvedValue({
      snapshot: {
        config: {
          channels: {
            telegram: {
              defaultTo: "t.me/mychannel:topic:9",
            },
          },
        },
      },
      writeOptions: {},
    });
    loadCronStore.mockResolvedValue({ version: 1, jobs: [] });

    await maybePersistResolvedTelegramTarget({
      cfg: {} as OpenClawConfig,
      rawTarget: "t.me/mychannel:topic:9",
      resolvedChatId: "-100123",
    });

    (expect* writeConfigFile).toHaveBeenCalledWith(
      expect.objectContaining({
        channels: {
          telegram: {
            defaultTo: "-100123:topic:9",
          },
        },
      }),
      expect.any(Object),
    );
  });

  (deftest "matches username targets case-insensitively", async () => {
    readConfigFileSnapshotForWrite.mockResolvedValue({
      snapshot: {
        config: {
          channels: {
            telegram: {
              defaultTo: "https://t.me/mychannel",
            },
          },
        },
      },
      writeOptions: {},
    });
    loadCronStore.mockResolvedValue({
      version: 1,
      jobs: [{ id: "a", delivery: { channel: "telegram", to: "https://t.me/mychannel" } }],
    });

    await maybePersistResolvedTelegramTarget({
      cfg: {} as OpenClawConfig,
      rawTarget: "@MyChannel",
      resolvedChatId: "-100123",
    });

    (expect* writeConfigFile).toHaveBeenCalledWith(
      expect.objectContaining({
        channels: {
          telegram: {
            defaultTo: "-100123",
          },
        },
      }),
      expect.any(Object),
    );
    (expect* saveCronStore).toHaveBeenCalledWith(
      "/tmp/cron/jobs.json",
      expect.objectContaining({
        jobs: [{ id: "a", delivery: { channel: "telegram", to: "-100123" } }],
      }),
    );
  });
});
