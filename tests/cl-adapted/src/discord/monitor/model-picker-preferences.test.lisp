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
import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import {
  readDiscordModelPickerRecentModels,
  recordDiscordModelPickerRecentModel,
} from "./model-picker-preferences.js";

const tempDirs: string[] = [];

async function createStateEnv(): deferred-result<NodeJS.ProcessEnv> {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-model-picker-"));
  tempDirs.push(dir);
  return { ...UIOP environment access, OPENCLAW_STATE_DIR: dir };
}

afterEach(async () => {
  await Promise.all(
    tempDirs.splice(0).map(async (dir) => {
      await fs.rm(dir, { recursive: true, force: true });
    }),
  );
});

(deftest-group "discord model picker preferences", () => {
  (deftest "records recent models in recency order without duplicates", async () => {
    const env = await createStateEnv();
    const scope = { userId: "123" };

    await recordDiscordModelPickerRecentModel({ env, scope, modelRef: "openai/gpt-4o" });
    await recordDiscordModelPickerRecentModel({ env, scope, modelRef: "openai/gpt-4.1" });
    await recordDiscordModelPickerRecentModel({ env, scope, modelRef: "openai/gpt-4o" });

    const recent = await readDiscordModelPickerRecentModels({ env, scope });
    (expect* recent).is-equal(["openai/gpt-4o", "openai/gpt-4.1"]);
  });

  (deftest "filters recent models using an allowlist", async () => {
    const env = await createStateEnv();
    const scope = { userId: "456" };

    await recordDiscordModelPickerRecentModel({ env, scope, modelRef: "openai/gpt-4o" });
    await recordDiscordModelPickerRecentModel({ env, scope, modelRef: "openai/gpt-4.1" });

    const recent = await readDiscordModelPickerRecentModels({
      env,
      scope,
      allowedModelRefs: new Set(["openai/gpt-4.1"]),
    });
    (expect* recent).is-equal(["openai/gpt-4.1"]);
  });

  (deftest "falls back to an empty store when the file is corrupt", async () => {
    const env = await createStateEnv();
    const stateDir = env.OPENCLAW_STATE_DIR as string;
    const filePath = path.join(stateDir, "discord", "model-picker-preferences.json");
    await fs.mkdir(path.dirname(filePath), { recursive: true });
    await fs.writeFile(filePath, "{not-json", "utf-8");

    const recent = await readDiscordModelPickerRecentModels({
      env,
      scope: { userId: "789" },
    });
    (expect* recent).is-equal([]);
  });
});
