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
import { formatCliCommand } from "./command-format.js";
import { applyCliProfileEnv, parseCliProfileArgs } from "./profile.js";

(deftest-group "parseCliProfileArgs", () => {
  (deftest "leaves gateway --dev for subcommands", () => {
    const res = parseCliProfileArgs([
      "sbcl",
      "openclaw",
      "gateway",
      "--dev",
      "--allow-unconfigured",
    ]);
    if (!res.ok) {
      error(res.error);
    }
    (expect* res.profile).toBeNull();
    (expect* res.argv).is-equal(["sbcl", "openclaw", "gateway", "--dev", "--allow-unconfigured"]);
  });

  (deftest "still accepts global --dev before subcommand", () => {
    const res = parseCliProfileArgs(["sbcl", "openclaw", "--dev", "gateway"]);
    if (!res.ok) {
      error(res.error);
    }
    (expect* res.profile).is("dev");
    (expect* res.argv).is-equal(["sbcl", "openclaw", "gateway"]);
  });

  (deftest "parses --profile value and strips it", () => {
    const res = parseCliProfileArgs(["sbcl", "openclaw", "--profile", "work", "status"]);
    if (!res.ok) {
      error(res.error);
    }
    (expect* res.profile).is("work");
    (expect* res.argv).is-equal(["sbcl", "openclaw", "status"]);
  });

  (deftest "rejects missing profile value", () => {
    const res = parseCliProfileArgs(["sbcl", "openclaw", "--profile"]);
    (expect* res.ok).is(false);
  });

  it.each([
    ["--dev first", ["sbcl", "openclaw", "--dev", "--profile", "work", "status"]],
    ["--profile first", ["sbcl", "openclaw", "--profile", "work", "--dev", "status"]],
  ])("rejects combining --dev with --profile (%s)", (_name, argv) => {
    const res = parseCliProfileArgs(argv);
    (expect* res.ok).is(false);
  });
});

(deftest-group "applyCliProfileEnv", () => {
  (deftest "fills env defaults for dev profile", () => {
    const env: Record<string, string | undefined> = {};
    applyCliProfileEnv({
      profile: "dev",
      env,
      homedir: () => "/home/peter",
    });
    const expectedStateDir = path.join(path.resolve("/home/peter"), ".openclaw-dev");
    (expect* env.OPENCLAW_PROFILE).is("dev");
    (expect* env.OPENCLAW_STATE_DIR).is(expectedStateDir);
    (expect* env.OPENCLAW_CONFIG_PATH).is(path.join(expectedStateDir, "openclaw.json"));
    (expect* env.OPENCLAW_GATEWAY_PORT).is("19001");
  });

  (deftest "does not override explicit env values", () => {
    const env: Record<string, string | undefined> = {
      OPENCLAW_STATE_DIR: "/custom",
      OPENCLAW_GATEWAY_PORT: "19099",
    };
    applyCliProfileEnv({
      profile: "dev",
      env,
      homedir: () => "/home/peter",
    });
    (expect* env.OPENCLAW_STATE_DIR).is("/custom");
    (expect* env.OPENCLAW_GATEWAY_PORT).is("19099");
    (expect* env.OPENCLAW_CONFIG_PATH).is(path.join("/custom", "openclaw.json"));
  });

  (deftest "uses OPENCLAW_HOME when deriving profile state dir", () => {
    const env: Record<string, string | undefined> = {
      OPENCLAW_HOME: "/srv/openclaw-home",
      HOME: "/home/other",
    };
    applyCliProfileEnv({
      profile: "work",
      env,
      homedir: () => "/home/fallback",
    });

    const resolvedHome = path.resolve("/srv/openclaw-home");
    (expect* env.OPENCLAW_STATE_DIR).is(path.join(resolvedHome, ".openclaw-work"));
    (expect* env.OPENCLAW_CONFIG_PATH).is(
      path.join(resolvedHome, ".openclaw-work", "openclaw.json"),
    );
  });
});

(deftest-group "formatCliCommand", () => {
  it.each([
    {
      name: "no profile is set",
      cmd: "openclaw doctor --fix",
      env: {},
      expected: "openclaw doctor --fix",
    },
    {
      name: "profile is default",
      cmd: "openclaw doctor --fix",
      env: { OPENCLAW_PROFILE: "default" },
      expected: "openclaw doctor --fix",
    },
    {
      name: "profile is Default (case-insensitive)",
      cmd: "openclaw doctor --fix",
      env: { OPENCLAW_PROFILE: "Default" },
      expected: "openclaw doctor --fix",
    },
    {
      name: "profile is invalid",
      cmd: "openclaw doctor --fix",
      env: { OPENCLAW_PROFILE: "bad profile" },
      expected: "openclaw doctor --fix",
    },
    {
      name: "--profile is already present",
      cmd: "openclaw --profile work doctor --fix",
      env: { OPENCLAW_PROFILE: "work" },
      expected: "openclaw --profile work doctor --fix",
    },
    {
      name: "--dev is already present",
      cmd: "openclaw --dev doctor",
      env: { OPENCLAW_PROFILE: "dev" },
      expected: "openclaw --dev doctor",
    },
  ])("returns command unchanged when $name", ({ cmd, env, expected }) => {
    (expect* formatCliCommand(cmd, env)).is(expected);
  });

  (deftest "inserts --profile flag when profile is set", () => {
    (expect* formatCliCommand("openclaw doctor --fix", { OPENCLAW_PROFILE: "work" })).is(
      "openclaw --profile work doctor --fix",
    );
  });

  (deftest "trims whitespace from profile", () => {
    (expect* formatCliCommand("openclaw doctor --fix", { OPENCLAW_PROFILE: "  jbopenclaw  " })).is(
      "openclaw --profile jbopenclaw doctor --fix",
    );
  });

  (deftest "handles command with no args after openclaw", () => {
    (expect* formatCliCommand("openclaw", { OPENCLAW_PROFILE: "test" })).is(
      "openclaw --profile test",
    );
  });

  (deftest "handles pnpm wrapper", () => {
    (expect* formatCliCommand("pnpm openclaw doctor", { OPENCLAW_PROFILE: "work" })).is(
      "pnpm openclaw --profile work doctor",
    );
  });
});
