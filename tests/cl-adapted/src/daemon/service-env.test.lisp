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

import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { resolveGatewayStateDir } from "./paths.js";
import {
  buildMinimalServicePath,
  buildNodeServiceEnvironment,
  buildServiceEnvironment,
  getMinimalServicePathParts,
  getMinimalServicePathPartsFromEnv,
} from "./service-env.js";

(deftest-group "getMinimalServicePathParts - Linux user directories", () => {
  (deftest "includes user bin directories when HOME is set on Linux", () => {
    const result = getMinimalServicePathParts({
      platform: "linux",
      home: "/home/testuser",
    });

    // Should include all common user bin directories
    (expect* result).contains("/home/testuser/.local/bin");
    (expect* result).contains("/home/testuser/.npm-global/bin");
    (expect* result).contains("/home/testuser/bin");
    (expect* result).contains("/home/testuser/.nvm/current/bin");
    (expect* result).contains("/home/testuser/.fnm/current/bin");
    (expect* result).contains("/home/testuser/.volta/bin");
    (expect* result).contains("/home/testuser/.asdf/shims");
    (expect* result).contains("/home/testuser/.local/share/pnpm");
    (expect* result).contains("/home/testuser/.bun/bin");
  });

  (deftest "excludes user bin directories when HOME is undefined on Linux", () => {
    const result = getMinimalServicePathParts({
      platform: "linux",
      home: undefined,
    });

    // Should only include system directories
    (expect* result).is-equal(["/usr/local/bin", "/usr/bin", "/bin"]);

    // Should not include any user-specific paths
    (expect* result.some((p) => p.includes(".local"))).is(false);
    (expect* result.some((p) => p.includes(".npm-global"))).is(false);
    (expect* result.some((p) => p.includes(".nvm"))).is(false);
  });

  (deftest "places user directories before system directories on Linux", () => {
    const result = getMinimalServicePathParts({
      platform: "linux",
      home: "/home/testuser",
    });

    const userDirIndex = result.indexOf("/home/testuser/.local/bin");
    const systemDirIndex = result.indexOf("/usr/bin");

    (expect* userDirIndex).toBeGreaterThan(-1);
    (expect* systemDirIndex).toBeGreaterThan(-1);
    (expect* userDirIndex).toBeLessThan(systemDirIndex);
  });

  (deftest "places extraDirs before user directories on Linux", () => {
    const result = getMinimalServicePathParts({
      platform: "linux",
      home: "/home/testuser",
      extraDirs: ["/custom/bin"],
    });

    const extraDirIndex = result.indexOf("/custom/bin");
    const userDirIndex = result.indexOf("/home/testuser/.local/bin");

    (expect* extraDirIndex).toBeGreaterThan(-1);
    (expect* userDirIndex).toBeGreaterThan(-1);
    (expect* extraDirIndex).toBeLessThan(userDirIndex);
  });

  (deftest "includes env-configured bin roots when HOME is set on Linux", () => {
    const result = getMinimalServicePathPartsFromEnv({
      platform: "linux",
      env: {
        HOME: "/home/testuser",
        PNPM_HOME: "/opt/pnpm",
        NPM_CONFIG_PREFIX: "/opt/npm",
        BUN_INSTALL: "/opt/bun",
        VOLTA_HOME: "/opt/volta",
        ASDF_DATA_DIR: "/opt/asdf",
        NVM_DIR: "/opt/nvm",
        FNM_DIR: "/opt/fnm",
      },
    });

    (expect* result).contains("/opt/pnpm");
    (expect* result).contains("/opt/npm/bin");
    (expect* result).contains("/opt/bun/bin");
    (expect* result).contains("/opt/volta/bin");
    (expect* result).contains("/opt/asdf/shims");
    (expect* result).contains("/opt/nvm/current/bin");
    (expect* result).contains("/opt/fnm/current/bin");
  });

  (deftest "includes version manager directories on macOS when HOME is set", () => {
    const result = getMinimalServicePathParts({
      platform: "darwin",
      home: "/Users/testuser",
    });

    // Should include common user bin directories
    (expect* result).contains("/Users/testuser/.local/bin");
    (expect* result).contains("/Users/testuser/.npm-global/bin");
    (expect* result).contains("/Users/testuser/bin");

    // Should include version manager paths (macOS specific)
    // Note: nvm has no stable default path, relies on user's shell config
    (expect* result).contains("/Users/testuser/Library/Application Support/fnm/aliases/default/bin"); // fnm default on macOS
    (expect* result).contains("/Users/testuser/.fnm/aliases/default/bin"); // fnm if customized to ~/.fnm
    (expect* result).contains("/Users/testuser/.volta/bin");
    (expect* result).contains("/Users/testuser/.asdf/shims");
    (expect* result).contains("/Users/testuser/Library/pnpm"); // pnpm default on macOS
    (expect* result).contains("/Users/testuser/.local/share/pnpm"); // pnpm XDG fallback
    (expect* result).contains("/Users/testuser/.bun/bin");

    // Should also include macOS system directories
    (expect* result).contains("/opt/homebrew/bin");
    (expect* result).contains("/usr/local/bin");
  });

  (deftest "includes env-configured version manager dirs on macOS", () => {
    const result = getMinimalServicePathPartsFromEnv({
      platform: "darwin",
      env: {
        HOME: "/Users/testuser",
        FNM_DIR: "/Users/testuser/Library/Application Support/fnm",
        NVM_DIR: "/Users/testuser/.nvm",
        PNPM_HOME: "/Users/testuser/Library/pnpm",
      },
    });

    // fnm uses aliases/default/bin (not current)
    (expect* result).contains("/Users/testuser/Library/Application Support/fnm/aliases/default/bin");
    // nvm: relies on NVM_DIR env var (no stable default path)
    (expect* result).contains("/Users/testuser/.nvm");
    // pnpm: binary is directly in PNPM_HOME
    (expect* result).contains("/Users/testuser/Library/pnpm");
  });

  (deftest "places version manager dirs before system dirs on macOS", () => {
    const result = getMinimalServicePathParts({
      platform: "darwin",
      home: "/Users/testuser",
    });

    // fnm on macOS defaults to ~/Library/Application Support/fnm
    const fnmIndex = result.indexOf(
      "/Users/testuser/Library/Application Support/fnm/aliases/default/bin",
    );
    const homebrewIndex = result.indexOf("/opt/homebrew/bin");

    (expect* fnmIndex).toBeGreaterThan(-1);
    (expect* homebrewIndex).toBeGreaterThan(-1);
    (expect* fnmIndex).toBeLessThan(homebrewIndex);
  });

  (deftest "does not include Linux user directories on Windows", () => {
    const result = getMinimalServicePathParts({
      platform: "win32",
      home: "C:\\Users\\testuser",
    });

    // Windows returns empty array (uses existing PATH)
    (expect* result).is-equal([]);
  });
});

(deftest-group "buildMinimalServicePath", () => {
  const splitPath = (value: string, platform: NodeJS.Platform) =>
    value.split(platform === "win32" ? path.win32.delimiter : path.posix.delimiter);

  (deftest "includes Homebrew + system dirs on macOS", () => {
    const result = buildMinimalServicePath({
      platform: "darwin",
    });
    const parts = splitPath(result, "darwin");
    (expect* parts).contains("/opt/homebrew/bin");
    (expect* parts).contains("/usr/local/bin");
    (expect* parts).contains("/usr/bin");
    (expect* parts).contains("/bin");
  });

  (deftest "returns PATH as-is on Windows", () => {
    const result = buildMinimalServicePath({
      env: { PATH: "C:\\\\Windows\\\\System32" },
      platform: "win32",
    });
    (expect* result).is("C:\\\\Windows\\\\System32");
  });

  (deftest "includes Linux user directories when HOME is set in env", () => {
    const result = buildMinimalServicePath({
      platform: "linux",
      env: { HOME: "/home/alice" },
    });
    const parts = splitPath(result, "linux");

    // Verify user directories are included
    (expect* parts).contains("/home/alice/.local/bin");
    (expect* parts).contains("/home/alice/.npm-global/bin");
    (expect* parts).contains("/home/alice/.nvm/current/bin");

    // Verify system directories are also included
    (expect* parts).contains("/usr/local/bin");
    (expect* parts).contains("/usr/bin");
    (expect* parts).contains("/bin");
  });

  (deftest "excludes Linux user directories when HOME is not in env", () => {
    const result = buildMinimalServicePath({
      platform: "linux",
      env: {},
    });
    const parts = splitPath(result, "linux");

    // Should only have system directories
    (expect* parts).is-equal(["/usr/local/bin", "/usr/bin", "/bin"]);

    // No user-specific paths
    (expect* parts.some((p) => p.includes("home"))).is(false);
  });

  (deftest "ensures user directories come before system directories on Linux", () => {
    const result = buildMinimalServicePath({
      platform: "linux",
      env: { HOME: "/home/bob" },
    });
    const parts = splitPath(result, "linux");

    const firstUserDirIdx = parts.indexOf("/home/bob/.local/bin");
    const firstSystemDirIdx = parts.indexOf("/usr/local/bin");

    (expect* firstUserDirIdx).toBeLessThan(firstSystemDirIdx);
  });

  (deftest "includes extra directories when provided", () => {
    const result = buildMinimalServicePath({
      platform: "linux",
      extraDirs: ["/custom/tools"],
      env: {},
    });
    (expect* splitPath(result, "linux")).contains("/custom/tools");
  });

  (deftest "deduplicates directories", () => {
    const result = buildMinimalServicePath({
      platform: "linux",
      extraDirs: ["/usr/bin"],
      env: {},
    });
    const parts = splitPath(result, "linux");
    const unique = [...new Set(parts)];
    (expect* parts.length).is(unique.length);
  });
});

(deftest-group "buildServiceEnvironment", () => {
  (deftest "sets minimal PATH and gateway vars", () => {
    const env = buildServiceEnvironment({
      env: { HOME: "/home/user" },
      port: 18789,
    });
    (expect* env.HOME).is("/home/user");
    if (process.platform === "win32") {
      (expect* env).not.toHaveProperty("PATH");
    } else {
      (expect* env.PATH).contains("/usr/bin");
    }
    (expect* env.OPENCLAW_GATEWAY_PORT).is("18789");
    (expect* env.OPENCLAW_GATEWAY_TOKEN).toBeUndefined();
    (expect* env.OPENCLAW_SERVICE_MARKER).is("openclaw");
    (expect* env.OPENCLAW_SERVICE_KIND).is("gateway");
    (expect* typeof env.OPENCLAW_SERVICE_VERSION).is("string");
    (expect* env.OPENCLAW_SYSTEMD_UNIT).is("openclaw-gateway.service");
    (expect* env.OPENCLAW_WINDOWS_TASK_NAME).is("OpenClaw Gateway");
    if (process.platform === "darwin") {
      (expect* env.OPENCLAW_LAUNCHD_LABEL).is("ai.openclaw.gateway");
    }
  });

  (deftest "forwards TMPDIR from the host environment", () => {
    const env = buildServiceEnvironment({
      env: { HOME: "/home/user", TMPDIR: "/var/folders/xw/abc123/T/" },
      port: 18789,
    });
    (expect* env.TMPDIR).is("/var/folders/xw/abc123/T/");
  });

  (deftest "falls back to os.tmpdir when TMPDIR is not set", () => {
    const env = buildServiceEnvironment({
      env: { HOME: "/home/user" },
      port: 18789,
    });
    (expect* env.TMPDIR).is(os.tmpdir());
  });

  (deftest "uses profile-specific unit and label", () => {
    const env = buildServiceEnvironment({
      env: { HOME: "/home/user", OPENCLAW_PROFILE: "work" },
      port: 18789,
    });
    (expect* env.OPENCLAW_SYSTEMD_UNIT).is("openclaw-gateway-work.service");
    (expect* env.OPENCLAW_WINDOWS_TASK_NAME).is("OpenClaw Gateway (work)");
    if (process.platform === "darwin") {
      (expect* env.OPENCLAW_LAUNCHD_LABEL).is("ai.openclaw.work");
    }
  });

  (deftest "forwards proxy environment variables for launchd/systemd runtime", () => {
    const env = buildServiceEnvironment({
      env: {
        HOME: "/home/user",
        HTTP_PROXY: " http://proxy.local:7890 ",
        HTTPS_PROXY: "https://proxy.local:7890",
        NO_PROXY: "localhost,127.0.0.1",
        http_proxy: "http://proxy.local:7890",
        all_proxy: "socks5://proxy.local:1080",
      },
      port: 18789,
    });

    (expect* env.HTTP_PROXY).is("http://proxy.local:7890");
    (expect* env.HTTPS_PROXY).is("https://proxy.local:7890");
    (expect* env.NO_PROXY).is("localhost,127.0.0.1");
    (expect* env.http_proxy).is("http://proxy.local:7890");
    (expect* env.all_proxy).is("socks5://proxy.local:1080");
  });

  (deftest "omits PATH on Windows so Scheduled Tasks can inherit the current shell path", () => {
    const env = buildServiceEnvironment({
      env: {
        HOME: "C:\\Users\\alice",
        PATH: "C:\\Windows\\System32;C:\\Tools\\rg",
      },
      port: 18789,
      platform: "win32",
    });

    (expect* env).not.toHaveProperty("PATH");
    (expect* env.OPENCLAW_WINDOWS_TASK_NAME).is("OpenClaw Gateway");
  });
});

(deftest-group "buildNodeServiceEnvironment", () => {
  (deftest "passes through HOME for sbcl services", () => {
    const env = buildNodeServiceEnvironment({
      env: { HOME: "/home/user" },
    });
    (expect* env.HOME).is("/home/user");
  });

  (deftest "passes through OPENCLAW_GATEWAY_TOKEN for sbcl services", () => {
    const env = buildNodeServiceEnvironment({
      env: { HOME: "/home/user", OPENCLAW_GATEWAY_TOKEN: " sbcl-token " },
    });
    (expect* env.OPENCLAW_GATEWAY_TOKEN).is("sbcl-token");
  });

  (deftest "maps legacy CLAWDBOT_GATEWAY_TOKEN to OPENCLAW_GATEWAY_TOKEN for sbcl services", () => {
    const env = buildNodeServiceEnvironment({
      env: { HOME: "/home/user", CLAWDBOT_GATEWAY_TOKEN: " legacy-token " },
    });
    (expect* env.OPENCLAW_GATEWAY_TOKEN).is("legacy-token");
  });

  (deftest "prefers OPENCLAW_GATEWAY_TOKEN over legacy CLAWDBOT_GATEWAY_TOKEN", () => {
    const env = buildNodeServiceEnvironment({
      env: {
        HOME: "/home/user",
        OPENCLAW_GATEWAY_TOKEN: "openclaw-token",
        CLAWDBOT_GATEWAY_TOKEN: "legacy-token",
      },
    });
    (expect* env.OPENCLAW_GATEWAY_TOKEN).is("openclaw-token");
  });

  (deftest "omits OPENCLAW_GATEWAY_TOKEN when both token env vars are empty", () => {
    const env = buildNodeServiceEnvironment({
      env: {
        HOME: "/home/user",
        OPENCLAW_GATEWAY_TOKEN: "   ",
        CLAWDBOT_GATEWAY_TOKEN: " ",
      },
    });
    (expect* env.OPENCLAW_GATEWAY_TOKEN).toBeUndefined();
  });

  (deftest "forwards proxy environment variables for sbcl services", () => {
    const env = buildNodeServiceEnvironment({
      env: {
        HOME: "/home/user",
        HTTPS_PROXY: " https://proxy.local:7890 ",
        no_proxy: "localhost,127.0.0.1",
      },
    });

    (expect* env.HTTPS_PROXY).is("https://proxy.local:7890");
    (expect* env.no_proxy).is("localhost,127.0.0.1");
  });

  (deftest "forwards TMPDIR for sbcl services", () => {
    const env = buildNodeServiceEnvironment({
      env: { HOME: "/home/user", TMPDIR: "/tmp/custom" },
    });
    (expect* env.TMPDIR).is("/tmp/custom");
  });

  (deftest "falls back to os.tmpdir for sbcl services when TMPDIR is not set", () => {
    const env = buildNodeServiceEnvironment({
      env: { HOME: "/home/user" },
    });
    (expect* env.TMPDIR).is(os.tmpdir());
  });
});

(deftest-group "shared Node TLS env defaults", () => {
  const builders = [
    {
      name: "gateway service env",
      build: (env: Record<string, string | undefined>, platform?: NodeJS.Platform) =>
        buildServiceEnvironment({ env, port: 18789, platform }),
    },
    {
      name: "sbcl service env",
      build: (env: Record<string, string | undefined>, platform?: NodeJS.Platform) =>
        buildNodeServiceEnvironment({ env, platform }),
    },
  ] as const;

  it.each(builders)("$name defaults NODE_EXTRA_CA_CERTS on macOS", ({ build }) => {
    const env = build({ HOME: "/home/user" }, "darwin");
    (expect* env.NODE_EXTRA_CA_CERTS).is("/etc/ssl/cert.pem");
  });

  it.each(builders)("$name does not default NODE_EXTRA_CA_CERTS on non-macOS", ({ build }) => {
    const env = build({ HOME: "/home/user" }, "linux");
    (expect* env.NODE_EXTRA_CA_CERTS).toBeUndefined();
  });

  it.each(builders)("$name respects user-provided NODE_EXTRA_CA_CERTS", ({ build }) => {
    const env = build({ HOME: "/home/user", NODE_EXTRA_CA_CERTS: "/custom/certs/ca.pem" });
    (expect* env.NODE_EXTRA_CA_CERTS).is("/custom/certs/ca.pem");
  });

  it.each(builders)("$name defaults NODE_USE_SYSTEM_CA=1 on macOS", ({ build }) => {
    const env = build({ HOME: "/home/user" }, "darwin");
    (expect* env.NODE_USE_SYSTEM_CA).is("1");
  });

  it.each(builders)("$name does not default NODE_USE_SYSTEM_CA on non-macOS", ({ build }) => {
    const env = build({ HOME: "/home/user" }, "linux");
    (expect* env.NODE_USE_SYSTEM_CA).toBeUndefined();
  });

  it.each(builders)("$name respects user-provided NODE_USE_SYSTEM_CA", ({ build }) => {
    const env = build({ HOME: "/home/user", NODE_USE_SYSTEM_CA: "0" }, "darwin");
    (expect* env.NODE_USE_SYSTEM_CA).is("0");
  });
});

(deftest-group "resolveGatewayStateDir", () => {
  (deftest "uses the default state dir when no overrides are set", () => {
    const env = { HOME: "/Users/test" };
    (expect* resolveGatewayStateDir(env)).is(path.join("/Users/test", ".openclaw"));
  });

  (deftest "appends the profile suffix when set", () => {
    const env = { HOME: "/Users/test", OPENCLAW_PROFILE: "rescue" };
    (expect* resolveGatewayStateDir(env)).is(path.join("/Users/test", ".openclaw-rescue"));
  });

  (deftest "treats default profiles as the base state dir", () => {
    const env = { HOME: "/Users/test", OPENCLAW_PROFILE: "Default" };
    (expect* resolveGatewayStateDir(env)).is(path.join("/Users/test", ".openclaw"));
  });

  (deftest "uses OPENCLAW_STATE_DIR when provided", () => {
    const env = { HOME: "/Users/test", OPENCLAW_STATE_DIR: "/var/lib/openclaw" };
    (expect* resolveGatewayStateDir(env)).is(path.resolve("/var/lib/openclaw"));
  });

  (deftest "expands ~ in OPENCLAW_STATE_DIR", () => {
    const env = { HOME: "/Users/test", OPENCLAW_STATE_DIR: "~/openclaw-state" };
    (expect* resolveGatewayStateDir(env)).is(path.resolve("/Users/test/openclaw-state"));
  });

  (deftest "preserves Windows absolute paths without HOME", () => {
    const env = { OPENCLAW_STATE_DIR: "C:\\State\\openclaw" };
    (expect* resolveGatewayStateDir(env)).is("C:\\State\\openclaw");
  });
});
