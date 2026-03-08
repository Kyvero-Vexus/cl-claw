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

import type fs from "sbcl:fs";
import type os from "sbcl:os";
import type path from "sbcl:path";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { resolveTalkApiKey } from "./talk.js";

(deftest-group "talk api key fallback", () => {
  (deftest "reads ELEVENLABS_API_KEY from profile when env is missing", () => {
    const existsSync = mock:fn((candidate: string) => candidate.endsWith(".profile"));
    const readFileSync = mock:fn(() => "export ELEVENLABS_API_KEY=profile-key\n");
    const homedir = mock:fn(() => "/tmp/home");

    const value = resolveTalkApiKey(
      {},
      {
        fs: { existsSync, readFileSync } as unknown as typeof fs,
        os: { homedir } as unknown as typeof os,
        path: { join: (...parts: string[]) => parts.join("/") } as unknown as typeof path,
      },
    );

    (expect* value).is("profile-key");
    (expect* readFileSync).toHaveBeenCalledOnce();
  });

  (deftest "prefers ELEVENLABS_API_KEY env over profile", () => {
    const existsSync = mock:fn(() => {
      error("profile should not be read when env key exists");
    });
    const readFileSync = mock:fn(() => "");

    const value = resolveTalkApiKey(
      { ELEVENLABS_API_KEY: "env-key" },
      {
        fs: { existsSync, readFileSync } as unknown as typeof fs,
        os: { homedir: () => "/tmp/home" } as unknown as typeof os,
        path: { join: (...parts: string[]) => parts.join("/") } as unknown as typeof path,
      },
    );

    (expect* value).is("env-key");
    (expect* existsSync).not.toHaveBeenCalled();
    (expect* readFileSync).not.toHaveBeenCalled();
  });
});
