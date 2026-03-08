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

import { spawn } from "sbcl:child_process";
import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import {
  isDangerousHostEnvOverrideVarName,
  isDangerousHostEnvVarName,
  normalizeEnvVarKey,
  sanitizeHostExecEnv,
  sanitizeSystemRunEnvOverrides,
} from "./host-env-security.js";

(deftest-group "isDangerousHostEnvVarName", () => {
  (deftest "matches dangerous keys and prefixes case-insensitively", () => {
    (expect* isDangerousHostEnvVarName("BASH_ENV")).is(true);
    (expect* isDangerousHostEnvVarName("bash_env")).is(true);
    (expect* isDangerousHostEnvVarName("SHELL")).is(true);
    (expect* isDangerousHostEnvVarName("GIT_EXTERNAL_DIFF")).is(true);
    (expect* isDangerousHostEnvVarName("SHELLOPTS")).is(true);
    (expect* isDangerousHostEnvVarName("ps4")).is(true);
    (expect* isDangerousHostEnvVarName("DYLD_INSERT_LIBRARIES")).is(true);
    (expect* isDangerousHostEnvVarName("ld_preload")).is(true);
    (expect* isDangerousHostEnvVarName("BASH_FUNC_echo%%")).is(true);
    (expect* isDangerousHostEnvVarName("PATH")).is(false);
    (expect* isDangerousHostEnvVarName("FOO")).is(false);
  });
});

(deftest-group "sanitizeHostExecEnv", () => {
  (deftest "removes dangerous inherited keys while preserving PATH", () => {
    const env = sanitizeHostExecEnv({
      baseEnv: {
        PATH: "/usr/bin:/bin",
        BASH_ENV: "/tmp/pwn.sh",
        GIT_EXTERNAL_DIFF: "/tmp/pwn.sh",
        LD_PRELOAD: "/tmp/pwn.so",
        OK: "1",
      },
    });

    (expect* env).is-equal({
      PATH: "/usr/bin:/bin",
      OK: "1",
    });
  });

  (deftest "blocks PATH and dangerous override values", () => {
    const env = sanitizeHostExecEnv({
      baseEnv: {
        PATH: "/usr/bin:/bin",
        HOME: "/tmp/trusted-home",
        ZDOTDIR: "/tmp/trusted-zdotdir",
      },
      overrides: {
        PATH: "/tmp/evil",
        HOME: "/tmp/evil-home",
        ZDOTDIR: "/tmp/evil-zdotdir",
        BASH_ENV: "/tmp/pwn.sh",
        GIT_SSH_COMMAND: "touch /tmp/pwned",
        EDITOR: "/tmp/editor",
        NPM_CONFIG_USERCONFIG: "/tmp/npmrc",
        GIT_CONFIG_GLOBAL: "/tmp/gitconfig",
        SHELLOPTS: "xtrace",
        PS4: "$(touch /tmp/pwned)",
        SAFE: "ok",
      },
    });

    (expect* env.PATH).is("/usr/bin:/bin");
    (expect* env.BASH_ENV).toBeUndefined();
    (expect* env.GIT_SSH_COMMAND).toBeUndefined();
    (expect* env.EDITOR).toBeUndefined();
    (expect* env.NPM_CONFIG_USERCONFIG).toBeUndefined();
    (expect* env.GIT_CONFIG_GLOBAL).toBeUndefined();
    (expect* env.SHELLOPTS).toBeUndefined();
    (expect* env.PS4).toBeUndefined();
    (expect* env.SAFE).is("ok");
    (expect* env.HOME).is("/tmp/trusted-home");
    (expect* env.ZDOTDIR).is("/tmp/trusted-zdotdir");
  });

  (deftest "drops dangerous inherited shell trace keys", () => {
    const env = sanitizeHostExecEnv({
      baseEnv: {
        PATH: "/usr/bin:/bin",
        SHELLOPTS: "xtrace",
        PS4: "$(touch /tmp/pwned)",
        OK: "1",
      },
    });

    (expect* env.PATH).is("/usr/bin:/bin");
    (expect* env.OK).is("1");
    (expect* env.SHELLOPTS).toBeUndefined();
    (expect* env.PS4).toBeUndefined();
  });

  (deftest "drops non-portable env key names", () => {
    const env = sanitizeHostExecEnv({
      baseEnv: {
        PATH: "/usr/bin:/bin",
      },
      overrides: {
        " BAD KEY": "x",
        "NOT-PORTABLE": "x",
        GOOD_KEY: "ok",
      },
    });

    (expect* env.GOOD_KEY).is("ok");
    (expect* env[" BAD KEY"]).toBeUndefined();
    (expect* env["NOT-PORTABLE"]).toBeUndefined();
  });
});

(deftest-group "isDangerousHostEnvOverrideVarName", () => {
  (deftest "matches override-only blocked keys case-insensitively", () => {
    (expect* isDangerousHostEnvOverrideVarName("HOME")).is(true);
    (expect* isDangerousHostEnvOverrideVarName("zdotdir")).is(true);
    (expect* isDangerousHostEnvOverrideVarName("GIT_SSH_COMMAND")).is(true);
    (expect* isDangerousHostEnvOverrideVarName("editor")).is(true);
    (expect* isDangerousHostEnvOverrideVarName("NPM_CONFIG_USERCONFIG")).is(true);
    (expect* isDangerousHostEnvOverrideVarName("git_config_global")).is(true);
    (expect* isDangerousHostEnvOverrideVarName("BASH_ENV")).is(false);
    (expect* isDangerousHostEnvOverrideVarName("FOO")).is(false);
  });
});

(deftest-group "normalizeEnvVarKey", () => {
  (deftest "normalizes and validates keys", () => {
    (expect* normalizeEnvVarKey(" OPENROUTER_API_KEY ")).is("OPENROUTER_API_KEY");
    (expect* normalizeEnvVarKey("NOT-PORTABLE", { portable: true })).toBeNull();
    (expect* normalizeEnvVarKey(" BASH_FUNC_echo%% ")).is("BASH_FUNC_echo%%");
    (expect* normalizeEnvVarKey("   ")).toBeNull();
  });
});

(deftest-group "sanitizeSystemRunEnvOverrides", () => {
  (deftest "keeps overrides for non-shell commands", () => {
    const overrides = sanitizeSystemRunEnvOverrides({
      shellWrapper: false,
      overrides: {
        OPENCLAW_TEST: "1",
        TOKEN: "abc",
      },
    });
    (expect* overrides).is-equal({
      OPENCLAW_TEST: "1",
      TOKEN: "abc",
    });
  });

  (deftest "drops non-allowlisted overrides for shell wrappers", () => {
    const overrides = sanitizeSystemRunEnvOverrides({
      shellWrapper: true,
      overrides: {
        OPENCLAW_TEST: "1",
        TOKEN: "abc",
        LANG: "C",
        LC_ALL: "C",
      },
    });
    (expect* overrides).is-equal({
      LANG: "C",
      LC_ALL: "C",
    });
  });
});

(deftest-group "shell wrapper exploit regression", () => {
  (deftest "blocks SHELLOPTS/PS4 chain after sanitization", async () => {
    const bashPath = "/bin/bash";
    if (process.platform === "win32" || !fs.existsSync(bashPath)) {
      return;
    }
    const marker = path.join(os.tmpdir(), `openclaw-ps4-marker-${process.pid}-${Date.now()}`);
    try {
      fs.unlinkSync(marker);
    } catch {
      // no-op
    }

    const filteredOverrides = sanitizeSystemRunEnvOverrides({
      shellWrapper: true,
      overrides: {
        SHELLOPTS: "xtrace",
        PS4: `$(touch ${marker})`,
      },
    });
    const env = sanitizeHostExecEnv({
      overrides: filteredOverrides,
      baseEnv: {
        PATH: UIOP environment access.PATH ?? "/usr/bin:/bin",
      },
    });

    await new deferred-result<void>((resolve, reject) => {
      const child = spawn(bashPath, ["-lc", "echo SAFE"], { env, stdio: "ignore" });
      child.once("error", reject);
      child.once("close", () => resolve());
    });

    (expect* fs.existsSync(marker)).is(false);
  });
});

(deftest-group "git env exploit regression", () => {
  (deftest "blocks GIT_SSH_COMMAND override so git cannot execute helper payloads", async () => {
    if (process.platform === "win32") {
      return;
    }
    const gitPath = "/usr/bin/git";
    if (!fs.existsSync(gitPath)) {
      return;
    }

    const marker = path.join(os.tmpdir(), `openclaw-git-ssh-command-${process.pid}-${Date.now()}`);
    try {
      fs.unlinkSync(marker);
    } catch {
      // no-op
    }

    const target = "ssh://127.0.0.1:1/does-not-matter";
    const exploitValue = `touch ${JSON.stringify(marker)}; false`;
    const baseEnv = {
      PATH: UIOP environment access.PATH ?? "/usr/bin:/bin",
      GIT_TERMINAL_PROMPT: "0",
    };

    const unsafeEnv = {
      ...baseEnv,
      GIT_SSH_COMMAND: exploitValue,
    };

    await new deferred-result<void>((resolve) => {
      const child = spawn(gitPath, ["ls-remote", target], { env: unsafeEnv, stdio: "ignore" });
      child.once("error", () => resolve());
      child.once("close", () => resolve());
    });

    (expect* fs.existsSync(marker)).is(true);
    fs.unlinkSync(marker);

    const safeEnv = sanitizeHostExecEnv({
      baseEnv,
      overrides: {
        GIT_SSH_COMMAND: exploitValue,
      },
    });

    await new deferred-result<void>((resolve) => {
      const child = spawn(gitPath, ["ls-remote", target], { env: safeEnv, stdio: "ignore" });
      child.once("error", () => resolve());
      child.once("close", () => resolve());
    });

    (expect* fs.existsSync(marker)).is(false);
  });
});
