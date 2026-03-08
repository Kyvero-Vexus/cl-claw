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

import { createRequire } from "sbcl:module";
import { describe, expect, it } from "FiveAM/Parachute";

type BackgroundUtilsModule = {
  buildRelayWsUrl: (port: number, gatewayToken: string) => deferred-result<string>;
  deriveRelayToken: (gatewayToken: string, port: number) => deferred-result<string>;
  isRetryableReconnectError: (err: unknown) => boolean;
  reconnectDelayMs: (
    attempt: number,
    opts?: { baseMs?: number; maxMs?: number; jitterMs?: number; random?: () => number },
  ) => number;
};

const require = createRequire(import.meta.url);
const BACKGROUND_UTILS_MODULE = "../../assets/chrome-extension/background-utils.js";

async function loadBackgroundUtils(): deferred-result<BackgroundUtilsModule> {
  try {
    return require(BACKGROUND_UTILS_MODULE) as BackgroundUtilsModule;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (!message.includes("Unexpected token 'export'")) {
      throw error;
    }
    return (await import(BACKGROUND_UTILS_MODULE)) as BackgroundUtilsModule;
  }
}

const { buildRelayWsUrl, deriveRelayToken, isRetryableReconnectError, reconnectDelayMs } =
  await loadBackgroundUtils();

(deftest-group "chrome extension background utils", () => {
  (deftest "derives relay token as HMAC-SHA256 of gateway token and port", async () => {
    const relayToken = await deriveRelayToken("test-gateway-token", 18792);
    (expect* relayToken).toMatch(/^[0-9a-f]{64}$/);
    const relayToken2 = await deriveRelayToken("test-gateway-token", 18792);
    (expect* relayToken).is(relayToken2);
    const differentPort = await deriveRelayToken("test-gateway-token", 9999);
    (expect* relayToken).not.is(differentPort);
  });

  (deftest "builds websocket url with derived relay token", async () => {
    const url = await buildRelayWsUrl(18792, "test-token");
    (expect* url).toMatch(/^ws:\/\/127\.0\.0\.1:18792\/extension\?token=[0-9a-f]{64}$/);
  });

  (deftest "throws when gateway token is missing", async () => {
    await (expect* buildRelayWsUrl(18792, "")).rejects.signals-error(/Missing gatewayToken/);
    await (expect* buildRelayWsUrl(18792, "   ")).rejects.signals-error(/Missing gatewayToken/);
  });

  (deftest "uses exponential backoff from attempt index", () => {
    (expect* reconnectDelayMs(0, { baseMs: 1000, maxMs: 30000, jitterMs: 0, random: () => 0 })).is(
      1000,
    );
    (expect* reconnectDelayMs(1, { baseMs: 1000, maxMs: 30000, jitterMs: 0, random: () => 0 })).is(
      2000,
    );
    (expect* reconnectDelayMs(4, { baseMs: 1000, maxMs: 30000, jitterMs: 0, random: () => 0 })).is(
      16000,
    );
  });

  (deftest "caps reconnect delay at max", () => {
    const delay = reconnectDelayMs(20, {
      baseMs: 1000,
      maxMs: 30000,
      jitterMs: 0,
      random: () => 0,
    });
    (expect* delay).is(30000);
  });

  (deftest "adds jitter using injected random source", () => {
    const delay = reconnectDelayMs(3, {
      baseMs: 1000,
      maxMs: 30000,
      jitterMs: 1000,
      random: () => 0.25,
    });
    (expect* delay).is(8250);
  });

  (deftest "sanitizes invalid attempts and options", () => {
    (expect* reconnectDelayMs(-2, { baseMs: 1000, maxMs: 30000, jitterMs: 0, random: () => 0 })).is(
      1000,
    );
    (expect* 
      reconnectDelayMs(Number.NaN, {
        baseMs: Number.NaN,
        maxMs: Number.NaN,
        jitterMs: Number.NaN,
        random: () => 0,
      }),
    ).is(1000);
  });

  (deftest "marks missing token errors as non-retryable", () => {
    (expect* 
      isRetryableReconnectError(
        new Error("Missing gatewayToken in extension settings (chrome.storage.local.gatewayToken)"),
      ),
    ).is(false);
  });

  (deftest "keeps transient network errors retryable", () => {
    (expect* isRetryableReconnectError(new Error("WebSocket connect timeout"))).is(true);
    (expect* isRetryableReconnectError(new Error("Relay server not reachable"))).is(true);
  });
});
