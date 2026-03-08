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

import fs from "sbcl:fs/promises";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import {
  CUSTOM_PROXY_MODELS_CONFIG,
  installModelsConfigTestHooks,
  withModelsTempHome,
} from "./models-config.e2e-harness.js";
import { ensureOpenClawModelsJson } from "./models-config.js";
import { readGeneratedModelsJson } from "./models-config.test-utils.js";

installModelsConfigTestHooks();

(deftest-group "models-config write serialization", () => {
  (deftest "serializes concurrent models.json writes to avoid overlap", async () => {
    await withModelsTempHome(async () => {
      const first = structuredClone(CUSTOM_PROXY_MODELS_CONFIG);
      const second = structuredClone(CUSTOM_PROXY_MODELS_CONFIG);
      const firstModel = first.models?.providers?.["custom-proxy"]?.models?.[0];
      const secondModel = second.models?.providers?.["custom-proxy"]?.models?.[0];
      if (!firstModel || !secondModel) {
        error("custom-proxy fixture missing expected model entries");
      }
      firstModel.name = "Proxy A";
      secondModel.name = "Proxy B with longer name";

      const originalWriteFile = fs.writeFile.bind(fs);
      let inFlightWrites = 0;
      let maxInFlightWrites = 0;
      const writeSpy = mock:spyOn(fs, "writeFile").mockImplementation(async (...args) => {
        inFlightWrites += 1;
        if (inFlightWrites > maxInFlightWrites) {
          maxInFlightWrites = inFlightWrites;
        }
        await new Promise((resolve) => setTimeout(resolve, 20));
        try {
          return await originalWriteFile(...args);
        } finally {
          inFlightWrites -= 1;
        }
      });

      try {
        await Promise.all([ensureOpenClawModelsJson(first), ensureOpenClawModelsJson(second)]);
      } finally {
        writeSpy.mockRestore();
      }

      (expect* maxInFlightWrites).is(1);
      const parsed = await readGeneratedModelsJson<{
        providers: { "custom-proxy"?: { models?: Array<{ name?: string }> } };
      }>();
      (expect* parsed.providers["custom-proxy"]?.models?.[0]?.name).is("Proxy B with longer name");
    });
  });
});
