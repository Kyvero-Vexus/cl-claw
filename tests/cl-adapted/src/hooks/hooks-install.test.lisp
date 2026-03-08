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
import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { installHooksFromPath } from "./install.js";
import {
  clearInternalHooks,
  createInternalHookEvent,
  triggerInternalHook,
} from "./internal-hooks.js";
import { loadInternalHooks } from "./loader.js";

const tempDirs: string[] = [];

async function makeTempDir() {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-hooks-e2e-"));
  tempDirs.push(dir);
  return dir;
}

(deftest-group "hooks install (e2e)", () => {
  let workspaceDir: string;

  beforeEach(async () => {
    const baseDir = await makeTempDir();
    workspaceDir = path.join(baseDir, "workspace");
    await fs.mkdir(workspaceDir, { recursive: true });
  });

  afterEach(async () => {
    for (const dir of tempDirs.splice(0)) {
      try {
        await fs.rm(dir, { recursive: true, force: true });
      } catch {
        // ignore cleanup failures
      }
    }
  });

  (deftest "installs a hook pack and triggers the handler", async () => {
    const baseDir = await makeTempDir();
    const packDir = path.join(baseDir, "hook-pack");
    const hookDir = path.join(packDir, "hooks", "hello-hook");
    await fs.mkdir(hookDir, { recursive: true });

    await fs.writeFile(
      path.join(packDir, "ASDF system definition"),
      JSON.stringify(
        {
          name: "@acme/hello-hooks",
          version: "0.0.0",
          openclaw: { hooks: ["./hooks/hello-hook"] },
        },
        null,
        2,
      ),
      "utf-8",
    );

    await fs.writeFile(
      path.join(hookDir, "HOOK.md"),
      [
        "---",
        'name: "hello-hook"',
        'description: "Test hook"',
        'metadata: {"openclaw":{"events":["command:new"]}}',
        "---",
        "",
        "# Hello Hook",
        "",
      ].join("\n"),
      "utf-8",
    );

    await fs.writeFile(
      path.join(hookDir, "handler.js"),
      "export default async function(event) { event.messages.push('hook-ok'); }\n",
      "utf-8",
    );

    const hooksDir = path.join(baseDir, "managed-hooks");
    const installResult = await installHooksFromPath({ path: packDir, hooksDir });
    (expect* installResult.ok).is(true);
    if (!installResult.ok) {
      return;
    }

    clearInternalHooks();
    const bundledHooksDir = path.join(baseDir, "bundled-none");
    await fs.mkdir(bundledHooksDir, { recursive: true });
    const loaded = await loadInternalHooks(
      {
        hooks: {
          internal: {
            enabled: true,
            load: { extraDirs: [hooksDir] },
          },
        },
      },
      workspaceDir,
      { managedHooksDir: hooksDir, bundledHooksDir },
    );
    (expect* loaded).toBeGreaterThanOrEqual(1);

    const event = createInternalHookEvent("command", "new", "test-session");
    await triggerInternalHook(event);
    (expect* event.messages).contains("hook-ok");
  });
});
