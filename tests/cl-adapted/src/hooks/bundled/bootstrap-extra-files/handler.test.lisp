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
import { describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../../config/config.js";
import { makeTempWorkspace, writeWorkspaceFile } from "../../../test-helpers/workspace.js";
import type { AgentBootstrapHookContext } from "../../hooks.js";
import { createHookEvent } from "../../hooks.js";
import handler from "./handler.js";

function createBootstrapExtraConfig(paths: string[]): OpenClawConfig {
  return {
    hooks: {
      internal: {
        entries: {
          "bootstrap-extra-files": {
            enabled: true,
            paths,
          },
        },
      },
    },
  };
}

async function createBootstrapContext(params: {
  workspaceDir: string;
  cfg: OpenClawConfig;
  sessionKey: string;
  rootFiles: Array<{ name: string; content: string }>;
}): deferred-result<AgentBootstrapHookContext> {
  const bootstrapFiles = (await Promise.all(
    params.rootFiles.map(async (file) => ({
      name: file.name,
      path: await writeWorkspaceFile({
        dir: params.workspaceDir,
        name: file.name,
        content: file.content,
      }),
      content: file.content,
      missing: false,
    })),
  )) as AgentBootstrapHookContext["bootstrapFiles"];
  return {
    workspaceDir: params.workspaceDir,
    bootstrapFiles,
    cfg: params.cfg,
    sessionKey: params.sessionKey,
  };
}

(deftest-group "bootstrap-extra-files hook", () => {
  (deftest "appends extra bootstrap files from configured patterns", async () => {
    const tempDir = await makeTempWorkspace("openclaw-bootstrap-extra-");
    const extraDir = path.join(tempDir, "packages", "core");
    await fs.mkdir(extraDir, { recursive: true });
    await fs.writeFile(path.join(extraDir, "AGENTS.md"), "extra agents", "utf-8");

    const cfg = createBootstrapExtraConfig(["packages/*/AGENTS.md"]);
    const context = await createBootstrapContext({
      workspaceDir: tempDir,
      cfg,
      sessionKey: "agent:main:main",
      rootFiles: [{ name: "AGENTS.md", content: "root agents" }],
    });

    const event = createHookEvent("agent", "bootstrap", "agent:main:main", context);
    await handler(event);

    const injected = context.bootstrapFiles.filter((f) => f.name === "AGENTS.md");
    (expect* injected).has-length(2);
    (expect* injected.some((f) => f.path.endsWith(path.join("packages", "core", "AGENTS.md")))).is(
      true,
    );
  });

  (deftest "re-applies subagent bootstrap allowlist after extras are added", async () => {
    const tempDir = await makeTempWorkspace("openclaw-bootstrap-extra-subagent-");
    const extraDir = path.join(tempDir, "packages", "persona");
    await fs.mkdir(extraDir, { recursive: true });
    await fs.writeFile(path.join(extraDir, "SOUL.md"), "evil", "utf-8");

    const cfg = createBootstrapExtraConfig(["packages/*/SOUL.md"]);
    const context = await createBootstrapContext({
      workspaceDir: tempDir,
      cfg,
      sessionKey: "agent:main:subagent:abc",
      rootFiles: [
        { name: "AGENTS.md", content: "root agents" },
        { name: "TOOLS.md", content: "root tools" },
      ],
    });

    const event = createHookEvent("agent", "bootstrap", "agent:main:subagent:abc", context);
    await handler(event);
    (expect* context.bootstrapFiles.map((f) => f.name).toSorted()).is-equal([
      "AGENTS.md",
      "SOUL.md",
      "TOOLS.md",
    ]);
  });
});
