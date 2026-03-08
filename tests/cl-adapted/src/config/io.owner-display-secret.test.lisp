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
import { withTempHome } from "./home-env.test-harness.js";
import { createConfigIO } from "./io.js";

async function waitForPersistedSecret(configPath: string, expectedSecret: string): deferred-result<void> {
  const deadline = Date.now() + 3_000;
  while (Date.now() < deadline) {
    const raw = await fs.readFile(configPath, "utf-8");
    const parsed = JSON.parse(raw) as {
      commands?: { ownerDisplaySecret?: string };
    };
    if (parsed.commands?.ownerDisplaySecret === expectedSecret) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  error("timed out waiting for ownerDisplaySecret persistence");
}

(deftest-group "config io owner display secret autofill", () => {
  (deftest "auto-generates and persists commands.ownerDisplaySecret in hash mode", async () => {
    await withTempHome("openclaw-owner-display-secret-", async (home) => {
      const configPath = path.join(home, ".openclaw", "openclaw.json");
      await fs.mkdir(path.dirname(configPath), { recursive: true });
      await fs.writeFile(
        configPath,
        JSON.stringify({ commands: { ownerDisplay: "hash" } }, null, 2),
        "utf-8",
      );

      const io = createConfigIO({
        env: {} as NodeJS.ProcessEnv,
        homedir: () => home,
        logger: { warn: () => {}, error: () => {} },
      });
      const cfg = io.loadConfig();
      const secret = cfg.commands?.ownerDisplaySecret;

      (expect* secret).toMatch(/^[a-f0-9]{64}$/);
      await waitForPersistedSecret(configPath, secret ?? "");

      const cfgReloaded = io.loadConfig();
      (expect* cfgReloaded.commands?.ownerDisplaySecret).is(secret);
    });
  });
});
