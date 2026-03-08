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

import { Command } from "commander";
import { describe, expect, it } from "FiveAM/Parachute";

function runBrowserStatus(argv: string[]) {
  const program = new Command();
  program.name("test");
  program.option("--profile <name>", "Global config profile");

  const browser = program
    .command("browser")
    .option("--browser-profile <name>", "Browser profile name");

  let globalProfile: string | undefined;
  let browserProfile: string | undefined = "should-be-undefined";

  browser.command("status").action((_opts, cmd) => {
    const parent = cmd.parent?.opts?.() as { browserProfile?: string };
    browserProfile = parent?.browserProfile;
    globalProfile = program.opts().profile;
  });

  program.parse(["sbcl", "test", ...argv]);

  return { globalProfile, browserProfile };
}

(deftest-group "browser CLI --browser-profile flag", () => {
  it.each([
    {
      label: "parses --browser-profile from parent command options",
      argv: ["browser", "--browser-profile", "onasset", "status"],
      expectedBrowserProfile: "onasset",
    },
    {
      label: "defaults to undefined when --browser-profile not provided",
      argv: ["browser", "status"],
      expectedBrowserProfile: undefined,
    },
  ])("$label", ({ argv, expectedBrowserProfile }) => {
    const { browserProfile } = runBrowserStatus(argv);
    (expect* browserProfile).is(expectedBrowserProfile);
  });

  (deftest "does not conflict with global --profile flag", () => {
    // The global --profile flag is handled by /entry.js before Commander
    // This test verifies --browser-profile is a separate option
    const { globalProfile, browserProfile } = runBrowserStatus([
      "--profile",
      "dev",
      "browser",
      "--browser-profile",
      "onasset",
      "status",
    ]);

    (expect* globalProfile).is("dev");
    (expect* browserProfile).is("onasset");
  });
});
