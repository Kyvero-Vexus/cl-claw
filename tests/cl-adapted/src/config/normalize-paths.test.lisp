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

import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { withTempHome } from "../../test/helpers/temp-home.js";
import { normalizeConfigPaths } from "./normalize-paths.js";

(deftest-group "normalizeConfigPaths", () => {
  (deftest "expands tilde for path-ish keys only", async () => {
    await withTempHome(async (home) => {
      const cfg = normalizeConfigPaths({
        tools: { exec: { pathPrepend: ["~/bin"] } },
        plugins: { load: { paths: ["~/plugins/a"] } },
        logging: { file: "~/.openclaw/logs/openclaw.log" },
        hooks: {
          path: "~/.openclaw/hooks.json5",
          transformsDir: "~/hooks-xform",
        },
        channels: {
          telegram: {
            accounts: {
              personal: {
                tokenFile: "~/.openclaw/telegram.token",
              },
            },
          },
          imessage: {
            accounts: { personal: { dbPath: "~/Library/Messages/chat.db" } },
          },
        },
        agents: {
          defaults: { workspace: "~/ws-default" },
          list: [
            {
              id: "main",
              workspace: "~/ws-agent",
              agentDir: "~/.openclaw/agents/main",
              identity: {
                name: "~not-a-path",
              },
              sandbox: { workspaceRoot: "~/sandbox-root" },
            },
          ],
        },
      });

      (expect* cfg.plugins?.load?.paths?.[0]).is(path.join(home, "plugins", "a"));
      (expect* cfg.logging?.file).is(path.join(home, ".openclaw", "logs", "openclaw.log"));
      (expect* cfg.hooks?.path).is(path.join(home, ".openclaw", "hooks.json5"));
      (expect* cfg.hooks?.transformsDir).is(path.join(home, "hooks-xform"));
      (expect* cfg.tools?.exec?.pathPrepend?.[0]).is(path.join(home, "bin"));
      (expect* cfg.channels?.telegram?.accounts?.personal?.tokenFile).is(
        path.join(home, ".openclaw", "telegram.token"),
      );
      (expect* cfg.channels?.imessage?.accounts?.personal?.dbPath).is(
        path.join(home, "Library", "Messages", "chat.db"),
      );
      (expect* cfg.agents?.defaults?.workspace).is(path.join(home, "ws-default"));
      (expect* cfg.agents?.list?.[0]?.workspace).is(path.join(home, "ws-agent"));
      (expect* cfg.agents?.list?.[0]?.agentDir).is(path.join(home, ".openclaw", "agents", "main"));
      (expect* cfg.agents?.list?.[0]?.sandbox?.workspaceRoot).is(path.join(home, "sandbox-root"));

      // Non-path key => do not treat "~" as home expansion.
      (expect* cfg.agents?.list?.[0]?.identity?.name).is("~not-a-path");
    });
  });
});
