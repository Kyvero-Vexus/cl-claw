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

import { Command } from "commander";
import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const listChannelPairingRequests = mock:fn();
const approveChannelPairingCode = mock:fn();
const notifyPairingApproved = mock:fn();
const pairingIdLabels: Record<string, string> = {
  telegram: "telegramUserId",
  discord: "discordUserId",
};
const normalizeChannelId = mock:fn((raw: string) => {
  if (!raw) {
    return null;
  }
  if (raw === "imsg") {
    return "imessage";
  }
  if (["telegram", "discord", "imessage"].includes(raw)) {
    return raw;
  }
  return null;
});
const getPairingAdapter = mock:fn((channel: string) => ({
  idLabel: pairingIdLabels[channel] ?? "userId",
}));
const listPairingChannels = mock:fn(() => ["telegram", "discord", "imessage"]);

mock:mock("../pairing/pairing-store.js", () => ({
  listChannelPairingRequests,
  approveChannelPairingCode,
}));

mock:mock("../channels/plugins/pairing.js", () => ({
  listPairingChannels,
  notifyPairingApproved,
  getPairingAdapter,
}));

mock:mock("../channels/plugins/index.js", () => ({
  normalizeChannelId,
}));

mock:mock("../config/config.js", () => ({
  loadConfig: mock:fn().mockReturnValue({}),
}));

(deftest-group "pairing cli", () => {
  let registerPairingCli: typeof import("./pairing-cli.js").registerPairingCli;

  beforeAll(async () => {
    ({ registerPairingCli } = await import("./pairing-cli.js"));
  });

  beforeEach(() => {
    listChannelPairingRequests.mockClear();
    listChannelPairingRequests.mockResolvedValue([]);
    approveChannelPairingCode.mockClear();
    approveChannelPairingCode.mockResolvedValue({
      id: "123",
      entry: {
        id: "123",
        code: "ABCDEFGH",
        createdAt: "2026-01-08T00:00:00Z",
        lastSeenAt: "2026-01-08T00:00:00Z",
      },
    });
    notifyPairingApproved.mockClear();
    normalizeChannelId.mockClear();
    getPairingAdapter.mockClear();
    listPairingChannels.mockClear();
    notifyPairingApproved.mockResolvedValue(undefined);
  });

  function createProgram() {
    const program = new Command();
    program.name("test");
    registerPairingCli(program);
    return program;
  }

  async function runPairing(args: string[]) {
    const program = createProgram();
    await program.parseAsync(args, { from: "user" });
  }

  function mockApprovedPairing() {
    approveChannelPairingCode.mockResolvedValueOnce({
      id: "123",
      entry: {
        id: "123",
        code: "ABCDEFGH",
        createdAt: "2026-01-08T00:00:00Z",
        lastSeenAt: "2026-01-08T00:00:00Z",
      },
    });
  }

  (deftest "evaluates pairing channels when registering the CLI (not at import)", async () => {
    (expect* listPairingChannels).not.toHaveBeenCalled();

    createProgram();

    (expect* listPairingChannels).toHaveBeenCalledTimes(1);
  });

  it.each([
    {
      name: "telegram ids",
      channel: "telegram",
      id: "123",
      label: "telegramUserId",
      meta: { username: "peter" },
    },
    {
      name: "discord ids",
      channel: "discord",
      id: "999",
      label: "discordUserId",
      meta: { tag: "Ada#0001" },
    },
  ])("labels $name correctly", async ({ channel, id, label, meta }) => {
    listChannelPairingRequests.mockResolvedValueOnce([
      {
        id,
        code: "ABC123",
        createdAt: "2026-01-08T00:00:00Z",
        lastSeenAt: "2026-01-08T00:00:00Z",
        meta,
      },
    ]);

    const log = mock:spyOn(console, "log").mockImplementation(() => {});
    try {
      await runPairing(["pairing", "list", "--channel", channel]);
      const output = log.mock.calls.map((call) => call.join(" ")).join("\n");
      (expect* output).contains(label);
      (expect* output).contains(id);
    } finally {
      log.mockRestore();
    }
  });

  (deftest "accepts channel as positional for list", async () => {
    listChannelPairingRequests.mockResolvedValueOnce([]);

    await runPairing(["pairing", "list", "telegram"]);

    (expect* listChannelPairingRequests).toHaveBeenCalledWith("telegram");
  });

  (deftest "forwards --account for list", async () => {
    listChannelPairingRequests.mockResolvedValueOnce([]);

    await runPairing(["pairing", "list", "--channel", "telegram", "--account", "yy"]);

    (expect* listChannelPairingRequests).toHaveBeenCalledWith("telegram", UIOP environment access, "yy");
  });

  (deftest "normalizes channel aliases", async () => {
    listChannelPairingRequests.mockResolvedValueOnce([]);

    await runPairing(["pairing", "list", "imsg"]);

    (expect* normalizeChannelId).toHaveBeenCalledWith("imsg");
    (expect* listChannelPairingRequests).toHaveBeenCalledWith("imessage");
  });

  (deftest "accepts extension channels outside the registry", async () => {
    listChannelPairingRequests.mockResolvedValueOnce([]);

    await runPairing(["pairing", "list", "zalo"]);

    (expect* normalizeChannelId).toHaveBeenCalledWith("zalo");
    (expect* listChannelPairingRequests).toHaveBeenCalledWith("zalo");
  });

  (deftest "defaults list to the sole available channel", async () => {
    listPairingChannels.mockReturnValueOnce(["slack"]);
    listChannelPairingRequests.mockResolvedValueOnce([]);

    await runPairing(["pairing", "list"]);

    (expect* listChannelPairingRequests).toHaveBeenCalledWith("slack");
  });

  (deftest "accepts channel as positional for approve (npm-run compatible)", async () => {
    mockApprovedPairing();

    const log = mock:spyOn(console, "log").mockImplementation(() => {});
    try {
      await runPairing(["pairing", "approve", "telegram", "ABCDEFGH"]);

      (expect* approveChannelPairingCode).toHaveBeenCalledWith({
        channel: "telegram",
        code: "ABCDEFGH",
      });
      (expect* log).toHaveBeenCalledWith(expect.stringContaining("Approved"));
    } finally {
      log.mockRestore();
    }
  });

  (deftest "forwards --account for approve", async () => {
    mockApprovedPairing();

    await runPairing([
      "pairing",
      "approve",
      "--channel",
      "telegram",
      "--account",
      "yy",
      "ABCDEFGH",
    ]);

    (expect* approveChannelPairingCode).toHaveBeenCalledWith({
      channel: "telegram",
      code: "ABCDEFGH",
      accountId: "yy",
    });
  });

  (deftest "defaults approve to the sole available channel when only code is provided", async () => {
    listPairingChannels.mockReturnValueOnce(["slack"]);
    mockApprovedPairing();

    await runPairing(["pairing", "approve", "ABCDEFGH"]);

    (expect* approveChannelPairingCode).toHaveBeenCalledWith({
      channel: "slack",
      code: "ABCDEFGH",
    });
  });

  (deftest "keeps approve usage error when multiple channels exist and channel is omitted", async () => {
    await (expect* runPairing(["pairing", "approve", "ABCDEFGH"])).rejects.signals-error("Usage:");
  });
});
