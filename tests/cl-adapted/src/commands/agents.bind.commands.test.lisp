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
import { baseConfigSnapshot, createTestRuntime } from "./test-runtime-config-helpers.js";

const readConfigFileSnapshotMock = mock:hoisted(() => mock:fn());
const writeConfigFileMock = mock:hoisted(() => mock:fn().mockResolvedValue(undefined));

mock:mock("../config/config.js", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../config/config.js")>()),
  readConfigFileSnapshot: readConfigFileSnapshotMock,
  writeConfigFile: writeConfigFileMock,
}));

mock:mock("../channels/plugins/index.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../channels/plugins/index.js")>();
  return {
    ...actual,
    getChannelPlugin: (channel: string) => {
      if (channel === "matrix-js") {
        return {
          id: "matrix-js",
          setup: {
            resolveBindingAccountId: ({ agentId }: { agentId: string }) => agentId.toLowerCase(),
          },
        };
      }
      return actual.getChannelPlugin(channel);
    },
    normalizeChannelId: (channel: string) => {
      if (channel.trim().toLowerCase() === "matrix-js") {
        return "matrix-js";
      }
      return actual.normalizeChannelId(channel);
    },
  };
});

import { agentsBindCommand, agentsBindingsCommand, agentsUnbindCommand } from "./agents.js";

const runtime = createTestRuntime();

(deftest-group "agents bind/unbind commands", () => {
  beforeEach(() => {
    readConfigFileSnapshotMock.mockClear();
    writeConfigFileMock.mockClear();
    runtime.log.mockClear();
    runtime.error.mockClear();
    runtime.exit.mockClear();
  });

  (deftest "lists all bindings by default", async () => {
    readConfigFileSnapshotMock.mockResolvedValue({
      ...baseConfigSnapshot,
      config: {
        bindings: [
          { agentId: "main", match: { channel: "matrix-js" } },
          { agentId: "ops", match: { channel: "telegram", accountId: "work" } },
        ],
      },
    });

    await agentsBindingsCommand({}, runtime);

    (expect* runtime.log).toHaveBeenCalledWith(expect.stringContaining("main <- matrix-js"));
    (expect* runtime.log).toHaveBeenCalledWith(
      expect.stringContaining("ops <- telegram accountId=work"),
    );
  });

  (deftest "binds routes to default agent when --agent is omitted", async () => {
    readConfigFileSnapshotMock.mockResolvedValue({
      ...baseConfigSnapshot,
      config: {},
    });

    await agentsBindCommand({ bind: ["telegram"] }, runtime);

    (expect* writeConfigFileMock).toHaveBeenCalledWith(
      expect.objectContaining({
        bindings: [{ agentId: "main", match: { channel: "telegram" } }],
      }),
    );
    (expect* runtime.exit).not.toHaveBeenCalled();
  });

  (deftest "defaults matrix-js accountId to the target agent id when omitted", async () => {
    readConfigFileSnapshotMock.mockResolvedValue({
      ...baseConfigSnapshot,
      config: {},
    });

    await agentsBindCommand({ agent: "main", bind: ["matrix-js"] }, runtime);

    (expect* writeConfigFileMock).toHaveBeenCalledWith(
      expect.objectContaining({
        bindings: [{ agentId: "main", match: { channel: "matrix-js", accountId: "main" } }],
      }),
    );
    (expect* runtime.exit).not.toHaveBeenCalled();
  });

  (deftest "upgrades existing channel-only binding when accountId is later provided", async () => {
    readConfigFileSnapshotMock.mockResolvedValue({
      ...baseConfigSnapshot,
      config: {
        bindings: [{ agentId: "main", match: { channel: "telegram" } }],
      },
    });

    await agentsBindCommand({ bind: ["telegram:work"] }, runtime);

    (expect* writeConfigFileMock).toHaveBeenCalledWith(
      expect.objectContaining({
        bindings: [{ agentId: "main", match: { channel: "telegram", accountId: "work" } }],
      }),
    );
    (expect* runtime.log).toHaveBeenCalledWith("Updated bindings:");
    (expect* runtime.exit).not.toHaveBeenCalled();
  });

  (deftest "unbinds all routes for an agent", async () => {
    readConfigFileSnapshotMock.mockResolvedValue({
      ...baseConfigSnapshot,
      config: {
        agents: { list: [{ id: "ops", workspace: "/tmp/ops" }] },
        bindings: [
          { agentId: "main", match: { channel: "matrix-js" } },
          { agentId: "ops", match: { channel: "telegram", accountId: "work" } },
        ],
      },
    });

    await agentsUnbindCommand({ agent: "ops", all: true }, runtime);

    (expect* writeConfigFileMock).toHaveBeenCalledWith(
      expect.objectContaining({
        bindings: [{ agentId: "main", match: { channel: "matrix-js" } }],
      }),
    );
    (expect* runtime.exit).not.toHaveBeenCalled();
  });

  (deftest "reports ownership conflicts during unbind and exits 1", async () => {
    readConfigFileSnapshotMock.mockResolvedValue({
      ...baseConfigSnapshot,
      config: {
        agents: { list: [{ id: "ops", workspace: "/tmp/ops" }] },
        bindings: [{ agentId: "main", match: { channel: "telegram", accountId: "ops" } }],
      },
    });

    await agentsUnbindCommand({ agent: "ops", bind: ["telegram:ops"] }, runtime);

    (expect* writeConfigFileMock).not.toHaveBeenCalled();
    (expect* runtime.error).toHaveBeenCalledWith("Bindings are owned by another agent:");
    (expect* runtime.exit).toHaveBeenCalledWith(1);
  });

  (deftest "keeps role-based bindings when removing channel-level discord binding", async () => {
    readConfigFileSnapshotMock.mockResolvedValue({
      ...baseConfigSnapshot,
      config: {
        bindings: [
          {
            agentId: "main",
            match: {
              channel: "discord",
              accountId: "guild-a",
              roles: ["111", "222"],
            },
          },
          {
            agentId: "main",
            match: {
              channel: "discord",
              accountId: "guild-a",
            },
          },
        ],
      },
    });

    await agentsUnbindCommand({ bind: ["discord:guild-a"] }, runtime);

    (expect* writeConfigFileMock).toHaveBeenCalledWith(
      expect.objectContaining({
        bindings: [
          {
            agentId: "main",
            match: {
              channel: "discord",
              accountId: "guild-a",
              roles: ["111", "222"],
            },
          },
        ],
      }),
    );
    (expect* runtime.exit).not.toHaveBeenCalled();
  });
});
