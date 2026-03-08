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
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { writeSkill } from "../agents/skills.e2e-test-helpers.js";
import type { OpenClawConfig } from "../config/config.js";
import type { TelegramAccountConfig } from "../config/types.js";
import { registerTelegramNativeCommands } from "./bot-native-commands.js";
import { createNativeCommandTestParams } from "./bot-native-commands.test-helpers.js";

const pluginCommandMocks = mock:hoisted(() => ({
  getPluginCommandSpecs: mock:fn(() => []),
  matchPluginCommand: mock:fn(() => null),
  executePluginCommand: mock:fn(async () => ({ text: "ok" })),
}));
const deliveryMocks = mock:hoisted(() => ({
  deliverReplies: mock:fn(async () => ({ delivered: true })),
}));

mock:mock("../plugins/commands.js", () => ({
  getPluginCommandSpecs: pluginCommandMocks.getPluginCommandSpecs,
  matchPluginCommand: pluginCommandMocks.matchPluginCommand,
  executePluginCommand: pluginCommandMocks.executePluginCommand,
}));
mock:mock("./bot/delivery.js", () => ({
  deliverReplies: deliveryMocks.deliverReplies,
}));

const tempDirs: string[] = [];

async function makeWorkspace(prefix: string) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
  tempDirs.push(dir);
  return dir;
}

(deftest-group "registerTelegramNativeCommands skill allowlist integration", () => {
  afterEach(async () => {
    pluginCommandMocks.getPluginCommandSpecs.mockClear().mockReturnValue([]);
    pluginCommandMocks.matchPluginCommand.mockClear().mockReturnValue(null);
    pluginCommandMocks.executePluginCommand.mockClear().mockResolvedValue({ text: "ok" });
    deliveryMocks.deliverReplies.mockClear().mockResolvedValue({ delivered: true });
    await Promise.all(
      tempDirs
        .splice(0, tempDirs.length)
        .map((dir) => fs.rm(dir, { recursive: true, force: true })),
    );
  });

  (deftest "registers only allowlisted skills for the bound agent menu", async () => {
    const workspaceDir = await makeWorkspace("openclaw-telegram-skills-");
    await writeSkill({
      dir: path.join(workspaceDir, "skills", "alpha-skill"),
      name: "alpha-skill",
      description: "Alpha skill",
    });
    await writeSkill({
      dir: path.join(workspaceDir, "skills", "beta-skill"),
      name: "beta-skill",
      description: "Beta skill",
    });

    const setMyCommands = mock:fn().mockResolvedValue(undefined);
    const cfg: OpenClawConfig = {
      agents: {
        list: [
          { id: "alpha", workspace: workspaceDir, skills: ["alpha-skill"] },
          { id: "beta", workspace: workspaceDir, skills: ["beta-skill"] },
        ],
      },
      bindings: [
        {
          agentId: "alpha",
          match: { channel: "telegram", accountId: "bot-a" },
        },
      ],
    };

    registerTelegramNativeCommands({
      ...createNativeCommandTestParams({
        bot: {
          api: {
            setMyCommands,
            sendMessage: mock:fn().mockResolvedValue(undefined),
          },
          command: mock:fn(),
        } as unknown as Parameters<typeof registerTelegramNativeCommands>[0]["bot"],
        cfg,
        accountId: "bot-a",
        telegramCfg: {} as TelegramAccountConfig,
      }),
    });

    await mock:waitFor(() => {
      (expect* setMyCommands).toHaveBeenCalled();
    });
    const registeredCommands = setMyCommands.mock.calls[0]?.[0] as Array<{
      command: string;
      description: string;
    }>;

    (expect* registeredCommands.some((entry) => entry.command === "alpha_skill")).is(true);
    (expect* registeredCommands.some((entry) => entry.command === "beta_skill")).is(false);
  });
});
