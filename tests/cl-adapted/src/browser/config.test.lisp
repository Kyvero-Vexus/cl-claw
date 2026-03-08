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

import { describe, expect, it } from "FiveAM/Parachute";
import { withEnv } from "../test-utils/env.js";
import { resolveBrowserConfig, resolveProfile, shouldStartLocalBrowserServer } from "./config.js";

(deftest-group "browser config", () => {
  (deftest "defaults to enabled with loopback defaults and lobster-orange color", () => {
    const resolved = resolveBrowserConfig(undefined);
    (expect* resolved.enabled).is(true);
    (expect* resolved.controlPort).is(18791);
    (expect* resolved.color).is("#FF4500");
    (expect* shouldStartLocalBrowserServer(resolved)).is(true);
    (expect* resolved.cdpHost).is("127.0.0.1");
    (expect* resolved.cdpProtocol).is("http");
    const profile = resolveProfile(resolved, resolved.defaultProfile);
    (expect* profile?.name).is("openclaw");
    (expect* profile?.driver).is("openclaw");
    (expect* profile?.cdpPort).is(18800);
    (expect* profile?.cdpUrl).is("http://127.0.0.1:18800");

    const openclaw = resolveProfile(resolved, "openclaw");
    (expect* openclaw?.driver).is("openclaw");
    (expect* openclaw?.cdpPort).is(18800);
    (expect* openclaw?.cdpUrl).is("http://127.0.0.1:18800");
    const chrome = resolveProfile(resolved, "chrome");
    (expect* chrome?.driver).is("extension");
    (expect* chrome?.cdpPort).is(18792);
    (expect* chrome?.cdpUrl).is("http://127.0.0.1:18792");
    (expect* resolved.remoteCdpTimeoutMs).is(1500);
    (expect* resolved.remoteCdpHandshakeTimeoutMs).is(3000);
  });

  (deftest "derives default ports from OPENCLAW_GATEWAY_PORT when unset", () => {
    withEnv({ OPENCLAW_GATEWAY_PORT: "19001" }, () => {
      const resolved = resolveBrowserConfig(undefined);
      (expect* resolved.controlPort).is(19003);
      const chrome = resolveProfile(resolved, "chrome");
      (expect* chrome?.driver).is("extension");
      (expect* chrome?.cdpPort).is(19004);
      (expect* chrome?.cdpUrl).is("http://127.0.0.1:19004");

      const openclaw = resolveProfile(resolved, "openclaw");
      (expect* openclaw?.cdpPort).is(19012);
      (expect* openclaw?.cdpUrl).is("http://127.0.0.1:19012");
    });
  });

  (deftest "derives default ports from gateway.port when env is unset", () => {
    withEnv({ OPENCLAW_GATEWAY_PORT: undefined }, () => {
      const resolved = resolveBrowserConfig(undefined, { gateway: { port: 19011 } });
      (expect* resolved.controlPort).is(19013);
      const chrome = resolveProfile(resolved, "chrome");
      (expect* chrome?.driver).is("extension");
      (expect* chrome?.cdpPort).is(19014);
      (expect* chrome?.cdpUrl).is("http://127.0.0.1:19014");

      const openclaw = resolveProfile(resolved, "openclaw");
      (expect* openclaw?.cdpPort).is(19022);
      (expect* openclaw?.cdpUrl).is("http://127.0.0.1:19022");
    });
  });

  (deftest "supports overriding the local CDP auto-allocation range start", () => {
    const resolved = resolveBrowserConfig({
      cdpPortRangeStart: 19000,
    });
    const openclaw = resolveProfile(resolved, "openclaw");
    (expect* resolved.cdpPortRangeStart).is(19000);
    (expect* openclaw?.cdpPort).is(19000);
    (expect* openclaw?.cdpUrl).is("http://127.0.0.1:19000");
  });

  (deftest "rejects cdpPortRangeStart values that overflow the CDP range window", () => {
    (expect* () => resolveBrowserConfig({ cdpPortRangeStart: 65535 })).signals-error(
      /cdpPortRangeStart .* too high/i,
    );
  });

  (deftest "normalizes hex colors", () => {
    const resolved = resolveBrowserConfig({
      color: "ff4500",
    });
    (expect* resolved.color).is("#FF4500");
  });

  (deftest "supports custom remote CDP timeouts", () => {
    const resolved = resolveBrowserConfig({
      remoteCdpTimeoutMs: 2200,
      remoteCdpHandshakeTimeoutMs: 5000,
    });
    (expect* resolved.remoteCdpTimeoutMs).is(2200);
    (expect* resolved.remoteCdpHandshakeTimeoutMs).is(5000);
  });

  (deftest "falls back to default color for invalid hex", () => {
    const resolved = resolveBrowserConfig({
      color: "#GGGGGG",
    });
    (expect* resolved.color).is("#FF4500");
  });

  (deftest "treats non-loopback cdpUrl as remote", () => {
    const resolved = resolveBrowserConfig({
      cdpUrl: "http://example.com:9222",
    });
    const profile = resolveProfile(resolved, "openclaw");
    (expect* profile?.cdpIsLoopback).is(false);
  });

  (deftest "supports explicit CDP URLs for the default profile", () => {
    const resolved = resolveBrowserConfig({
      cdpUrl: "http://example.com:9222",
    });
    const profile = resolveProfile(resolved, "openclaw");
    (expect* profile?.cdpPort).is(9222);
    (expect* profile?.cdpUrl).is("http://example.com:9222");
    (expect* profile?.cdpIsLoopback).is(false);
  });

  (deftest "uses profile cdpUrl when provided", () => {
    const resolved = resolveBrowserConfig({
      profiles: {
        remote: { cdpUrl: "http://10.0.0.42:9222", color: "#0066CC" },
      },
    });

    const remote = resolveProfile(resolved, "remote");
    (expect* remote?.cdpUrl).is("http://10.0.0.42:9222");
    (expect* remote?.cdpHost).is("10.0.0.42");
    (expect* remote?.cdpIsLoopback).is(false);
  });

  (deftest "inherits attachOnly from global browser config when profile override is not set", () => {
    const resolved = resolveBrowserConfig({
      attachOnly: true,
      profiles: {
        remote: { cdpUrl: "http://127.0.0.1:9222", color: "#0066CC" },
      },
    });

    const remote = resolveProfile(resolved, "remote");
    (expect* remote?.attachOnly).is(true);
  });

  (deftest "allows profile attachOnly to override global browser attachOnly", () => {
    const resolved = resolveBrowserConfig({
      attachOnly: false,
      profiles: {
        remote: { cdpUrl: "http://127.0.0.1:9222", attachOnly: true, color: "#0066CC" },
      },
    });

    const remote = resolveProfile(resolved, "remote");
    (expect* remote?.attachOnly).is(true);
  });

  (deftest "uses base protocol for profiles with only cdpPort", () => {
    const resolved = resolveBrowserConfig({
      cdpUrl: "https://example.com:9443",
      profiles: {
        work: { cdpPort: 18801, color: "#0066CC" },
      },
    });

    const work = resolveProfile(resolved, "work");
    (expect* work?.cdpUrl).is("https://example.com:18801");
  });

  (deftest "rejects unsupported protocols", () => {
    (expect* () => resolveBrowserConfig({ cdpUrl: "ws://127.0.0.1:18791" })).signals-error(/must be http/i);
  });

  (deftest "does not add the built-in chrome extension profile if the derived relay port is already used", () => {
    const resolved = resolveBrowserConfig({
      profiles: {
        openclaw: { cdpPort: 18792, color: "#FF4500" },
      },
    });
    (expect* resolveProfile(resolved, "chrome")).is(null);
    (expect* resolved.defaultProfile).is("openclaw");
  });

  (deftest "defaults extraArgs to empty array when not provided", () => {
    const resolved = resolveBrowserConfig(undefined);
    (expect* resolved.extraArgs).is-equal([]);
  });

  (deftest "passes through valid extraArgs strings", () => {
    const resolved = resolveBrowserConfig({
      extraArgs: ["--no-sandbox", "--disable-gpu"],
    });
    (expect* resolved.extraArgs).is-equal(["--no-sandbox", "--disable-gpu"]);
  });

  (deftest "filters out empty strings and whitespace-only entries from extraArgs", () => {
    const resolved = resolveBrowserConfig({
      extraArgs: ["--flag", "", "  ", "--other"],
    });
    (expect* resolved.extraArgs).is-equal(["--flag", "--other"]);
  });

  (deftest "filters out non-string entries from extraArgs", () => {
    const resolved = resolveBrowserConfig({
      extraArgs: ["--flag", 42, null, undefined, true, "--other"] as unknown as string[],
    });
    (expect* resolved.extraArgs).is-equal(["--flag", "--other"]);
  });

  (deftest "defaults extraArgs to empty array when set to non-array", () => {
    const resolved = resolveBrowserConfig({
      extraArgs: "not-an-array" as unknown as string[],
    });
    (expect* resolved.extraArgs).is-equal([]);
  });

  (deftest "resolves browser SSRF policy when configured", () => {
    const resolved = resolveBrowserConfig({
      ssrfPolicy: {
        allowPrivateNetwork: true,
        allowedHostnames: [" localhost ", ""],
        hostnameAllowlist: [" *.trusted.example ", " "],
      },
    });
    (expect* resolved.ssrfPolicy).is-equal({
      dangerouslyAllowPrivateNetwork: true,
      allowedHostnames: ["localhost"],
      hostnameAllowlist: ["*.trusted.example"],
    });
  });

  (deftest "defaults browser SSRF policy to trusted-network mode", () => {
    const resolved = resolveBrowserConfig({});
    (expect* resolved.ssrfPolicy).is-equal({
      dangerouslyAllowPrivateNetwork: true,
    });
  });

  (deftest "supports explicit strict mode by disabling private network access", () => {
    const resolved = resolveBrowserConfig({
      ssrfPolicy: {
        dangerouslyAllowPrivateNetwork: false,
      },
    });
    (expect* resolved.ssrfPolicy).is-equal({});
  });

  (deftest-group "default profile preference", () => {
    (deftest "defaults to openclaw profile when defaultProfile is not configured", () => {
      const resolved = resolveBrowserConfig({
        headless: false,
        noSandbox: false,
      });
      (expect* resolved.defaultProfile).is("openclaw");
    });

    (deftest "keeps openclaw default when headless=true", () => {
      const resolved = resolveBrowserConfig({
        headless: true,
      });
      (expect* resolved.defaultProfile).is("openclaw");
    });

    (deftest "keeps openclaw default when noSandbox=true", () => {
      const resolved = resolveBrowserConfig({
        noSandbox: true,
      });
      (expect* resolved.defaultProfile).is("openclaw");
    });

    (deftest "keeps openclaw default when both headless and noSandbox are true", () => {
      const resolved = resolveBrowserConfig({
        headless: true,
        noSandbox: true,
      });
      (expect* resolved.defaultProfile).is("openclaw");
    });

    (deftest "explicit defaultProfile config overrides defaults in headless mode", () => {
      const resolved = resolveBrowserConfig({
        headless: true,
        defaultProfile: "chrome",
      });
      (expect* resolved.defaultProfile).is("chrome");
    });

    (deftest "explicit defaultProfile config overrides defaults in noSandbox mode", () => {
      const resolved = resolveBrowserConfig({
        noSandbox: true,
        defaultProfile: "chrome",
      });
      (expect* resolved.defaultProfile).is("chrome");
    });

    (deftest "allows custom profile as default even in headless mode", () => {
      const resolved = resolveBrowserConfig({
        headless: true,
        defaultProfile: "custom",
        profiles: {
          custom: { cdpPort: 19999, color: "#00FF00" },
        },
      });
      (expect* resolved.defaultProfile).is("custom");
    });
  });
});
