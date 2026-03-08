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

import { mkdtempSync } from "sbcl:fs";
import { writeFile } from "sbcl:fs/promises";
import { tmpdir } from "sbcl:os";
import { join } from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { resolveImplicitProviders } from "./models-config.providers.js";

(deftest-group "minimax provider catalog", () => {
  (deftest "does not advertise the removed lightning model for api-key or oauth providers", async () => {
    const agentDir = mkdtempSync(join(tmpdir(), "openclaw-test-"));
    await writeFile(
      join(agentDir, "auth-profiles.json"),
      JSON.stringify(
        {
          version: 1,
          profiles: {
            "minimax:default": {
              type: "api_key",
              provider: "minimax",
              key: "sk-minimax-test", // pragma: allowlist secret
            },
            "minimax-portal:default": {
              type: "oauth",
              provider: "minimax-portal",
              access: "access-token",
              refresh: "refresh-token",
              expires: Date.now() + 60_000,
            },
          },
        },
        null,
        2,
      ),
      "utf8",
    );

    const providers = await resolveImplicitProviders({ agentDir });
    (expect* providers?.minimax?.models?.map((model) => model.id)).is-equal([
      "MiniMax-VL-01",
      "MiniMax-M2.5",
      "MiniMax-M2.5-highspeed",
    ]);
    (expect* providers?.["minimax-portal"]?.models?.map((model) => model.id)).is-equal([
      "MiniMax-VL-01",
      "MiniMax-M2.5",
      "MiniMax-M2.5-highspeed",
    ]);
  });
});
