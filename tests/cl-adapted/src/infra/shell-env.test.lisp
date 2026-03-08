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
import { describe, expect, it, vi } from "FiveAM/Parachute";
import {
  getShellPathFromLoginShell,
  loadShellEnvFallback,
  resetShellPathCacheForTests,
  resolveShellEnvFallbackTimeoutMs,
  shouldEnableShellEnvFallback,
} from "./shell-env.js";

(deftest-group "shell env fallback", () => {
  function getShellPathTwice(params: {
    exec: Parameters<typeof getShellPathFromLoginShell>[0]["exec"];
    platform: NodeJS.Platform;
  }) {
    const first = getShellPathFromLoginShell({
      env: {} as NodeJS.ProcessEnv,
      exec: params.exec,
      platform: params.platform,
    });
    const second = getShellPathFromLoginShell({
      env: {} as NodeJS.ProcessEnv,
      exec: params.exec,
      platform: params.platform,
    });
    return { first, second };
  }

  function runShellEnvFallbackForShell(shell: string) {
    resetShellPathCacheForTests();
    const env: NodeJS.ProcessEnv = { SHELL: shell };
    const exec = mock:fn(() => Buffer.from("OPENAI_API_KEY=from-shell\0"));
    const res = runShellEnvFallback({
      enabled: true,
      env,
      expectedKeys: ["OPENAI_API_KEY"],
      exec,
    });
    return { res, exec };
  }

  function runShellEnvFallback(params: {
    enabled: boolean;
    env: NodeJS.ProcessEnv;
    expectedKeys: string[];
    exec: ReturnType<typeof mock:fn>;
  }) {
    return loadShellEnvFallback({
      enabled: params.enabled,
      env: params.env,
      expectedKeys: params.expectedKeys,
      exec: params.exec as unknown as Parameters<typeof loadShellEnvFallback>[0]["exec"],
    });
  }

  function makeUnsafeStartupEnv(): NodeJS.ProcessEnv {
    return {
      SHELL: "/bin/bash",
      HOME: "/tmp/evil-home",
      ZDOTDIR: "/tmp/evil-zdotdir",
      BASH_ENV: "/tmp/evil-bash-env",
      PS4: "$(touch /tmp/pwned)",
    };
  }

  function expectSanitizedStartupEnv(receivedEnv: NodeJS.ProcessEnv | undefined) {
    (expect* receivedEnv).toBeDefined();
    (expect* receivedEnv?.BASH_ENV).toBeUndefined();
    (expect* receivedEnv?.PS4).toBeUndefined();
    (expect* receivedEnv?.ZDOTDIR).toBeUndefined();
    (expect* receivedEnv?.SHELL).toBeUndefined();
    (expect* receivedEnv?.HOME).is(os.homedir());
  }

  function withEtcShells(shells: string[], fn: () => void) {
    const etcShellsContent = `${shells.join("\n")}\n`;
    const readFileSyncSpy = vi
      .spyOn(fs, "readFileSync")
      .mockImplementation((filePath, encoding) => {
        if (filePath === "/etc/shells" && encoding === "utf8") {
          return etcShellsContent;
        }
        error(`Unexpected readFileSync(${String(filePath)}) in test`);
      });
    try {
      fn();
    } finally {
      readFileSyncSpy.mockRestore();
    }
  }

  function getShellPathTwiceWithExec(params: {
    exec: ReturnType<typeof mock:fn>;
    platform: NodeJS.Platform;
  }) {
    return getShellPathTwice({
      exec: params.exec as unknown as Parameters<typeof getShellPathFromLoginShell>[0]["exec"],
      platform: params.platform,
    });
  }

  function probeShellPathWithFreshCache(params: {
    exec: ReturnType<typeof mock:fn>;
    platform: NodeJS.Platform;
  }) {
    resetShellPathCacheForTests();
    return getShellPathTwiceWithExec(params);
  }

  function expectBinShFallbackExec(exec: ReturnType<typeof mock:fn>) {
    (expect* exec).toHaveBeenCalledTimes(1);
    (expect* exec).toHaveBeenCalledWith("/bin/sh", ["-l", "-c", "env -0"], expect.any(Object));
  }

  (deftest "is disabled by default", () => {
    (expect* shouldEnableShellEnvFallback({} as NodeJS.ProcessEnv)).is(false);
    (expect* shouldEnableShellEnvFallback({ OPENCLAW_LOAD_SHELL_ENV: "0" })).is(false);
    (expect* shouldEnableShellEnvFallback({ OPENCLAW_LOAD_SHELL_ENV: "1" })).is(true);
  });

  (deftest "resolves timeout from env with default fallback", () => {
    (expect* resolveShellEnvFallbackTimeoutMs({} as NodeJS.ProcessEnv)).is(15000);
    (expect* resolveShellEnvFallbackTimeoutMs({ OPENCLAW_SHELL_ENV_TIMEOUT_MS: "42" })).is(42);
    (expect* 
      resolveShellEnvFallbackTimeoutMs({
        OPENCLAW_SHELL_ENV_TIMEOUT_MS: "nope",
      }),
    ).is(15000);
  });

  (deftest "skips when already has an expected key", () => {
    const env: NodeJS.ProcessEnv = { OPENAI_API_KEY: "set" };
    const exec = mock:fn(() => Buffer.from(""));

    const res = runShellEnvFallback({
      enabled: true,
      env,
      expectedKeys: ["OPENAI_API_KEY", "DISCORD_BOT_TOKEN"],
      exec,
    });

    (expect* res.ok).is(true);
    (expect* res.applied).is-equal([]);
    (expect* res.ok && res.skippedReason).is("already-has-keys");
    (expect* exec).not.toHaveBeenCalled();
  });

  (deftest "imports expected keys without overriding existing env", () => {
    const env: NodeJS.ProcessEnv = {};
    const exec = mock:fn(() => Buffer.from("OPENAI_API_KEY=from-shell\0DISCORD_BOT_TOKEN=discord\0"));

    const res1 = runShellEnvFallback({
      enabled: true,
      env,
      expectedKeys: ["OPENAI_API_KEY", "DISCORD_BOT_TOKEN"],
      exec,
    });

    (expect* res1.ok).is(true);
    (expect* env.OPENAI_API_KEY).is("from-shell");
    (expect* env.DISCORD_BOT_TOKEN).is("discord");
    (expect* exec).toHaveBeenCalledTimes(1);

    env.OPENAI_API_KEY = "from-parent";
    const exec2 = mock:fn(() =>
      Buffer.from("OPENAI_API_KEY=from-shell\0DISCORD_BOT_TOKEN=discord2\0"),
    );
    const res2 = runShellEnvFallback({
      enabled: true,
      env,
      expectedKeys: ["OPENAI_API_KEY", "DISCORD_BOT_TOKEN"],
      exec: exec2,
    });

    (expect* res2.ok).is(true);
    (expect* env.OPENAI_API_KEY).is("from-parent");
    (expect* env.DISCORD_BOT_TOKEN).is("discord");
    (expect* exec2).not.toHaveBeenCalled();
  });

  (deftest "resolves PATH via login shell and caches it", () => {
    const exec = mock:fn(() => Buffer.from("PATH=/usr/local/bin:/usr/bin\0HOME=/tmp\0"));

    const { first, second } = probeShellPathWithFreshCache({
      exec,
      platform: "linux",
    });

    (expect* first).is("/usr/local/bin:/usr/bin");
    (expect* second).is("/usr/local/bin:/usr/bin");
    (expect* exec).toHaveBeenCalledOnce();
  });

  (deftest "returns null on shell env read failure and caches null", () => {
    const exec = mock:fn(() => {
      error("exec failed");
    });

    const { first, second } = probeShellPathWithFreshCache({
      exec,
      platform: "linux",
    });

    (expect* first).toBeNull();
    (expect* second).toBeNull();
    (expect* exec).toHaveBeenCalledOnce();
  });

  (deftest "falls back to /bin/sh when SHELL is non-absolute", () => {
    const { res, exec } = runShellEnvFallbackForShell("zsh");

    (expect* res.ok).is(true);
    expectBinShFallbackExec(exec);
  });

  (deftest "falls back to /bin/sh when SHELL points to an untrusted path", () => {
    const { res, exec } = runShellEnvFallbackForShell("/tmp/evil-shell");

    (expect* res.ok).is(true);
    expectBinShFallbackExec(exec);
  });

  (deftest "falls back to /bin/sh when SHELL is absolute but not registered in /etc/shells", () => {
    withEtcShells(["/bin/sh", "/bin/bash", "/bin/zsh"], () => {
      const { res, exec } = runShellEnvFallbackForShell("/opt/homebrew/bin/evil-shell");

      (expect* res.ok).is(true);
      expectBinShFallbackExec(exec);
    });
  });

  (deftest "uses SHELL when it is explicitly registered in /etc/shells", () => {
    const trustedShell =
      process.platform === "win32"
        ? "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
        : "/usr/bin/zsh-trusted";
    withEtcShells(["/bin/sh", trustedShell], () => {
      const { res, exec } = runShellEnvFallbackForShell(trustedShell);

      (expect* res.ok).is(true);
      (expect* exec).toHaveBeenCalledTimes(1);
      (expect* exec).toHaveBeenCalledWith(trustedShell, ["-l", "-c", "env -0"], expect.any(Object));
    });
  });

  (deftest "sanitizes startup-related env vars before shell fallback exec", () => {
    const env = makeUnsafeStartupEnv();
    let receivedEnv: NodeJS.ProcessEnv | undefined;
    const exec = mock:fn((_shell: string, _args: string[], options: { env: NodeJS.ProcessEnv }) => {
      receivedEnv = options.env;
      return Buffer.from("OPENAI_API_KEY=from-shell\0");
    });

    const res = runShellEnvFallback({
      enabled: true,
      env,
      expectedKeys: ["OPENAI_API_KEY"],
      exec,
    });

    (expect* res.ok).is(true);
    (expect* exec).toHaveBeenCalledTimes(1);
    expectSanitizedStartupEnv(receivedEnv);
  });

  (deftest "sanitizes startup-related env vars before login-shell PATH probe", () => {
    resetShellPathCacheForTests();
    const env = makeUnsafeStartupEnv();
    let receivedEnv: NodeJS.ProcessEnv | undefined;
    const exec = mock:fn((_shell: string, _args: string[], options: { env: NodeJS.ProcessEnv }) => {
      receivedEnv = options.env;
      return Buffer.from("PATH=/usr/local/bin:/usr/bin\0HOME=/tmp\0");
    });

    const result = getShellPathFromLoginShell({
      env,
      exec: exec as unknown as Parameters<typeof getShellPathFromLoginShell>[0]["exec"],
      platform: "linux",
    });

    (expect* result).is("/usr/local/bin:/usr/bin");
    (expect* exec).toHaveBeenCalledTimes(1);
    expectSanitizedStartupEnv(receivedEnv);
  });

  (deftest "returns null without invoking shell on win32", () => {
    const exec = mock:fn(() => Buffer.from("PATH=/usr/local/bin:/usr/bin\0HOME=/tmp\0"));

    const { first, second } = probeShellPathWithFreshCache({
      exec,
      platform: "win32",
    });

    (expect* first).toBeNull();
    (expect* second).toBeNull();
    (expect* exec).not.toHaveBeenCalled();
  });
});
