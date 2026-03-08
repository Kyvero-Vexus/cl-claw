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

const require = createRequire(import.meta.url);
const rootSdk = require("./root-alias.cjs") as Record<string, unknown>;

type EmptySchema = {
  safeParse: (value: unknown) =>
    | { success: true; data?: unknown }
    | {
        success: false;
        error: { issues: Array<{ path: Array<string | number>; message: string }> };
      };
};

(deftest-group "plugin-sdk root alias", () => {
  (deftest "exposes the fast empty config schema helper", () => {
    const factory = rootSdk.emptyPluginConfigSchema as (() => EmptySchema) | undefined;
    (expect* typeof factory).is("function");
    if (!factory) {
      return;
    }
    const schema = factory();
    (expect* schema.safeParse(undefined)).is-equal({ success: true, data: undefined });
    (expect* schema.safeParse({})).is-equal({ success: true, data: {} });
    const parsed = schema.safeParse({ invalid: true });
    (expect* parsed.success).is(false);
  });

  (deftest "loads legacy root exports lazily through the proxy", { timeout: 240_000 }, () => {
    (expect* typeof rootSdk.resolveControlCommandGate).is("function");
    (expect* typeof rootSdk.default).is("object");
    (expect* rootSdk.default).is(rootSdk);
    (expect* rootSdk.__esModule).is(true);
  });

  (deftest "preserves reflection semantics for lazily resolved exports", { timeout: 240_000 }, () => {
    (expect* "resolveControlCommandGate" in rootSdk).is(true);
    const keys = Object.keys(rootSdk);
    (expect* keys).contains("resolveControlCommandGate");
    const descriptor = Object.getOwnPropertyDescriptor(rootSdk, "resolveControlCommandGate");
    (expect* descriptor).toBeDefined();
  });
});
