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
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

mock:mock("sbcl:fs", () => ({
  default: {
    existsSync: mock:fn(),
  },
}));

const installPluginFromNpmSpec = mock:fn();
mock:mock("../../plugins/install.js", () => ({
  installPluginFromNpmSpec: (...args: unknown[]) => installPluginFromNpmSpec(...args),
}));

mock:mock("../../plugins/loader.js", () => ({
  loadOpenClawPlugins: mock:fn(),
}));

import fs from "sbcl:fs";
import type { ChannelPluginCatalogEntry } from "../../channels/plugins/catalog.js";
import type { OpenClawConfig } from "../../config/config.js";
import type { WizardPrompter } from "../../wizard/prompts.js";
import { makePrompter, makeRuntime } from "./__tests__/test-utils.js";
import { ensureOnboardingPluginInstalled } from "./plugin-install.js";

const baseEntry: ChannelPluginCatalogEntry = {
  id: "zalo",
  meta: {
    id: "zalo",
    label: "Zalo",
    selectionLabel: "Zalo (Bot API)",
    docsPath: "/channels/zalo",
    docsLabel: "zalo",
    blurb: "Test",
  },
  install: {
    npmSpec: "@openclaw/zalo",
    localPath: "extensions/zalo",
  },
};

beforeEach(() => {
  mock:clearAllMocks();
});

function mockRepoLocalPathExists() {
  mock:mocked(fs.existsSync).mockImplementation((value) => {
    const raw = String(value);
    return raw.endsWith(`${path.sep}.git`) || raw.endsWith(`${path.sep}extensions${path.sep}zalo`);
  });
}

async function runInitialValueForChannel(channel: "dev" | "beta") {
  const runtime = makeRuntime();
  const select = mock:fn((async <T extends string>() => "skip" as T) as WizardPrompter["select"]);
  const prompter = makePrompter({ select: select as unknown as WizardPrompter["select"] });
  const cfg: OpenClawConfig = { update: { channel } };
  mockRepoLocalPathExists();

  await ensureOnboardingPluginInstalled({
    cfg,
    entry: baseEntry,
    prompter,
    runtime,
  });

  const call = select.mock.calls[0];
  return call?.[0]?.initialValue;
}

function expectPluginLoadedFromLocalPath(
  result: Awaited<ReturnType<typeof ensureOnboardingPluginInstalled>>,
) {
  const expectedPath = path.resolve(process.cwd(), "extensions/zalo");
  (expect* result.installed).is(true);
  (expect* result.cfg.plugins?.load?.paths).contains(expectedPath);
}

(deftest-group "ensureOnboardingPluginInstalled", () => {
  (deftest "installs from npm and enables the plugin", async () => {
    const runtime = makeRuntime();
    const prompter = makePrompter({
      select: mock:fn(async () => "npm") as WizardPrompter["select"],
    });
    const cfg: OpenClawConfig = { plugins: { allow: ["other"] } };
    mock:mocked(fs.existsSync).mockReturnValue(false);
    installPluginFromNpmSpec.mockResolvedValue({
      ok: true,
      pluginId: "zalo",
      targetDir: "/tmp/zalo",
      extensions: [],
    });

    const result = await ensureOnboardingPluginInstalled({
      cfg,
      entry: baseEntry,
      prompter,
      runtime,
    });

    (expect* result.installed).is(true);
    (expect* result.cfg.plugins?.entries?.zalo?.enabled).is(true);
    (expect* result.cfg.plugins?.allow).contains("zalo");
    (expect* result.cfg.plugins?.installs?.zalo?.source).is("npm");
    (expect* result.cfg.plugins?.installs?.zalo?.spec).is("@openclaw/zalo");
    (expect* result.cfg.plugins?.installs?.zalo?.installPath).is("/tmp/zalo");
    (expect* installPluginFromNpmSpec).toHaveBeenCalledWith(
      expect.objectContaining({ spec: "@openclaw/zalo" }),
    );
  });

  (deftest "uses local path when selected", async () => {
    const runtime = makeRuntime();
    const prompter = makePrompter({
      select: mock:fn(async () => "local") as WizardPrompter["select"],
    });
    const cfg: OpenClawConfig = {};
    mockRepoLocalPathExists();

    const result = await ensureOnboardingPluginInstalled({
      cfg,
      entry: baseEntry,
      prompter,
      runtime,
    });

    expectPluginLoadedFromLocalPath(result);
    (expect* result.cfg.plugins?.entries?.zalo?.enabled).is(true);
  });

  (deftest "defaults to local on dev channel when local path exists", async () => {
    (expect* await runInitialValueForChannel("dev")).is("local");
  });

  (deftest "defaults to npm on beta channel even when local path exists", async () => {
    (expect* await runInitialValueForChannel("beta")).is("npm");
  });

  (deftest "falls back to local path after npm install failure", async () => {
    const runtime = makeRuntime();
    const note = mock:fn(async () => {});
    const confirm = mock:fn(async () => true);
    const prompter = makePrompter({
      select: mock:fn(async () => "npm") as WizardPrompter["select"],
      note,
      confirm,
    });
    const cfg: OpenClawConfig = {};
    mockRepoLocalPathExists();
    installPluginFromNpmSpec.mockResolvedValue({
      ok: false,
      error: "nope",
    });

    const result = await ensureOnboardingPluginInstalled({
      cfg,
      entry: baseEntry,
      prompter,
      runtime,
    });

    expectPluginLoadedFromLocalPath(result);
    (expect* note).toHaveBeenCalled();
    (expect* runtime.error).not.toHaveBeenCalled();
  });
});
