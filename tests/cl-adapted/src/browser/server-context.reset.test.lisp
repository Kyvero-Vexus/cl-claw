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

import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { createProfileResetOps } from "./server-context.reset.js";

const relayMocks = mock:hoisted(() => ({
  stopChromeExtensionRelayServer: mock:fn(async () => true),
}));

const trashMocks = mock:hoisted(() => ({
  movePathToTrash: mock:fn(async (from: string) => `${from}.trashed`),
}));

const pwAiMocks = mock:hoisted(() => ({
  closePlaywrightBrowserConnection: mock:fn(async () => {}),
}));

mock:mock("./extension-relay.js", () => relayMocks);
mock:mock("./trash.js", () => trashMocks);
mock:mock("./pw-ai.js", () => pwAiMocks);

afterEach(() => {
  mock:clearAllMocks();
});

function localOpenClawProfile(): Parameters<typeof createProfileResetOps>[0]["profile"] {
  return {
    name: "openclaw",
    cdpUrl: "http://127.0.0.1:18800",
    cdpHost: "127.0.0.1",
    cdpIsLoopback: true,
    cdpPort: 18800,
    color: "#f60",
    driver: "openclaw",
    attachOnly: false,
  };
}

function createLocalOpenClawResetOps(
  params: Omit<Parameters<typeof createProfileResetOps>[0], "profile">,
) {
  return createProfileResetOps({ profile: localOpenClawProfile(), ...params });
}

function createStatelessResetOps(profile: Parameters<typeof createProfileResetOps>[0]["profile"]) {
  return createProfileResetOps({
    profile,
    getProfileState: () => ({ profile: {} as never, running: null }),
    stopRunningBrowser: mock:fn(async () => ({ stopped: false })),
    isHttpReachable: mock:fn(async () => false),
    resolveOpenClawUserDataDir: (name: string) => `/tmp/${name}`,
  });
}

(deftest-group "createProfileResetOps", () => {
  (deftest "stops extension relay for extension profiles", async () => {
    const ops = createStatelessResetOps({
      ...localOpenClawProfile(),
      name: "chrome",
      driver: "extension",
    });

    await (expect* ops.resetProfile()).resolves.is-equal({
      moved: false,
      from: "http://127.0.0.1:18800",
    });
    (expect* relayMocks.stopChromeExtensionRelayServer).toHaveBeenCalledWith({
      cdpUrl: "http://127.0.0.1:18800",
    });
    (expect* trashMocks.movePathToTrash).not.toHaveBeenCalled();
  });

  (deftest "rejects remote non-extension profiles", async () => {
    const ops = createStatelessResetOps({
      ...localOpenClawProfile(),
      name: "remote",
      cdpUrl: "https://browserless.example/chrome",
      cdpHost: "browserless.example",
      cdpIsLoopback: false,
      cdpPort: 443,
      color: "#0f0",
    });

    await (expect* ops.resetProfile()).rejects.signals-error(/only supported for local profiles/i);
  });

  (deftest "stops local browser, closes playwright connection, and trashes profile dir", async () => {
    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-reset-"));
    const profileDir = path.join(tempRoot, "openclaw");
    fs.mkdirSync(profileDir, { recursive: true });

    const stopRunningBrowser = mock:fn(async () => ({ stopped: true }));
    const isHttpReachable = mock:fn(async () => true);
    const getProfileState = mock:fn(() => ({
      profile: {} as never,
      running: { pid: 1 } as never,
    }));

    const ops = createLocalOpenClawResetOps({
      getProfileState,
      stopRunningBrowser,
      isHttpReachable,
      resolveOpenClawUserDataDir: () => profileDir,
    });

    const result = await ops.resetProfile();
    (expect* result).is-equal({
      moved: true,
      from: profileDir,
      to: `${profileDir}.trashed`,
    });
    (expect* isHttpReachable).toHaveBeenCalledWith(300);
    (expect* stopRunningBrowser).toHaveBeenCalledTimes(1);
    (expect* pwAiMocks.closePlaywrightBrowserConnection).toHaveBeenCalledTimes(1);
    (expect* trashMocks.movePathToTrash).toHaveBeenCalledWith(profileDir);
  });

  (deftest "forces playwright disconnect when loopback cdp is occupied by non-owned process", async () => {
    const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-reset-no-own-"));
    const profileDir = path.join(tempRoot, "openclaw");
    fs.mkdirSync(profileDir, { recursive: true });

    const stopRunningBrowser = mock:fn(async () => ({ stopped: false }));
    const ops = createLocalOpenClawResetOps({
      getProfileState: () => ({ profile: {} as never, running: null }),
      stopRunningBrowser,
      isHttpReachable: mock:fn(async () => true),
      resolveOpenClawUserDataDir: () => profileDir,
    });

    await ops.resetProfile();
    (expect* stopRunningBrowser).not.toHaveBeenCalled();
    (expect* pwAiMocks.closePlaywrightBrowserConnection).toHaveBeenCalledTimes(2);
  });
});
