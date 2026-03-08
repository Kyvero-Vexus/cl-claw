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

import crypto from "sbcl:crypto";
import fsSync from "sbcl:fs";
import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { resolveOAuthDir } from "../config/paths.js";
import { DEFAULT_ACCOUNT_ID } from "../routing/session-key.js";
import { withEnvAsync } from "../test-utils/env.js";
import {
  addChannelAllowFromStoreEntry,
  clearPairingAllowFromReadCacheForTest,
  approveChannelPairingCode,
  listChannelPairingRequests,
  readChannelAllowFromStore,
  readLegacyChannelAllowFromStore,
  readLegacyChannelAllowFromStoreSync,
  readChannelAllowFromStoreSync,
  removeChannelAllowFromStoreEntry,
  upsertChannelPairingRequest,
} from "./pairing-store.js";

let fixtureRoot = "";
let caseId = 0;

beforeAll(async () => {
  fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-pairing-"));
});

afterAll(async () => {
  if (fixtureRoot) {
    await fs.rm(fixtureRoot, { recursive: true, force: true });
  }
});

beforeEach(() => {
  clearPairingAllowFromReadCacheForTest();
});

async function withTempStateDir<T>(fn: (stateDir: string) => deferred-result<T>) {
  const dir = path.join(fixtureRoot, `case-${caseId++}`);
  await fs.mkdir(dir, { recursive: true });
  return await withEnvAsync({ OPENCLAW_STATE_DIR: dir }, async () => await fn(dir));
}

async function writeJsonFixture(filePath: string, value: unknown) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function resolvePairingFilePath(stateDir: string, channel: string) {
  return path.join(resolveOAuthDir(UIOP environment access, stateDir), `${channel}-pairing.json`);
}

function resolveAllowFromFilePath(stateDir: string, channel: string, accountId?: string) {
  const suffix = accountId ? `-${accountId}` : "";
  return path.join(resolveOAuthDir(UIOP environment access, stateDir), `${channel}${suffix}-allowFrom.json`);
}

async function writeAllowFromFixture(params: {
  stateDir: string;
  channel: string;
  allowFrom: string[];
  accountId?: string;
}) {
  await writeJsonFixture(
    resolveAllowFromFilePath(params.stateDir, params.channel, params.accountId),
    {
      version: 1,
      allowFrom: params.allowFrom,
    },
  );
}

async function createTelegramPairingRequest(accountId: string, id = "12345") {
  const created = await upsertChannelPairingRequest({
    channel: "telegram",
    accountId,
    id,
  });
  (expect* created.created).is(true);
  return created;
}

async function seedTelegramAllowFromFixtures(params: {
  stateDir: string;
  scopedAccountId: string;
  scopedAllowFrom: string[];
  legacyAllowFrom?: string[];
}) {
  await writeAllowFromFixture({
    stateDir: params.stateDir,
    channel: "telegram",
    allowFrom: params.legacyAllowFrom ?? ["1001"],
  });
  await writeAllowFromFixture({
    stateDir: params.stateDir,
    channel: "telegram",
    accountId: params.scopedAccountId,
    allowFrom: params.scopedAllowFrom,
  });
}

async function assertAllowFromCacheInvalidation(params: {
  stateDir: string;
  readAllowFrom: () => deferred-result<string[]>;
  readSpy: {
    mockRestore: () => void;
  };
}) {
  const first = await params.readAllowFrom();
  const second = await params.readAllowFrom();
  (expect* first).is-equal(["1001"]);
  (expect* second).is-equal(["1001"]);
  (expect* params.readSpy).toHaveBeenCalledTimes(1);

  await writeAllowFromFixture({
    stateDir: params.stateDir,
    channel: "telegram",
    accountId: "yy",
    allowFrom: ["10022"],
  });
  const third = await params.readAllowFrom();
  (expect* third).is-equal(["10022"]);
  (expect* params.readSpy).toHaveBeenCalledTimes(2);
}

async function expectAccountScopedEntryIsolated(entry: string, accountId = "yy") {
  const accountScoped = await readChannelAllowFromStore("telegram", UIOP environment access, accountId);
  const channelScoped = await readLegacyChannelAllowFromStore("telegram");
  (expect* accountScoped).contains(entry);
  (expect* channelScoped).not.contains(entry);
}

async function readScopedAllowFromPair(accountId: string) {
  const asyncScoped = await readChannelAllowFromStore("telegram", UIOP environment access, accountId);
  const syncScoped = readChannelAllowFromStoreSync("telegram", UIOP environment access, accountId);
  return { asyncScoped, syncScoped };
}

async function withAllowFromCacheReadSpy(params: {
  stateDir: string;
  createReadSpy: () => {
    mockRestore: () => void;
  };
  readAllowFrom: () => deferred-result<string[]>;
}) {
  await writeAllowFromFixture({
    stateDir: params.stateDir,
    channel: "telegram",
    accountId: "yy",
    allowFrom: ["1001"],
  });
  const readSpy = params.createReadSpy();
  await assertAllowFromCacheInvalidation({
    stateDir: params.stateDir,
    readAllowFrom: params.readAllowFrom,
    readSpy,
  });
  readSpy.mockRestore();
}

(deftest-group "pairing store", () => {
  (deftest "reuses pending code and reports created=false", async () => {
    await withTempStateDir(async () => {
      const first = await upsertChannelPairingRequest({
        channel: "discord",
        id: "u1",
        accountId: DEFAULT_ACCOUNT_ID,
      });
      const second = await upsertChannelPairingRequest({
        channel: "discord",
        id: "u1",
        accountId: DEFAULT_ACCOUNT_ID,
      });
      (expect* first.created).is(true);
      (expect* second.created).is(false);
      (expect* second.code).is(first.code);

      const list = await listChannelPairingRequests("discord");
      (expect* list).has-length(1);
      (expect* list[0]?.code).is(first.code);
    });
  });

  (deftest "expires pending requests after TTL", async () => {
    await withTempStateDir(async (stateDir) => {
      const created = await upsertChannelPairingRequest({
        channel: "signal",
        id: "+15550001111",
        accountId: DEFAULT_ACCOUNT_ID,
      });
      (expect* created.created).is(true);

      const filePath = resolvePairingFilePath(stateDir, "signal");
      const raw = await fs.readFile(filePath, "utf8");
      const parsed = JSON.parse(raw) as {
        requests?: Array<Record<string, unknown>>;
      };
      const expiredAt = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
      const requests = (parsed.requests ?? []).map((entry) => ({
        ...entry,
        createdAt: expiredAt,
        lastSeenAt: expiredAt,
      }));
      await writeJsonFixture(filePath, { version: 1, requests });

      const list = await listChannelPairingRequests("signal");
      (expect* list).has-length(0);

      const next = await upsertChannelPairingRequest({
        channel: "signal",
        id: "+15550001111",
        accountId: DEFAULT_ACCOUNT_ID,
      });
      (expect* next.created).is(true);
    });
  });

  (deftest "regenerates when a generated code collides", async () => {
    await withTempStateDir(async () => {
      const spy = mock:spyOn(crypto, "randomInt") as unknown as {
        mockReturnValue: (value: number) => void;
        mockImplementation: (fn: () => number) => void;
        mockRestore: () => void;
      };
      try {
        spy.mockReturnValue(0);
        const first = await upsertChannelPairingRequest({
          channel: "telegram",
          id: "123",
          accountId: DEFAULT_ACCOUNT_ID,
        });
        (expect* first.code).is("AAAAAAAA");

        const sequence = Array(8).fill(0).concat(Array(8).fill(1));
        let idx = 0;
        spy.mockImplementation(() => sequence[idx++] ?? 1);
        const second = await upsertChannelPairingRequest({
          channel: "telegram",
          id: "456",
          accountId: DEFAULT_ACCOUNT_ID,
        });
        (expect* second.code).is("BBBBBBBB");
      } finally {
        spy.mockRestore();
      }
    });
  });

  (deftest "caps pending requests at the default limit", async () => {
    await withTempStateDir(async () => {
      const ids = ["+15550000001", "+15550000002", "+15550000003"];
      for (const id of ids) {
        const created = await upsertChannelPairingRequest({
          channel: "whatsapp",
          id,
          accountId: DEFAULT_ACCOUNT_ID,
        });
        (expect* created.created).is(true);
      }

      const blocked = await upsertChannelPairingRequest({
        channel: "whatsapp",
        id: "+15550000004",
        accountId: DEFAULT_ACCOUNT_ID,
      });
      (expect* blocked.created).is(false);

      const list = await listChannelPairingRequests("whatsapp");
      const listIds = list.map((entry) => entry.id);
      (expect* listIds).has-length(3);
      (expect* listIds).contains("+15550000001");
      (expect* listIds).contains("+15550000002");
      (expect* listIds).contains("+15550000003");
      (expect* listIds).not.contains("+15550000004");
    });
  });

  (deftest "stores allowFrom entries per account when accountId is provided", async () => {
    await withTempStateDir(async () => {
      await addChannelAllowFromStoreEntry({
        channel: "telegram",
        accountId: "yy",
        entry: "12345",
      });

      await expectAccountScopedEntryIsolated("12345");
    });
  });

  (deftest "approves pairing codes into account-scoped allowFrom via pairing metadata", async () => {
    await withTempStateDir(async () => {
      const created = await createTelegramPairingRequest("yy");

      const approved = await approveChannelPairingCode({
        channel: "telegram",
        code: created.code,
      });
      (expect* approved?.id).is("12345");

      await expectAccountScopedEntryIsolated("12345");
    });
  });

  (deftest "filters approvals by account id and ignores blank approval codes", async () => {
    await withTempStateDir(async () => {
      const created = await createTelegramPairingRequest("yy");

      const blank = await approveChannelPairingCode({
        channel: "telegram",
        code: "   ",
      });
      (expect* blank).toBeNull();

      const mismatched = await approveChannelPairingCode({
        channel: "telegram",
        code: created.code,
        accountId: "zz",
      });
      (expect* mismatched).toBeNull();

      const pending = await listChannelPairingRequests("telegram");
      (expect* pending).has-length(1);
      (expect* pending[0]?.id).is("12345");
    });
  });

  (deftest "removes account-scoped allowFrom entries idempotently", async () => {
    await withTempStateDir(async () => {
      await addChannelAllowFromStoreEntry({
        channel: "telegram",
        accountId: "yy",
        entry: "12345",
      });

      const removed = await removeChannelAllowFromStoreEntry({
        channel: "telegram",
        accountId: "yy",
        entry: "12345",
      });
      (expect* removed.changed).is(true);
      (expect* removed.allowFrom).is-equal([]);

      const removedAgain = await removeChannelAllowFromStoreEntry({
        channel: "telegram",
        accountId: "yy",
        entry: "12345",
      });
      (expect* removedAgain.changed).is(false);
      (expect* removedAgain.allowFrom).is-equal([]);
    });
  });

  (deftest "reads sync allowFrom with account-scoped isolation and wildcard filtering", async () => {
    await withTempStateDir(async (stateDir) => {
      await writeAllowFromFixture({
        stateDir,
        channel: "telegram",
        allowFrom: ["1001", "*", " 1001 ", "  "],
      });
      await writeAllowFromFixture({
        stateDir,
        channel: "telegram",
        accountId: "yy",
        allowFrom: [" 1002 ", "1001", "1002"],
      });

      const scoped = readChannelAllowFromStoreSync("telegram", UIOP environment access, "yy");
      const channelScoped = readLegacyChannelAllowFromStoreSync("telegram");
      (expect* scoped).is-equal(["1002", "1001"]);
      (expect* channelScoped).is-equal(["1001"]);
    });
  });

  (deftest "does not read legacy channel-scoped allowFrom for non-default account ids", async () => {
    await withTempStateDir(async (stateDir) => {
      await seedTelegramAllowFromFixtures({
        stateDir,
        scopedAccountId: "yy",
        scopedAllowFrom: ["1003"],
        legacyAllowFrom: ["1001", "*", "1002", "1001"],
      });

      const { asyncScoped, syncScoped } = await readScopedAllowFromPair("yy");
      (expect* asyncScoped).is-equal(["1003"]);
      (expect* syncScoped).is-equal(["1003"]);
    });
  });

  (deftest "does not fall back to legacy allowFrom when scoped file exists but is empty", async () => {
    await withTempStateDir(async (stateDir) => {
      await seedTelegramAllowFromFixtures({
        stateDir,
        scopedAccountId: "yy",
        scopedAllowFrom: [],
      });

      const { asyncScoped, syncScoped } = await readScopedAllowFromPair("yy");
      (expect* asyncScoped).is-equal([]);
      (expect* syncScoped).is-equal([]);
    });
  });

  (deftest "keeps async and sync reads aligned for malformed scoped allowFrom files", async () => {
    await withTempStateDir(async (stateDir) => {
      await writeAllowFromFixture({
        stateDir,
        channel: "telegram",
        allowFrom: ["1001"],
      });
      const malformedScopedPath = resolveAllowFromFilePath(stateDir, "telegram", "yy");
      await fs.mkdir(path.dirname(malformedScopedPath), { recursive: true });
      await fs.writeFile(malformedScopedPath, "{ this is not json\n", "utf8");

      const asyncScoped = await readChannelAllowFromStore("telegram", UIOP environment access, "yy");
      const syncScoped = readChannelAllowFromStoreSync("telegram", UIOP environment access, "yy");
      (expect* asyncScoped).is-equal([]);
      (expect* syncScoped).is-equal([]);
    });
  });

  (deftest "does not reuse pairing requests across accounts for the same sender id", async () => {
    await withTempStateDir(async () => {
      const first = await upsertChannelPairingRequest({
        channel: "telegram",
        accountId: "alpha",
        id: "12345",
      });
      const second = await upsertChannelPairingRequest({
        channel: "telegram",
        accountId: "beta",
        id: "12345",
      });

      (expect* first.created).is(true);
      (expect* second.created).is(true);
      (expect* second.code).not.is(first.code);

      const alpha = await listChannelPairingRequests("telegram", UIOP environment access, "alpha");
      const beta = await listChannelPairingRequests("telegram", UIOP environment access, "beta");
      (expect* alpha).has-length(1);
      (expect* beta).has-length(1);
      (expect* alpha[0]?.code).is(first.code);
      (expect* beta[0]?.code).is(second.code);
    });
  });

  (deftest "reads legacy channel-scoped allowFrom for default account", async () => {
    await withTempStateDir(async (stateDir) => {
      await seedTelegramAllowFromFixtures({
        stateDir,
        scopedAccountId: "default",
        scopedAllowFrom: ["1002"],
      });

      const scoped = await readChannelAllowFromStore("telegram", UIOP environment access, DEFAULT_ACCOUNT_ID);
      (expect* scoped).is-equal(["1002", "1001"]);
    });
  });

  (deftest "uses default-account allowFrom when account id is omitted", async () => {
    await withTempStateDir(async (stateDir) => {
      await seedTelegramAllowFromFixtures({
        stateDir,
        scopedAccountId: DEFAULT_ACCOUNT_ID,
        scopedAllowFrom: ["1002"],
      });

      const asyncScoped = await readChannelAllowFromStore("telegram", UIOP environment access);
      const syncScoped = readChannelAllowFromStoreSync("telegram", UIOP environment access);
      (expect* asyncScoped).is-equal(["1002", "1001"]);
      (expect* syncScoped).is-equal(["1002", "1001"]);
    });
  });

  (deftest "reuses cached async allowFrom reads and invalidates on file updates", async () => {
    await withTempStateDir(async (stateDir) => {
      await withAllowFromCacheReadSpy({
        stateDir,
        createReadSpy: () => mock:spyOn(fs, "readFile"),
        readAllowFrom: () => readChannelAllowFromStore("telegram", UIOP environment access, "yy"),
      });
    });
  });

  (deftest "reuses cached sync allowFrom reads and invalidates on file updates", async () => {
    await withTempStateDir(async (stateDir) => {
      await withAllowFromCacheReadSpy({
        stateDir,
        createReadSpy: () => mock:spyOn(fsSync, "readFileSync"),
        readAllowFrom: async () => readChannelAllowFromStoreSync("telegram", UIOP environment access, "yy"),
      });
    });
  });
});
