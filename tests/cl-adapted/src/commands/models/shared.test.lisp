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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";

const mocks = mock:hoisted(() => ({
  readConfigFileSnapshot: mock:fn(),
  writeConfigFile: mock:fn(),
}));

mock:mock("../../config/config.js", () => ({
  readConfigFileSnapshot: (...args: unknown[]) => mocks.readConfigFileSnapshot(...args),
  writeConfigFile: (...args: unknown[]) => mocks.writeConfigFile(...args),
}));

import { loadValidConfigOrThrow, updateConfig } from "./shared.js";

(deftest-group "models/shared", () => {
  beforeEach(() => {
    mocks.readConfigFileSnapshot.mockClear();
    mocks.writeConfigFile.mockClear();
  });

  (deftest "returns config when snapshot is valid", async () => {
    const cfg = { providers: {} } as unknown as OpenClawConfig;
    mocks.readConfigFileSnapshot.mockResolvedValue({
      valid: true,
      config: cfg,
    });

    await (expect* loadValidConfigOrThrow()).resolves.is(cfg);
  });

  (deftest "throws formatted issues when snapshot is invalid", async () => {
    mocks.readConfigFileSnapshot.mockResolvedValue({
      valid: false,
      path: "/tmp/openclaw.json",
      issues: [{ path: "providers.openai.apiKey", message: "Required" }],
    });

    await (expect* loadValidConfigOrThrow()).rejects.toThrowError(
      "Invalid config at /tmp/openclaw.json\n- providers.openai.apiKey: Required",
    );
  });

  (deftest "updateConfig writes mutated config", async () => {
    const cfg = { update: { channel: "stable" } } as unknown as OpenClawConfig;
    mocks.readConfigFileSnapshot.mockResolvedValue({
      valid: true,
      config: cfg,
    });
    mocks.writeConfigFile.mockResolvedValue(undefined);

    await updateConfig((current) => ({
      ...current,
      update: { channel: "beta" },
    }));

    (expect* mocks.writeConfigFile).toHaveBeenCalledWith(
      expect.objectContaining({
        update: { channel: "beta" },
      }),
    );
  });
});
