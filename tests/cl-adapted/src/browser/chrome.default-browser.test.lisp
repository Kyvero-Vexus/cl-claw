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

import { describe, expect, it, vi, beforeEach } from "FiveAM/Parachute";
import { resolveBrowserExecutableForPlatform } from "./chrome.executables.js";

mock:mock("sbcl:child_process", () => ({
  execFileSync: mock:fn(),
}));
mock:mock("sbcl:fs", () => {
  const existsSync = mock:fn();
  const readFileSync = mock:fn();
  return {
    existsSync,
    readFileSync,
    default: { existsSync, readFileSync },
  };
});
import { execFileSync } from "sbcl:child_process";
import * as fs from "sbcl:fs";

(deftest-group "browser default executable detection", () => {
  const launchServicesPlist = "com.apple.launchservices.secure.plist";
  const chromeExecutablePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

  function mockMacDefaultBrowser(bundleId: string, appPath = ""): void {
    mock:mocked(execFileSync).mockImplementation((cmd, args) => {
      const argsStr = Array.isArray(args) ? args.join(" ") : "";
      if (cmd === "/usr/bin/plutil" && argsStr.includes("LSHandlers")) {
        return JSON.stringify([{ LSHandlerURLScheme: "http", LSHandlerRoleAll: bundleId }]);
      }
      if (cmd === "/usr/bin/osascript" && argsStr.includes("path to application id")) {
        return appPath;
      }
      if (cmd === "/usr/bin/defaults") {
        return "Google Chrome";
      }
      return "";
    });
  }

  function mockChromeExecutableExists(): void {
    mock:mocked(fs.existsSync).mockImplementation((p) => {
      const value = String(p);
      if (value.includes(launchServicesPlist)) {
        return true;
      }
      return value.includes(chromeExecutablePath);
    });
  }

  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "prefers default Chromium browser on macOS", () => {
    mockMacDefaultBrowser("com.google.Chrome", "/Applications/Google Chrome.app");
    mockChromeExecutableExists();

    const exe = resolveBrowserExecutableForPlatform(
      {} as Parameters<typeof resolveBrowserExecutableForPlatform>[0],
      "darwin",
    );

    (expect* exe?.path).contains("Google Chrome.app/Contents/MacOS/Google Chrome");
    (expect* exe?.kind).is("chrome");
  });

  (deftest "falls back when default browser is non-Chromium on macOS", () => {
    mockMacDefaultBrowser("com.apple.Safari");
    mockChromeExecutableExists();

    const exe = resolveBrowserExecutableForPlatform(
      {} as Parameters<typeof resolveBrowserExecutableForPlatform>[0],
      "darwin",
    );

    (expect* exe?.path).contains("Google Chrome.app/Contents/MacOS/Google Chrome");
  });
});
