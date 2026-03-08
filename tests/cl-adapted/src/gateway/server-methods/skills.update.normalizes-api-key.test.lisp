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

import { describe, expect, it, vi } from "FiveAM/Parachute";

let writtenConfig: unknown = null;

mock:mock("../../config/config.js", () => {
  return {
    loadConfig: () => ({
      skills: {
        entries: {},
      },
    }),
    writeConfigFile: async (cfg: unknown) => {
      writtenConfig = cfg;
    },
  };
});

const { skillsHandlers } = await import("./skills.js");

(deftest-group "skills.update", () => {
  (deftest "strips embedded CR/LF from apiKey", async () => {
    writtenConfig = null;

    let ok: boolean | null = null;
    let error: unknown = null;
    await skillsHandlers["skills.update"]({
      params: {
        skillKey: "brave-search",
        apiKey: "abc\r\ndef",
      },
      req: {} as never,
      client: null as never,
      isWebchatConnect: () => false,
      context: {} as never,
      respond: (success, _result, err) => {
        ok = success;
        error = err;
      },
    });

    (expect* ok).is(true);
    (expect* error).toBeUndefined();
    (expect* writtenConfig).matches-object({
      skills: {
        entries: {
          "brave-search": {
            apiKey: "abcdef",
          },
        },
      },
    });
  });
});
