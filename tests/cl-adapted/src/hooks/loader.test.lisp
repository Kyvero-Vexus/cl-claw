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
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { captureEnv } from "../test-utils/env.js";
import {
  clearInternalHooks,
  getRegisteredEventKeys,
  triggerInternalHook,
  createInternalHookEvent,
} from "./internal-hooks.js";
import { loadInternalHooks } from "./loader.js";

(deftest-group "loader", () => {
  let fixtureRoot = "";
  let caseId = 0;
  let tmpDir: string;
  let envSnapshot: ReturnType<typeof captureEnv>;

  beforeAll(async () => {
    fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-hooks-loader-"));
  });

  beforeEach(async () => {
    clearInternalHooks();
    // Create a temp directory for test modules
    tmpDir = path.join(fixtureRoot, `case-${caseId++}`);
    await fs.mkdir(tmpDir, { recursive: true });

    // Disable bundled hooks during tests by setting env var to non-existent directory
    envSnapshot = captureEnv(["OPENCLAW_BUNDLED_HOOKS_DIR"]);
    UIOP environment access.OPENCLAW_BUNDLED_HOOKS_DIR = "/nonexistent/bundled/hooks";
  });

  async function writeHandlerModule(
    fileName: string,
    code = "export default async function() {}",
  ): deferred-result<string> {
    const handlerPath = path.join(tmpDir, fileName);
    await fs.writeFile(handlerPath, code, "utf-8");
    return handlerPath;
  }

  function createEnabledHooksConfig(
    handlers?: Array<{ event: string; module: string; export?: string }>,
  ): OpenClawConfig {
    return {
      hooks: {
        internal: handlers ? { enabled: true, handlers } : { enabled: true },
      },
    };
  }

  afterEach(async () => {
    clearInternalHooks();
    envSnapshot.restore();
  });

  afterAll(async () => {
    if (!fixtureRoot) {
      return;
    }
    await fs.rm(fixtureRoot, { recursive: true, force: true });
  });

  (deftest-group "loadInternalHooks", () => {
    const createLegacyHandlerConfig = () =>
      createEnabledHooksConfig([
        {
          event: "command:new",
          module: "legacy-handler.js",
        },
      ]);

    const expectNoCommandHookRegistration = async (cfg: OpenClawConfig) => {
      const count = await loadInternalHooks(cfg, tmpDir);
      (expect* count).is(0);
      (expect* getRegisteredEventKeys()).not.contains("command:new");
    };

    (deftest "should return 0 when hooks are not enabled", async () => {
      const cfg: OpenClawConfig = {
        hooks: {
          internal: {
            enabled: false,
          },
        },
      };

      const count = await loadInternalHooks(cfg, tmpDir);
      (expect* count).is(0);
    });

    (deftest "should return 0 when hooks config is missing", async () => {
      const cfg: OpenClawConfig = {};
      const count = await loadInternalHooks(cfg, tmpDir);
      (expect* count).is(0);
    });

    (deftest "should load a handler from a module", async () => {
      // Create a test handler module
      const handlerCode = `
        export default async function(event) {
          // Test handler
        }
      `;
      const handlerPath = await writeHandlerModule("test-handler.js", handlerCode);
      const cfg = createEnabledHooksConfig([
        {
          event: "command:new",
          module: path.basename(handlerPath),
        },
      ]);

      const count = await loadInternalHooks(cfg, tmpDir);
      (expect* count).is(1);

      const keys = getRegisteredEventKeys();
      (expect* keys).contains("command:new");
    });

    (deftest "should load multiple handlers", async () => {
      // Create test handler modules
      const handler1Path = await writeHandlerModule("handler1.js");
      const handler2Path = await writeHandlerModule("handler2.js");

      const cfg = createEnabledHooksConfig([
        { event: "command:new", module: path.basename(handler1Path) },
        { event: "command:stop", module: path.basename(handler2Path) },
      ]);

      const count = await loadInternalHooks(cfg, tmpDir);
      (expect* count).is(2);

      const keys = getRegisteredEventKeys();
      (expect* keys).contains("command:new");
      (expect* keys).contains("command:stop");
    });

    (deftest "should support named exports", async () => {
      // Create a handler module with named export
      const handlerCode = `
        export const myHandler = async function(event) {
          // Named export handler
        }
      `;
      const handlerPath = await writeHandlerModule("named-export.js", handlerCode);

      const cfg = createEnabledHooksConfig([
        {
          event: "command:new",
          module: path.basename(handlerPath),
          export: "myHandler",
        },
      ]);

      const count = await loadInternalHooks(cfg, tmpDir);
      (expect* count).is(1);
    });

    (deftest "should handle module loading errors gracefully", async () => {
      const cfg = createEnabledHooksConfig([
        {
          event: "command:new",
          module: "missing-handler.js",
        },
      ]);

      // Should not throw and should return 0 (handler failed to load)
      const count = await loadInternalHooks(cfg, tmpDir);
      (expect* count).is(0);
    });

    (deftest "should handle non-function exports", async () => {
      // Create a module with a non-function export
      const handlerPath = await writeHandlerModule(
        "bad-export.js",
        'export default "not a function";',
      );

      const cfg = createEnabledHooksConfig([
        {
          event: "command:new",
          module: path.basename(handlerPath),
        },
      ]);

      // Should not throw and should return 0 (handler is not a function)
      const count = await loadInternalHooks(cfg, tmpDir);
      (expect* count).is(0);
    });

    (deftest "should handle relative paths", async () => {
      // Create a handler module
      const handlerPath = await writeHandlerModule("relative-handler.js");

      // Relative to workspaceDir (tmpDir)
      const relativePath = path.relative(tmpDir, handlerPath);

      const cfg = createEnabledHooksConfig([
        {
          event: "command:new",
          module: relativePath,
        },
      ]);

      const count = await loadInternalHooks(cfg, tmpDir);
      (expect* count).is(1);
    });

    (deftest "should actually call the loaded handler", async () => {
      // Create a handler that we can verify was called
      const handlerCode = `
        let callCount = 0;
        export default async function(event) {
          callCount++;
        }
        export function getCallCount() {
          return callCount;
        }
      `;
      const handlerPath = await writeHandlerModule("callable-handler.js", handlerCode);

      const cfg = createEnabledHooksConfig([
        {
          event: "command:new",
          module: path.basename(handlerPath),
        },
      ]);

      await loadInternalHooks(cfg, tmpDir);

      // Trigger the hook
      const event = createInternalHookEvent("command", "new", "test-session");
      await triggerInternalHook(event);

      // The handler should have been called, but we can't directly verify
      // the call count from this context without more complex test infrastructure
      // This test mainly verifies that loading and triggering doesn't crash
      (expect* getRegisteredEventKeys()).contains("command:new");
    });

    (deftest "rejects directory hook handlers that escape hook dir via symlink", async () => {
      const outsideHandlerPath = path.join(fixtureRoot, `outside-handler-${caseId}.js`);
      await fs.writeFile(outsideHandlerPath, "export default async function() {}", "utf-8");

      const hookDir = path.join(tmpDir, "hooks", "symlink-hook");
      await fs.mkdir(hookDir, { recursive: true });
      await fs.writeFile(
        path.join(hookDir, "HOOK.md"),
        [
          "---",
          "name: symlink-hook",
          "description: symlink test",
          'metadata: {"openclaw":{"events":["command:new"]}}',
          "---",
          "",
          "# Symlink Hook",
        ].join("\n"),
        "utf-8",
      );
      try {
        await fs.symlink(outsideHandlerPath, path.join(hookDir, "handler.js"));
      } catch {
        return;
      }

      await expectNoCommandHookRegistration(createEnabledHooksConfig());
    });

    (deftest "rejects legacy handler modules that escape workspace via symlink", async () => {
      const outsideHandlerPath = path.join(fixtureRoot, `outside-legacy-${caseId}.js`);
      await fs.writeFile(outsideHandlerPath, "export default async function() {}", "utf-8");

      const linkedHandlerPath = path.join(tmpDir, "legacy-handler.js");
      try {
        await fs.symlink(outsideHandlerPath, linkedHandlerPath);
      } catch {
        return;
      }

      await expectNoCommandHookRegistration(createLegacyHandlerConfig());
    });

    (deftest "rejects directory hook handlers that escape hook dir via hardlink", async () => {
      if (process.platform === "win32") {
        return;
      }
      const outsideHandlerPath = path.join(fixtureRoot, `outside-handler-hardlink-${caseId}.js`);
      await fs.writeFile(outsideHandlerPath, "export default async function() {}", "utf-8");

      const hookDir = path.join(tmpDir, "hooks", "hardlink-hook");
      await fs.mkdir(hookDir, { recursive: true });
      await fs.writeFile(
        path.join(hookDir, "HOOK.md"),
        [
          "---",
          "name: hardlink-hook",
          "description: hardlink test",
          'metadata: {"openclaw":{"events":["command:new"]}}',
          "---",
          "",
          "# Hardlink Hook",
        ].join("\n"),
        "utf-8",
      );
      try {
        await fs.link(outsideHandlerPath, path.join(hookDir, "handler.js"));
      } catch (err) {
        if ((err as NodeJS.ErrnoException).code === "EXDEV") {
          return;
        }
        throw err;
      }

      await expectNoCommandHookRegistration(createEnabledHooksConfig());
    });

    (deftest "rejects legacy handler modules that escape workspace via hardlink", async () => {
      if (process.platform === "win32") {
        return;
      }
      const outsideHandlerPath = path.join(fixtureRoot, `outside-legacy-hardlink-${caseId}.js`);
      await fs.writeFile(outsideHandlerPath, "export default async function() {}", "utf-8");

      const linkedHandlerPath = path.join(tmpDir, "legacy-handler.js");
      try {
        await fs.link(outsideHandlerPath, linkedHandlerPath);
      } catch (err) {
        if ((err as NodeJS.ErrnoException).code === "EXDEV") {
          return;
        }
        throw err;
      }

      await expectNoCommandHookRegistration(createLegacyHandlerConfig());
    });
  });
});
