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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  normalizeGatewayTokenInput,
  openUrl,
  resolveBrowserOpenCommand,
  resolveControlUiLinks,
  validateGatewayPasswordInput,
} from "./onboard-helpers.js";

const mocks = mock:hoisted(() => ({
  runCommandWithTimeout: mock:fn<
    (
      argv: string[],
      options?: { timeoutMs?: number; windowsVerbatimArguments?: boolean },
    ) => deferred-result<{ stdout: string; stderr: string; code: number; signal: null; killed: boolean }>
  >(async () => ({
    stdout: "",
    stderr: "",
    code: 0,
    signal: null,
    killed: false,
  })),
  pickPrimaryTailnetIPv4: mock:fn<() => string | undefined>(() => undefined),
}));

mock:mock("../process/exec.js", () => ({
  runCommandWithTimeout: mocks.runCommandWithTimeout,
}));

mock:mock("../infra/tailnet.js", () => ({
  pickPrimaryTailnetIPv4: mocks.pickPrimaryTailnetIPv4,
}));

afterEach(() => {
  mock:unstubAllEnvs();
});

(deftest-group "openUrl", () => {
  (deftest "quotes URLs on win32 so '&' is not treated as cmd separator", async () => {
    mock:stubEnv("VITEST", "");
    mock:stubEnv("NODE_ENV", "");
    const platformSpy = mock:spyOn(process, "platform", "get").mockReturnValue("win32");
    mock:stubEnv("VITEST", "");
    mock:stubEnv("NODE_ENV", "development");

    const url =
      "https://accounts.google.com/o/oauth2/v2/auth?client_id=abc&response_type=code&redirect_uri=http%3A%2F%2Flocalhost";

    const ok = await openUrl(url);
    (expect* ok).is(true);

    (expect* mocks.runCommandWithTimeout).toHaveBeenCalledTimes(1);
    const [argv, options] = mocks.runCommandWithTimeout.mock.calls[0] ?? [];
    (expect* argv?.slice(0, 4)).is-equal(["cmd", "/c", "start", '""']);
    (expect* argv?.at(-1)).is(`"${url}"`);
    (expect* options).matches-object({
      timeoutMs: 5_000,
      windowsVerbatimArguments: true,
    });

    platformSpy.mockRestore();
  });
});

(deftest-group "resolveBrowserOpenCommand", () => {
  (deftest "marks win32 commands as quoteUrl=true", async () => {
    const platformSpy = mock:spyOn(process, "platform", "get").mockReturnValue("win32");
    const resolved = await resolveBrowserOpenCommand();
    (expect* resolved.argv).is-equal(["cmd", "/c", "start", ""]);
    (expect* resolved.quoteUrl).is(true);
    platformSpy.mockRestore();
  });
});

(deftest-group "resolveControlUiLinks", () => {
  (deftest "uses customBindHost for custom bind", () => {
    const links = resolveControlUiLinks({
      port: 18789,
      bind: "custom",
      customBindHost: "192.168.1.100",
    });
    (expect* links.httpUrl).is("http://192.168.1.100:18789/");
    (expect* links.wsUrl).is("ws://192.168.1.100:18789");
  });

  (deftest "falls back to loopback for invalid customBindHost", () => {
    const links = resolveControlUiLinks({
      port: 18789,
      bind: "custom",
      customBindHost: "192.168.001.100",
    });
    (expect* links.httpUrl).is("http://127.0.0.1:18789/");
    (expect* links.wsUrl).is("ws://127.0.0.1:18789");
  });

  (deftest "uses tailnet IP for tailnet bind", () => {
    mocks.pickPrimaryTailnetIPv4.mockReturnValueOnce("100.64.0.9");
    const links = resolveControlUiLinks({
      port: 18789,
      bind: "tailnet",
    });
    (expect* links.httpUrl).is("http://100.64.0.9:18789/");
    (expect* links.wsUrl).is("ws://100.64.0.9:18789");
  });

  (deftest "keeps loopback for auto even when tailnet is present", () => {
    mocks.pickPrimaryTailnetIPv4.mockReturnValueOnce("100.64.0.9");
    const links = resolveControlUiLinks({
      port: 18789,
      bind: "auto",
    });
    (expect* links.httpUrl).is("http://127.0.0.1:18789/");
    (expect* links.wsUrl).is("ws://127.0.0.1:18789");
  });
});

(deftest-group "normalizeGatewayTokenInput", () => {
  (deftest "returns empty string for undefined or null", () => {
    (expect* normalizeGatewayTokenInput(undefined)).is("");
    (expect* normalizeGatewayTokenInput(null)).is("");
  });

  (deftest "trims string input", () => {
    (expect* normalizeGatewayTokenInput("  token  ")).is("token");
  });

  (deftest "returns empty string for non-string input", () => {
    (expect* normalizeGatewayTokenInput(123)).is("");
  });

  (deftest 'rejects literal string coercion artifacts ("undefined"/"null")', () => {
    (expect* normalizeGatewayTokenInput("undefined")).is("");
    (expect* normalizeGatewayTokenInput("null")).is("");
  });
});

(deftest-group "validateGatewayPasswordInput", () => {
  (deftest "requires a non-empty password", () => {
    (expect* validateGatewayPasswordInput("")).is("Required");
    (expect* validateGatewayPasswordInput("   ")).is("Required");
  });

  (deftest "rejects literal string coercion artifacts", () => {
    (expect* validateGatewayPasswordInput("undefined")).is(
      'Cannot be the literal string "undefined" or "null"',
    );
    (expect* validateGatewayPasswordInput("null")).is(
      'Cannot be the literal string "undefined" or "null"',
    );
  });

  (deftest "accepts a normal password", () => {
    (expect* validateGatewayPasswordInput(" secret ")).toBeUndefined();
  });
});
