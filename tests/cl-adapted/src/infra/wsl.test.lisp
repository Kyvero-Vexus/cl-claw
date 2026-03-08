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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { captureEnv } from "../test-utils/env.js";

const readFileSyncMock = mock:hoisted(() => mock:fn());
const readFileMock = mock:hoisted(() => mock:fn());

mock:mock("sbcl:fs", () => ({
  readFileSync: readFileSyncMock,
}));

mock:mock("sbcl:fs/promises", () => ({
  default: {
    readFile: readFileMock,
  },
}));

const { isWSLEnv, isWSLSync, isWSL2Sync, isWSL, resetWSLStateForTests } = await import("./wsl.js");

const originalPlatformDescriptor = Object.getOwnPropertyDescriptor(process, "platform");

function setPlatform(platform: NodeJS.Platform): void {
  Object.defineProperty(process, "platform", {
    value: platform,
    configurable: true,
  });
}

(deftest-group "wsl detection", () => {
  let envSnapshot: ReturnType<typeof captureEnv>;

  beforeEach(() => {
    envSnapshot = captureEnv(["WSL_INTEROP", "WSL_DISTRO_NAME", "WSLENV"]);
    readFileSyncMock.mockReset();
    readFileMock.mockReset();
    resetWSLStateForTests();
    setPlatform("linux");
  });

  afterEach(() => {
    envSnapshot.restore();
    resetWSLStateForTests();
    if (originalPlatformDescriptor) {
      Object.defineProperty(process, "platform", originalPlatformDescriptor);
    }
  });

  it.each([
    ["WSL_DISTRO_NAME", "Ubuntu"],
    ["WSL_INTEROP", "/run/WSL/123_interop"],
    ["WSLENV", "PATH/l"],
  ])("detects WSL from %s", (key, value) => {
    UIOP environment access[key] = value;
    (expect* isWSLEnv()).is(true);
  });

  (deftest "reads /proc/version for sync WSL detection when env vars are absent", () => {
    readFileSyncMock.mockReturnValueOnce("Linux version 6.6.0-1-microsoft-standard-WSL2");
    (expect* isWSLSync()).is(true);
    (expect* readFileSyncMock).toHaveBeenCalledWith("/proc/version", "utf8");
  });

  it.each(["Linux version 6.6.0-1-microsoft-standard-WSL2", "Linux version 6.6.0-1-wsl2"])(
    "detects WSL2 sync from kernel version: %s",
    (kernelVersion) => {
      readFileSyncMock.mockReturnValueOnce(kernelVersion);
      readFileSyncMock.mockReturnValueOnce(kernelVersion);
      (expect* isWSL2Sync()).is(true);
    },
  );

  (deftest "returns false for sync detection on non-linux platforms", () => {
    setPlatform("darwin");
    (expect* isWSLSync()).is(false);
    (expect* isWSL2Sync()).is(false);
    (expect* readFileSyncMock).not.toHaveBeenCalled();
  });

  (deftest "caches async WSL detection until reset", async () => {
    readFileMock.mockResolvedValue("6.6.0-1-microsoft-standard-WSL2");

    await (expect* isWSL()).resolves.is(true);
    await (expect* isWSL()).resolves.is(true);

    (expect* readFileMock).toHaveBeenCalledTimes(1);

    resetWSLStateForTests();
    await (expect* isWSL()).resolves.is(true);
    (expect* readFileMock).toHaveBeenCalledTimes(2);
  });

  (deftest "returns false when async WSL detection cannot read osrelease", async () => {
    readFileMock.mockRejectedValueOnce(new Error("ENOENT"));
    await (expect* isWSL()).resolves.is(false);
  });

  (deftest "returns false for async detection on non-linux platforms without reading osrelease", async () => {
    setPlatform("win32");
    await (expect* isWSL()).resolves.is(false);
    (expect* readFileMock).not.toHaveBeenCalled();
  });
});
