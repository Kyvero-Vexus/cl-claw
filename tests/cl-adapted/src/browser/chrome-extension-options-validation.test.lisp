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

type RelayCheckResponse = {
  status?: number;
  ok?: boolean;
  error?: string;
  contentType?: string;
  json?: unknown;
};

type RelayCheckStatus =
  | { action: "throw"; error: string }
  | { action: "status"; kind: "ok" | "error"; message: string };

type RelayCheckExceptionStatus = { kind: "error"; message: string };

type OptionsValidationModule = {
  classifyRelayCheckResponse: (
    res: RelayCheckResponse | null | undefined,
    port: number,
  ) => RelayCheckStatus;
  classifyRelayCheckException: (err: unknown, port: number) => RelayCheckExceptionStatus;
};

const require = createRequire(import.meta.url);
const OPTIONS_VALIDATION_MODULE = "../../assets/chrome-extension/options-validation.js";

async function loadOptionsValidation(): deferred-result<OptionsValidationModule> {
  try {
    return require(OPTIONS_VALIDATION_MODULE) as OptionsValidationModule;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (!message.includes("Unexpected token 'export'")) {
      throw error;
    }
    return (await import(OPTIONS_VALIDATION_MODULE)) as OptionsValidationModule;
  }
}

const { classifyRelayCheckException, classifyRelayCheckResponse } = await loadOptionsValidation();

(deftest-group "chrome extension options validation", () => {
  (deftest "maps 401 response to token rejected error", () => {
    const result = classifyRelayCheckResponse({ status: 401, ok: false }, 18792);
    (expect* result).is-equal({
      action: "status",
      kind: "error",
      message: "Gateway token rejected. Check token and save again.",
    });
  });

  (deftest "maps non-json 200 response to wrong-port error", () => {
    const result = classifyRelayCheckResponse(
      { status: 200, ok: true, contentType: "text/html; charset=utf-8", json: null },
      18792,
    );
    (expect* result).is-equal({
      action: "status",
      kind: "error",
      message:
        "Wrong port: this is likely the gateway, not the relay. Use gateway port + 3 (for gateway 18789, relay is 18792).",
    });
  });

  (deftest "maps json response without CDP keys to wrong-port error", () => {
    const result = classifyRelayCheckResponse(
      { status: 200, ok: true, contentType: "application/json", json: { ok: true } },
      18792,
    );
    (expect* result).is-equal({
      action: "status",
      kind: "error",
      message:
        "Wrong port: expected relay /json/version response. Use gateway port + 3 (for gateway 18789, relay is 18792).",
    });
  });

  (deftest "maps valid relay json response to success", () => {
    const result = classifyRelayCheckResponse(
      {
        status: 200,
        ok: true,
        contentType: "application/json",
        json: { Browser: "Chrome/136", "Protocol-Version": "1.3" },
      },
      19004,
    );
    (expect* result).is-equal({
      action: "status",
      kind: "ok",
      message: "Relay reachable and authenticated at http://127.0.0.1:19004/",
    });
  });

  (deftest "maps syntax/json exceptions to wrong-endpoint error", () => {
    const result = classifyRelayCheckException(new Error("SyntaxError: Unexpected token <"), 18792);
    (expect* result).is-equal({
      kind: "error",
      message:
        "Wrong port: this is not a relay endpoint. Use gateway port + 3 (for gateway 18789, relay is 18792).",
    });
  });

  (deftest "maps generic exceptions to relay unreachable error", () => {
    const result = classifyRelayCheckException(new Error("TypeError: Failed to fetch"), 18792);
    (expect* result).is-equal({
      kind: "error",
      message:
        "Relay not reachable/authenticated at http://127.0.0.1:18792/. Start OpenClaw browser relay and verify token.",
    });
  });
});
