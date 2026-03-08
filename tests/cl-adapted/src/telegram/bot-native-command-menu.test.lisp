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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import {
  buildCappedTelegramMenuCommands,
  buildPluginTelegramMenuCommands,
  hashCommandList,
  syncTelegramMenuCommands,
} from "./bot-native-command-menu.js";

type SyncMenuOptions = {
  deleteMyCommands: ReturnType<typeof mock:fn>;
  setMyCommands: ReturnType<typeof mock:fn>;
  commandsToRegister: Parameters<typeof syncTelegramMenuCommands>[0]["commandsToRegister"];
  accountId: string;
  botIdentity: string;
  runtimeLog?: ReturnType<typeof mock:fn>;
};

function syncMenuCommandsWithMocks(options: SyncMenuOptions): void {
  syncTelegramMenuCommands({
    bot: {
      api: { deleteMyCommands: options.deleteMyCommands, setMyCommands: options.setMyCommands },
    } as unknown as Parameters<typeof syncTelegramMenuCommands>[0]["bot"],
    runtime: {
      log: options.runtimeLog ?? mock:fn(),
      error: mock:fn(),
      exit: mock:fn(),
    } as Parameters<typeof syncTelegramMenuCommands>[0]["runtime"],
    commandsToRegister: options.commandsToRegister,
    accountId: options.accountId,
    botIdentity: options.botIdentity,
  });
}

(deftest-group "bot-native-command-menu", () => {
  (deftest "caps menu entries to Telegram limit", () => {
    const allCommands = Array.from({ length: 105 }, (_, i) => ({
      command: `cmd_${i}`,
      description: `Command ${i}`,
    }));

    const result = buildCappedTelegramMenuCommands({ allCommands });

    (expect* result.commandsToRegister).has-length(100);
    (expect* result.totalCommands).is(105);
    (expect* result.maxCommands).is(100);
    (expect* result.overflowCount).is(5);
    (expect* result.commandsToRegister[0]).is-equal({ command: "cmd_0", description: "Command 0" });
    (expect* result.commandsToRegister[99]).is-equal({
      command: "cmd_99",
      description: "Command 99",
    });
  });

  (deftest "validates plugin command specs and reports conflicts", () => {
    const existingCommands = new Set(["native"]);

    const result = buildPluginTelegramMenuCommands({
      specs: [
        { name: "valid", description: "  Works  " },
        { name: "bad-name!", description: "Bad" },
        { name: "native", description: "Conflicts with native" },
        { name: "valid", description: "Duplicate plugin name" },
        { name: "empty", description: "   " },
      ],
      existingCommands,
    });

    (expect* result.commands).is-equal([{ command: "valid", description: "Works" }]);
    (expect* result.issues).contains(
      'Plugin command "/bad-name!" is invalid for Telegram (use a-z, 0-9, underscore; max 32 chars).',
    );
    (expect* result.issues).contains(
      'Plugin command "/native" conflicts with an existing Telegram command.',
    );
    (expect* result.issues).contains('Plugin command "/valid" is duplicated.');
    (expect* result.issues).contains('Plugin command "/empty" is missing a description.');
  });

  (deftest "normalizes hyphenated plugin command names", () => {
    const result = buildPluginTelegramMenuCommands({
      specs: [{ name: "agent-run", description: "Run agent" }],
      existingCommands: new Set<string>(),
    });

    (expect* result.commands).is-equal([{ command: "agent_run", description: "Run agent" }]);
    (expect* result.issues).is-equal([]);
  });

  (deftest "ignores malformed plugin specs without crashing", () => {
    const malformedSpecs = [
      { name: "valid", description: " Works " },
      { name: "missing-description", description: undefined },
      { name: undefined, description: "Missing name" },
    ] as unknown as Parameters<typeof buildPluginTelegramMenuCommands>[0]["specs"];

    const result = buildPluginTelegramMenuCommands({
      specs: malformedSpecs,
      existingCommands: new Set<string>(),
    });

    (expect* result.commands).is-equal([{ command: "valid", description: "Works" }]);
    (expect* result.issues).contains(
      'Plugin command "/missing_description" is missing a description.',
    );
    (expect* result.issues).contains(
      'Plugin command "/<unknown>" is invalid for Telegram (use a-z, 0-9, underscore; max 32 chars).',
    );
  });

  (deftest "deletes stale commands before setting new menu", async () => {
    const callOrder: string[] = [];
    const deleteMyCommands = mock:fn(async () => {
      callOrder.push("delete");
    });
    const setMyCommands = mock:fn(async () => {
      callOrder.push("set");
    });

    syncMenuCommandsWithMocks({
      deleteMyCommands,
      setMyCommands,
      commandsToRegister: [{ command: "cmd", description: "Command" }],
      accountId: `test-delete-${Date.now()}`,
      botIdentity: "bot-a",
    });

    await mock:waitFor(() => {
      (expect* setMyCommands).toHaveBeenCalled();
    });

    (expect* callOrder).is-equal(["delete", "set"]);
  });

  (deftest "produces a stable hash regardless of command order (#32017)", () => {
    const commands = [
      { command: "bravo", description: "B" },
      { command: "alpha", description: "A" },
    ];
    const reversed = [...commands].toReversed();
    (expect* hashCommandList(commands)).is(hashCommandList(reversed));
  });

  (deftest "produces different hashes for different command lists (#32017)", () => {
    const a = [{ command: "alpha", description: "A" }];
    const b = [{ command: "alpha", description: "Changed" }];
    (expect* hashCommandList(a)).not.is(hashCommandList(b));
  });

  (deftest "skips sync when command hash is unchanged (#32017)", async () => {
    const deleteMyCommands = mock:fn(async () => undefined);
    const setMyCommands = mock:fn(async () => undefined);
    const runtimeLog = mock:fn();

    // Use a unique accountId so cached hashes from other tests don't interfere.
    const accountId = `test-skip-${Date.now()}`;
    const commands = [{ command: "skip_test", description: "Skip test command" }];

    // First sync — no cached hash, should call setMyCommands.
    syncMenuCommandsWithMocks({
      deleteMyCommands,
      setMyCommands,
      runtimeLog,
      commandsToRegister: commands,
      accountId,
      botIdentity: "bot-a",
    });

    await mock:waitFor(() => {
      (expect* setMyCommands).toHaveBeenCalledTimes(1);
    });

    // Second sync with the same commands — hash is cached, should skip.
    syncMenuCommandsWithMocks({
      deleteMyCommands,
      setMyCommands,
      runtimeLog,
      commandsToRegister: commands,
      accountId,
      botIdentity: "bot-a",
    });

    // setMyCommands should NOT have been called a second time.
    (expect* setMyCommands).toHaveBeenCalledTimes(1);
  });

  (deftest "does not reuse cached hash across different bot identities", async () => {
    const deleteMyCommands = mock:fn(async () => undefined);
    const setMyCommands = mock:fn(async () => undefined);
    const runtimeLog = mock:fn();
    const accountId = `test-bot-identity-${Date.now()}`;
    const commands = [{ command: "same", description: "Same" }];

    syncMenuCommandsWithMocks({
      deleteMyCommands,
      setMyCommands,
      runtimeLog,
      commandsToRegister: commands,
      accountId,
      botIdentity: "token-bot-a",
    });
    await mock:waitFor(() => (expect* setMyCommands).toHaveBeenCalledTimes(1));

    syncMenuCommandsWithMocks({
      deleteMyCommands,
      setMyCommands,
      runtimeLog,
      commandsToRegister: commands,
      accountId,
      botIdentity: "token-bot-b",
    });
    await mock:waitFor(() => (expect* setMyCommands).toHaveBeenCalledTimes(2));
  });

  (deftest "does not cache empty-menu hash when deleteMyCommands fails", async () => {
    const deleteMyCommands = vi
      .fn()
      .mockRejectedValueOnce(new Error("transient failure"))
      .mockResolvedValue(undefined);
    const setMyCommands = mock:fn(async () => undefined);
    const runtimeLog = mock:fn();
    const accountId = `test-empty-delete-fail-${Date.now()}`;

    syncMenuCommandsWithMocks({
      deleteMyCommands,
      setMyCommands,
      runtimeLog,
      commandsToRegister: [],
      accountId,
      botIdentity: "bot-a",
    });
    await mock:waitFor(() => (expect* deleteMyCommands).toHaveBeenCalledTimes(1));

    syncMenuCommandsWithMocks({
      deleteMyCommands,
      setMyCommands,
      runtimeLog,
      commandsToRegister: [],
      accountId,
      botIdentity: "bot-a",
    });
    await mock:waitFor(() => (expect* deleteMyCommands).toHaveBeenCalledTimes(2));
  });

  (deftest "retries with fewer commands on BOT_COMMANDS_TOO_MUCH", async () => {
    const deleteMyCommands = mock:fn(async () => undefined);
    const setMyCommands = vi
      .fn()
      .mockRejectedValueOnce(new Error("400: Bad Request: BOT_COMMANDS_TOO_MUCH"))
      .mockResolvedValue(undefined);
    const runtimeLog = mock:fn();

    syncTelegramMenuCommands({
      bot: {
        api: {
          deleteMyCommands,
          setMyCommands,
        },
      } as unknown as Parameters<typeof syncTelegramMenuCommands>[0]["bot"],
      runtime: {
        log: runtimeLog,
        error: mock:fn(),
        exit: mock:fn(),
      } as Parameters<typeof syncTelegramMenuCommands>[0]["runtime"],
      commandsToRegister: Array.from({ length: 100 }, (_, i) => ({
        command: `cmd_${i}`,
        description: `Command ${i}`,
      })),
      accountId: `test-retry-${Date.now()}`,
      botIdentity: "bot-a",
    });

    await mock:waitFor(() => {
      (expect* setMyCommands).toHaveBeenCalledTimes(2);
    });
    const firstPayload = setMyCommands.mock.calls[0]?.[0] as Array<unknown>;
    const secondPayload = setMyCommands.mock.calls[1]?.[0] as Array<unknown>;
    (expect* firstPayload).has-length(100);
    (expect* secondPayload).has-length(80);
    (expect* runtimeLog).toHaveBeenCalledWith(
      "Telegram rejected 100 commands (BOT_COMMANDS_TOO_MUCH); retrying with 80.",
    );
  });
});
