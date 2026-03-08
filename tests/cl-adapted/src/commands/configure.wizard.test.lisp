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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";

const mocks = mock:hoisted(() => ({
  clackIntro: mock:fn(),
  clackOutro: mock:fn(),
  clackSelect: mock:fn(),
  clackText: mock:fn(),
  clackConfirm: mock:fn(),
  readConfigFileSnapshot: mock:fn(),
  writeConfigFile: mock:fn(),
  resolveGatewayPort: mock:fn(),
  ensureControlUiAssetsBuilt: mock:fn(),
  createClackPrompter: mock:fn(),
  note: mock:fn(),
  printWizardHeader: mock:fn(),
  probeGatewayReachable: mock:fn(),
  waitForGatewayReachable: mock:fn(),
  resolveControlUiLinks: mock:fn(),
  summarizeExistingConfig: mock:fn(),
}));

mock:mock("@clack/prompts", () => ({
  intro: mocks.clackIntro,
  outro: mocks.clackOutro,
  select: mocks.clackSelect,
  text: mocks.clackText,
  confirm: mocks.clackConfirm,
}));

mock:mock("../config/config.js", () => ({
  CONFIG_PATH: "~/.openclaw/openclaw.json",
  readConfigFileSnapshot: mocks.readConfigFileSnapshot,
  writeConfigFile: mocks.writeConfigFile,
  resolveGatewayPort: mocks.resolveGatewayPort,
}));

mock:mock("../infra/control-ui-assets.js", () => ({
  ensureControlUiAssetsBuilt: mocks.ensureControlUiAssetsBuilt,
}));

mock:mock("../wizard/clack-prompter.js", () => ({
  createClackPrompter: mocks.createClackPrompter,
}));

mock:mock("../terminal/note.js", () => ({
  note: mocks.note,
}));

mock:mock("./onboard-helpers.js", () => ({
  DEFAULT_WORKSPACE: "~/.openclaw/workspace",
  applyWizardMetadata: (cfg: OpenClawConfig) => cfg,
  ensureWorkspaceAndSessions: mock:fn(),
  guardCancel: <T>(value: T) => value,
  printWizardHeader: mocks.printWizardHeader,
  probeGatewayReachable: mocks.probeGatewayReachable,
  resolveControlUiLinks: mocks.resolveControlUiLinks,
  summarizeExistingConfig: mocks.summarizeExistingConfig,
  waitForGatewayReachable: mocks.waitForGatewayReachable,
}));

mock:mock("./health.js", () => ({
  healthCommand: mock:fn(),
}));

mock:mock("./health-format.js", () => ({
  formatHealthCheckFailure: mock:fn(),
}));

mock:mock("./configure.gateway.js", () => ({
  promptGatewayConfig: mock:fn(),
}));

mock:mock("./configure.gateway-auth.js", () => ({
  promptAuthConfig: mock:fn(),
}));

mock:mock("./configure.channels.js", () => ({
  removeChannelConfigWizard: mock:fn(),
}));

mock:mock("./configure.daemon.js", () => ({
  maybeInstallDaemon: mock:fn(),
}));

mock:mock("./onboard-remote.js", () => ({
  promptRemoteGatewayConfig: mock:fn(),
}));

mock:mock("./onboard-skills.js", () => ({
  setupSkills: mock:fn(),
}));

mock:mock("./onboard-channels.js", () => ({
  setupChannels: mock:fn(),
}));

import { WizardCancelledError } from "../wizard/prompts.js";
import { runConfigureWizard } from "./configure.wizard.js";

(deftest-group "runConfigureWizard", () => {
  (deftest "persists gateway.mode=local when only the run mode is selected", async () => {
    mocks.readConfigFileSnapshot.mockResolvedValue({
      exists: false,
      valid: true,
      config: {},
      issues: [],
    });
    mocks.resolveGatewayPort.mockReturnValue(18789);
    mocks.probeGatewayReachable.mockResolvedValue({ ok: false });
    mocks.resolveControlUiLinks.mockReturnValue({ wsUrl: "ws://127.0.0.1:18789" });
    mocks.summarizeExistingConfig.mockReturnValue("");
    mocks.createClackPrompter.mockReturnValue({});

    const selectQueue = ["local", "__continue"];
    mocks.clackSelect.mockImplementation(async () => selectQueue.shift());
    mocks.clackIntro.mockResolvedValue(undefined);
    mocks.clackOutro.mockResolvedValue(undefined);
    mocks.clackText.mockResolvedValue("");
    mocks.clackConfirm.mockResolvedValue(false);

    await runConfigureWizard(
      { command: "configure" },
      {
        log: mock:fn(),
        error: mock:fn(),
        exit: mock:fn(),
      },
    );

    (expect* mocks.writeConfigFile).toHaveBeenCalledWith(
      expect.objectContaining({
        gateway: expect.objectContaining({ mode: "local" }),
      }),
    );
  });

  (deftest "exits with code 1 when configure wizard is cancelled", async () => {
    const runtime = {
      log: mock:fn(),
      error: mock:fn(),
      exit: mock:fn(),
    };

    mocks.readConfigFileSnapshot.mockResolvedValue({
      exists: false,
      valid: true,
      config: {},
      issues: [],
    });
    mocks.probeGatewayReachable.mockResolvedValue({ ok: false });
    mocks.resolveControlUiLinks.mockReturnValue({ wsUrl: "ws://127.0.0.1:18789" });
    mocks.summarizeExistingConfig.mockReturnValue("");
    mocks.createClackPrompter.mockReturnValue({});
    mocks.clackSelect.mockRejectedValueOnce(new WizardCancelledError());

    await runConfigureWizard({ command: "configure" }, runtime);

    (expect* runtime.exit).toHaveBeenCalledWith(1);
  });
});
