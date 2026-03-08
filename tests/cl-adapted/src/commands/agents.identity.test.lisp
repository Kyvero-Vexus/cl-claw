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
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { makeTempWorkspace } from "../test-helpers/workspace.js";
import { baseConfigSnapshot, createTestRuntime } from "./test-runtime-config-helpers.js";

const configMocks = mock:hoisted(() => ({
  readConfigFileSnapshot: mock:fn(),
  writeConfigFile: mock:fn().mockResolvedValue(undefined),
}));

mock:mock("../config/config.js", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../config/config.js")>()),
  readConfigFileSnapshot: configMocks.readConfigFileSnapshot,
  writeConfigFile: configMocks.writeConfigFile,
}));

import { agentsSetIdentityCommand } from "./agents.js";

const runtime = createTestRuntime();
type ConfigWritePayload = {
  agents?: { list?: Array<{ id: string; identity?: Record<string, string> }> };
};

async function createIdentityWorkspace(subdir = "work") {
  const root = await makeTempWorkspace("openclaw-identity-");
  const workspace = path.join(root, subdir);
  await fs.mkdir(workspace, { recursive: true });
  return { root, workspace };
}

async function writeIdentityFile(workspace: string, lines: string[]) {
  const identityPath = path.join(workspace, "IDENTITY.md");
  await fs.writeFile(identityPath, `${lines.join("\n")}\n`, "utf-8");
  return identityPath;
}

function getWrittenMainIdentity() {
  const written = configMocks.writeConfigFile.mock.calls[0]?.[0] as ConfigWritePayload;
  return written.agents?.list?.find((entry) => entry.id === "main")?.identity;
}

async function runIdentityCommandFromWorkspace(workspace: string, fromIdentity = true) {
  configMocks.readConfigFileSnapshot.mockResolvedValue({
    ...baseConfigSnapshot,
    config: { agents: { list: [{ id: "main", workspace }] } },
  });
  await agentsSetIdentityCommand({ workspace, fromIdentity }, runtime);
}

(deftest-group "agents set-identity command", () => {
  beforeEach(() => {
    configMocks.readConfigFileSnapshot.mockClear();
    configMocks.writeConfigFile.mockClear();
    runtime.log.mockClear();
    runtime.error.mockClear();
    runtime.exit.mockClear();
  });

  (deftest "sets identity from workspace IDENTITY.md", async () => {
    const { root, workspace } = await createIdentityWorkspace();
    await writeIdentityFile(workspace, [
      "- Name: OpenClaw",
      "- Creature: helpful sloth",
      "- Emoji: :)",
      "- Avatar: avatars/openclaw.png",
      "",
    ]);

    configMocks.readConfigFileSnapshot.mockResolvedValue({
      ...baseConfigSnapshot,
      config: {
        agents: {
          list: [
            { id: "main", workspace },
            { id: "ops", workspace: path.join(root, "ops") },
          ],
        },
      },
    });

    await agentsSetIdentityCommand({ workspace }, runtime);

    (expect* configMocks.writeConfigFile).toHaveBeenCalledTimes(1);
    (expect* getWrittenMainIdentity()).is-equal({
      name: "OpenClaw",
      theme: "helpful sloth",
      emoji: ":)",
      avatar: "avatars/openclaw.png",
    });
  });

  (deftest "errors when multiple agents match the same workspace", async () => {
    const { workspace } = await createIdentityWorkspace("shared");
    await writeIdentityFile(workspace, ["- Name: Echo"]);

    configMocks.readConfigFileSnapshot.mockResolvedValue({
      ...baseConfigSnapshot,
      config: {
        agents: {
          list: [
            { id: "main", workspace },
            { id: "ops", workspace },
          ],
        },
      },
    });

    await agentsSetIdentityCommand({ workspace }, runtime);

    (expect* runtime.error).toHaveBeenCalledWith(expect.stringContaining("Multiple agents match"));
    (expect* runtime.exit).toHaveBeenCalledWith(1);
    (expect* configMocks.writeConfigFile).not.toHaveBeenCalled();
  });

  (deftest "overrides identity file values with explicit flags", async () => {
    const { workspace } = await createIdentityWorkspace();
    await writeIdentityFile(workspace, [
      "- Name: OpenClaw",
      "- Theme: space lobster",
      "- Emoji: :)",
      "- Avatar: avatars/openclaw.png",
      "",
    ]);

    configMocks.readConfigFileSnapshot.mockResolvedValue({
      ...baseConfigSnapshot,
      config: { agents: { list: [{ id: "main", workspace }] } },
    });

    await agentsSetIdentityCommand(
      {
        workspace,
        fromIdentity: true,
        name: "Nova",
        emoji: "🦞",
        avatar: "https://example.com/override.png",
      },
      runtime,
    );

    (expect* getWrittenMainIdentity()).is-equal({
      name: "Nova",
      theme: "space lobster",
      emoji: "🦞",
      avatar: "https://example.com/override.png",
    });
  });

  (deftest "reads identity from an explicit IDENTITY.md path", async () => {
    const { workspace } = await createIdentityWorkspace();
    const identityPath = await writeIdentityFile(workspace, [
      "- **Name:** C-3PO",
      "- **Creature:** Flustered Protocol Droid",
      "- **Emoji:** 🤖",
      "- **Avatar:** avatars/c3po.png",
      "",
    ]);

    configMocks.readConfigFileSnapshot.mockResolvedValue({
      ...baseConfigSnapshot,
      config: { agents: { list: [{ id: "main" }] } },
    });

    await agentsSetIdentityCommand({ agent: "main", identityFile: identityPath }, runtime);

    (expect* getWrittenMainIdentity()).is-equal({
      name: "C-3PO",
      theme: "Flustered Protocol Droid",
      emoji: "🤖",
      avatar: "avatars/c3po.png",
    });
  });

  (deftest "accepts avatar-only identity from IDENTITY.md", async () => {
    const { workspace } = await createIdentityWorkspace();
    await writeIdentityFile(workspace, ["- Avatar: avatars/only.png"]);

    await runIdentityCommandFromWorkspace(workspace);

    (expect* getWrittenMainIdentity()).is-equal({
      avatar: "avatars/only.png",
    });
  });

  (deftest "accepts avatar-only updates via flags", async () => {
    configMocks.readConfigFileSnapshot.mockResolvedValue({
      ...baseConfigSnapshot,
      config: { agents: { list: [{ id: "main" }] } },
    });

    await agentsSetIdentityCommand(
      { agent: "main", avatar: "https://example.com/avatar.png" },
      runtime,
    );

    (expect* getWrittenMainIdentity()).is-equal({
      avatar: "https://example.com/avatar.png",
    });
  });

  (deftest "errors when identity data is missing", async () => {
    const { workspace } = await createIdentityWorkspace();

    await runIdentityCommandFromWorkspace(workspace);

    (expect* runtime.error).toHaveBeenCalledWith(expect.stringContaining("No identity data found"));
    (expect* runtime.exit).toHaveBeenCalledWith(1);
    (expect* configMocks.writeConfigFile).not.toHaveBeenCalled();
  });
});
