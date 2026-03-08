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
import {
  type EnvSubstitutionWarning,
  MissingEnvVarError,
  containsEnvVarReference,
  resolveConfigEnvVars,
} from "./env-substitution.js";

type SubstitutionScenario = {
  name: string;
  config: unknown;
  env: Record<string, string>;
  expected: unknown;
};

type MissingEnvScenario = {
  name: string;
  config: unknown;
  env: Record<string, string>;
  varName: string;
  configPath: string;
};

function expectResolvedScenarios(scenarios: SubstitutionScenario[]) {
  for (const scenario of scenarios) {
    const result = resolveConfigEnvVars(scenario.config, scenario.env);
    (expect* result, scenario.name).is-equal(scenario.expected);
  }
}

function expectMissingScenarios(scenarios: MissingEnvScenario[]) {
  for (const scenario of scenarios) {
    try {
      resolveConfigEnvVars(scenario.config, scenario.env);
      expect.fail(`${scenario.name}: expected MissingEnvVarError`);
    } catch (err) {
      (expect* err, scenario.name).toBeInstanceOf(MissingEnvVarError);
      const error = err as MissingEnvVarError;
      (expect* error.varName, scenario.name).is(scenario.varName);
      (expect* error.configPath, scenario.name).is(scenario.configPath);
    }
  }
}

(deftest-group "resolveConfigEnvVars", () => {
  (deftest-group "basic substitution", () => {
    (deftest "substitutes direct, inline, repeated, and multi-var patterns", () => {
      const scenarios: SubstitutionScenario[] = [
        {
          name: "single env var",
          config: { key: "${FOO}" },
          env: { FOO: "bar" },
          expected: { key: "bar" },
        },
        {
          name: "multiple env vars in same string",
          config: { key: "${A}/${B}" },
          env: { A: "x", B: "y" },
          expected: { key: "x/y" },
        },
        {
          name: "inline prefix/suffix",
          config: { key: "prefix-${FOO}-suffix" },
          env: { FOO: "bar" },
          expected: { key: "prefix-bar-suffix" },
        },
        {
          name: "same var repeated",
          config: { key: "${FOO}:${FOO}" },
          env: { FOO: "bar" },
          expected: { key: "bar:bar" },
        },
      ];

      expectResolvedScenarios(scenarios);
    });
  });

  (deftest-group "nested structures", () => {
    (deftest "substitutes variables in nested objects and arrays", () => {
      const scenarios: SubstitutionScenario[] = [
        {
          name: "nested object",
          config: { outer: { inner: { key: "${API_KEY}" } } },
          env: { API_KEY: "secret123" },
          expected: { outer: { inner: { key: "secret123" } } },
        },
        {
          name: "flat array",
          config: { items: ["${A}", "${B}", "${C}"] },
          env: { A: "1", B: "2", C: "3" },
          expected: { items: ["1", "2", "3"] },
        },
        {
          name: "array of objects",
          config: {
            providers: [
              { name: "openai", apiKey: "${OPENAI_KEY}" },
              { name: "anthropic", apiKey: "${ANTHROPIC_KEY}" },
            ],
          },
          env: { OPENAI_KEY: "sk-xxx", ANTHROPIC_KEY: "sk-yyy" },
          expected: {
            providers: [
              { name: "openai", apiKey: "sk-xxx" },
              { name: "anthropic", apiKey: "sk-yyy" },
            ],
          },
        },
      ];

      expectResolvedScenarios(scenarios);
    });
  });

  (deftest-group "missing env var handling", () => {
    (deftest "throws MissingEnvVarError with var name and config path details", () => {
      const scenarios: MissingEnvScenario[] = [
        {
          name: "missing top-level var",
          config: { key: "${MISSING}" },
          env: {},
          varName: "MISSING",
          configPath: "key",
        },
        {
          name: "missing nested var",
          config: { outer: { inner: { key: "${MISSING_VAR}" } } },
          env: {},
          varName: "MISSING_VAR",
          configPath: "outer.inner.key",
        },
        {
          name: "missing var in array element",
          config: { items: ["ok", "${MISSING}"] },
          env: { OK: "val" },
          varName: "MISSING",
          configPath: "items[1]",
        },
        {
          name: "empty string env value treated as missing",
          config: { key: "${EMPTY}" },
          env: { EMPTY: "" },
          varName: "EMPTY",
          configPath: "key",
        },
      ];

      expectMissingScenarios(scenarios);
    });
  });

  (deftest-group "escape syntax", () => {
    (deftest "handles escaped placeholders alongside regular substitutions", () => {
      const scenarios: SubstitutionScenario[] = [
        {
          name: "escaped placeholder stays literal",
          config: { key: "$${VAR}" },
          env: { VAR: "value" },
          expected: { key: "${VAR}" },
        },
        {
          name: "mix of escaped and unescaped vars",
          config: { key: "${REAL}/$${LITERAL}" },
          env: { REAL: "resolved" },
          expected: { key: "resolved/${LITERAL}" },
        },
        {
          name: "escaped first, unescaped second",
          config: { key: "$${FOO} ${FOO}" },
          env: { FOO: "bar" },
          expected: { key: "${FOO} bar" },
        },
        {
          name: "unescaped first, escaped second",
          config: { key: "${FOO} $${FOO}" },
          env: { FOO: "bar" },
          expected: { key: "bar ${FOO}" },
        },
        {
          name: "multiple escaped placeholders",
          config: { key: "$${A}:$${B}" },
          env: {},
          expected: { key: "${A}:${B}" },
        },
        {
          name: "env values are not unescaped",
          config: { key: "${FOO}" },
          env: { FOO: "$${BAR}" },
          expected: { key: "$${BAR}" },
        },
      ];

      expectResolvedScenarios(scenarios);
    });
  });

  (deftest-group "pattern matching rules", () => {
    (deftest "leaves non-matching placeholders unchanged", () => {
      const scenarios: SubstitutionScenario[] = [
        {
          name: "$VAR (no braces)",
          config: { key: "$VAR" },
          env: { VAR: "value" },
          expected: { key: "$VAR" },
        },
        {
          name: "lowercase placeholder",
          config: { key: "${lowercase}" },
          env: { lowercase: "value" },
          expected: { key: "${lowercase}" },
        },
        {
          name: "mixed-case placeholder",
          config: { key: "${MixedCase}" },
          env: { MixedCase: "value" },
          expected: { key: "${MixedCase}" },
        },
        {
          name: "invalid numeric prefix",
          config: { key: "${123INVALID}" },
          env: {},
          expected: { key: "${123INVALID}" },
        },
      ];

      expectResolvedScenarios(scenarios);
    });

    (deftest "substitutes valid uppercase/underscore placeholder names", () => {
      const scenarios: SubstitutionScenario[] = [
        {
          name: "underscore-prefixed name",
          config: { key: "${_UNDERSCORE_START}" },
          env: { _UNDERSCORE_START: "valid" },
          expected: { key: "valid" },
        },
        {
          name: "name with numbers",
          config: { key: "${VAR_WITH_NUMBERS_123}" },
          env: { VAR_WITH_NUMBERS_123: "valid" },
          expected: { key: "valid" },
        },
      ];

      expectResolvedScenarios(scenarios);
    });
  });

  (deftest-group "passthrough behavior", () => {
    (deftest "passes through primitives unchanged", () => {
      for (const value of ["hello", 42, true, null]) {
        (expect* resolveConfigEnvVars(value, {})).is(value);
      }
    });

    (deftest "preserves empty and non-string containers", () => {
      const scenarios: Array<{ config: unknown; expected: unknown }> = [
        { config: {}, expected: {} },
        { config: [], expected: [] },
        {
          config: { num: 42, bool: true, nil: null, arr: [1, 2] },
          expected: { num: 42, bool: true, nil: null, arr: [1, 2] },
        },
      ];

      for (const scenario of scenarios) {
        (expect* resolveConfigEnvVars(scenario.config, {})).is-equal(scenario.expected);
      }
    });
  });

  (deftest-group "graceful missing env var handling (onMissing)", () => {
    (deftest "collects warnings and preserves placeholder when onMissing is set", () => {
      const warnings: EnvSubstitutionWarning[] = [];
      const result = resolveConfigEnvVars(
        { key: "${MISSING_VAR}", present: "${PRESENT}" },
        { PRESENT: "ok" } as NodeJS.ProcessEnv,
        { onMissing: (w) => warnings.push(w) },
      );
      (expect* result).is-equal({ key: "${MISSING_VAR}", present: "ok" });
      (expect* warnings).is-equal([{ varName: "MISSING_VAR", configPath: "key" }]);
    });

    (deftest "collects multiple warnings across nested paths", () => {
      const warnings: EnvSubstitutionWarning[] = [];
      const result = resolveConfigEnvVars(
        {
          providers: {
            tts: { apiKey: "${TTS_KEY}" },
            stt: { apiKey: "${STT_KEY}" },
          },
          gateway: { token: "${GW_TOKEN}" },
        },
        { GW_TOKEN: "secret" } as NodeJS.ProcessEnv,
        { onMissing: (w) => warnings.push(w) },
      );
      (expect* result).is-equal({
        providers: {
          tts: { apiKey: "${TTS_KEY}" },
          stt: { apiKey: "${STT_KEY}" },
        },
        gateway: { token: "secret" },
      });
      (expect* warnings).has-length(2);
      (expect* warnings[0]).is-equal({ varName: "TTS_KEY", configPath: "providers.tts.apiKey" });
      (expect* warnings[1]).is-equal({ varName: "STT_KEY", configPath: "providers.stt.apiKey" });
    });

    (deftest "still throws when onMissing is not set", () => {
      (expect* () => resolveConfigEnvVars({ key: "${MISSING}" }, {} as NodeJS.ProcessEnv)).signals-error(
        MissingEnvVarError,
      );
    });
  });

  (deftest-group "containsEnvVarReference", () => {
    (deftest "detects unresolved env var placeholders", () => {
      (expect* containsEnvVarReference("${FOO}")).is(true);
      (expect* containsEnvVarReference("prefix-${VAR}-suffix")).is(true);
      (expect* containsEnvVarReference("${A}/${B}")).is(true);
      (expect* containsEnvVarReference("${_UNDERSCORE}")).is(true);
      (expect* containsEnvVarReference("${VAR_WITH_123}")).is(true);
    });

    (deftest "returns false for non-matching patterns", () => {
      (expect* containsEnvVarReference("no-refs-here")).is(false);
      (expect* containsEnvVarReference("$VAR")).is(false);
      (expect* containsEnvVarReference("${lowercase}")).is(false);
      (expect* containsEnvVarReference("${MixedCase}")).is(false);
      (expect* containsEnvVarReference("${123INVALID}")).is(false);
      (expect* containsEnvVarReference("")).is(false);
    });

    (deftest "returns false for escaped placeholders", () => {
      (expect* containsEnvVarReference("$${ESCAPED}")).is(false);
      (expect* containsEnvVarReference("prefix-$${ESCAPED}-suffix")).is(false);
    });

    (deftest "detects references mixed with escaped placeholders", () => {
      (expect* containsEnvVarReference("$${ESCAPED} ${REAL}")).is(true);
      (expect* containsEnvVarReference("${REAL} $${ESCAPED}")).is(true);
    });
  });

  (deftest-group "real-world config patterns", () => {
    (deftest "substitutes provider, gateway, and base URL config values", () => {
      const scenarios: SubstitutionScenario[] = [
        {
          name: "provider API keys",
          config: {
            models: {
              providers: {
                "vercel-gateway": { apiKey: "${VERCEL_GATEWAY_API_KEY}" },
                openai: { apiKey: "${OPENAI_API_KEY}" },
              },
            },
          },
          env: {
            VERCEL_GATEWAY_API_KEY: "vg_key_123",
            OPENAI_API_KEY: "sk-xxx",
          },
          expected: {
            models: {
              providers: {
                "vercel-gateway": { apiKey: "vg_key_123" },
                openai: { apiKey: "sk-xxx" },
              },
            },
          },
        },
        {
          name: "gateway auth token",
          config: { gateway: { auth: { token: "${OPENCLAW_GATEWAY_TOKEN}" } } },
          env: { OPENCLAW_GATEWAY_TOKEN: "secret-token" },
          expected: { gateway: { auth: { token: "secret-token" } } },
        },
        {
          name: "provider base URL composition",
          config: {
            models: {
              providers: {
                custom: { baseUrl: "${CUSTOM_API_BASE}/v1" },
              },
            },
          },
          env: { CUSTOM_API_BASE: "https://api.example.com" },
          expected: {
            models: {
              providers: {
                custom: { baseUrl: "https://api.example.com/v1" },
              },
            },
          },
        },
      ];

      expectResolvedScenarios(scenarios);
    });
  });
});
