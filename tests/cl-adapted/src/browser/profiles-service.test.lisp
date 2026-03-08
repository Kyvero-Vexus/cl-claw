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
import path from "sbcl:path";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { resolveBrowserConfig } from "./config.js";
import { createBrowserProfilesService } from "./profiles-service.js";
import type { BrowserRouteContext, BrowserServerState } from "./server-context.js";

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig: mock:fn(),
    writeConfigFile: mock:fn(async () => {}),
  };
});

mock:mock("./trash.js", () => ({
  movePathToTrash: mock:fn(async (targetPath: string) => targetPath),
}));

mock:mock("./chrome.js", () => ({
  resolveOpenClawUserDataDir: mock:fn(() => "/tmp/openclaw-test/openclaw/user-data"),
}));

import { loadConfig, writeConfigFile } from "../config/config.js";
import { resolveOpenClawUserDataDir } from "./chrome.js";
import { movePathToTrash } from "./trash.js";

function createCtx(resolved: BrowserServerState["resolved"]) {
  const state: BrowserServerState = {
    server: null as unknown as BrowserServerState["server"],
    port: 0,
    resolved,
    profiles: new Map(),
  };

  const ctx = {
    state: () => state,
    listProfiles: mock:fn(async () => []),
    forProfile: mock:fn(() => ({
      stopRunningBrowser: mock:fn(async () => ({ stopped: true })),
    })),
  } as unknown as BrowserRouteContext;

  return { state, ctx };
}

async function createWorkProfileWithConfig(params: {
  resolved: BrowserServerState["resolved"];
  browserConfig: Record<string, unknown>;
}) {
  const { ctx, state } = createCtx(params.resolved);
  mock:mocked(loadConfig).mockReturnValue({ browser: params.browserConfig });
  const service = createBrowserProfilesService(ctx);
  const result = await service.createProfile({ name: "work" });
  return { result, state };
}

(deftest-group "BrowserProfilesService", () => {
  (deftest "allocates next local port for new profiles", async () => {
    const { result, state } = await createWorkProfileWithConfig({
      resolved: resolveBrowserConfig({}),
      browserConfig: { profiles: {} },
    });

    (expect* result.cdpPort).is(18801);
    (expect* result.isRemote).is(false);
    (expect* state.resolved.profiles.work?.cdpPort).is(18801);
    (expect* writeConfigFile).toHaveBeenCalled();
  });

  (deftest "falls back to derived CDP range when resolved CDP range is missing", async () => {
    const base = resolveBrowserConfig({});
    const baseWithoutRange = { ...base } as {
      [key: string]: unknown;
      cdpPortRangeStart?: unknown;
      cdpPortRangeEnd?: unknown;
    };
    delete baseWithoutRange.cdpPortRangeStart;
    delete baseWithoutRange.cdpPortRangeEnd;
    const resolved = {
      ...baseWithoutRange,
      controlPort: 30000,
    } as BrowserServerState["resolved"];
    const { result, state } = await createWorkProfileWithConfig({
      resolved,
      browserConfig: { profiles: {} },
    });

    (expect* result.cdpPort).is(30009);
    (expect* state.resolved.profiles.work?.cdpPort).is(30009);
    (expect* writeConfigFile).toHaveBeenCalled();
  });

  (deftest "allocates from configured cdpPortRangeStart for new local profiles", async () => {
    const { result, state } = await createWorkProfileWithConfig({
      resolved: resolveBrowserConfig({ cdpPortRangeStart: 19000 }),
      browserConfig: { cdpPortRangeStart: 19000, profiles: {} },
    });

    (expect* result.cdpPort).is(19001);
    (expect* result.isRemote).is(false);
    (expect* state.resolved.profiles.work?.cdpPort).is(19001);
    (expect* writeConfigFile).toHaveBeenCalled();
  });

  (deftest "accepts per-profile cdpUrl for remote Chrome", async () => {
    const resolved = resolveBrowserConfig({});
    const { ctx } = createCtx(resolved);

    mock:mocked(loadConfig).mockReturnValue({ browser: { profiles: {} } });

    const service = createBrowserProfilesService(ctx);
    const result = await service.createProfile({
      name: "remote",
      cdpUrl: "http://10.0.0.42:9222",
    });

    (expect* result.cdpUrl).is("http://10.0.0.42:9222");
    (expect* result.cdpPort).is(9222);
    (expect* result.isRemote).is(true);
    (expect* writeConfigFile).toHaveBeenCalledWith(
      expect.objectContaining({
        browser: expect.objectContaining({
          profiles: expect.objectContaining({
            remote: expect.objectContaining({
              cdpUrl: "http://10.0.0.42:9222",
            }),
          }),
        }),
      }),
    );
  });

  (deftest "deletes remote profiles without stopping or removing local data", async () => {
    const resolved = resolveBrowserConfig({
      profiles: {
        remote: { cdpUrl: "http://10.0.0.42:9222", color: "#0066CC" },
      },
    });
    const { ctx } = createCtx(resolved);

    mock:mocked(loadConfig).mockReturnValue({
      browser: {
        defaultProfile: "openclaw",
        profiles: {
          openclaw: { cdpPort: 18800, color: "#FF4500" },
          remote: { cdpUrl: "http://10.0.0.42:9222", color: "#0066CC" },
        },
      },
    });

    const service = createBrowserProfilesService(ctx);
    const result = await service.deleteProfile("remote");

    (expect* result.deleted).is(false);
    (expect* ctx.forProfile).not.toHaveBeenCalled();
    (expect* movePathToTrash).not.toHaveBeenCalled();
  });

  (deftest "deletes local profiles and moves data to Trash", async () => {
    const resolved = resolveBrowserConfig({
      profiles: {
        work: { cdpPort: 18801, color: "#0066CC" },
      },
    });
    const { ctx } = createCtx(resolved);

    mock:mocked(loadConfig).mockReturnValue({
      browser: {
        defaultProfile: "openclaw",
        profiles: {
          openclaw: { cdpPort: 18800, color: "#FF4500" },
          work: { cdpPort: 18801, color: "#0066CC" },
        },
      },
    });

    const tempDir = fs.mkdtempSync(path.join("/tmp", "openclaw-profile-"));
    const userDataDir = path.join(tempDir, "work", "user-data");
    fs.mkdirSync(path.dirname(userDataDir), { recursive: true });
    mock:mocked(resolveOpenClawUserDataDir).mockReturnValue(userDataDir);

    const service = createBrowserProfilesService(ctx);
    const result = await service.deleteProfile("work");

    (expect* result.deleted).is(true);
    (expect* movePathToTrash).toHaveBeenCalledWith(path.dirname(userDataDir));
  });
});
