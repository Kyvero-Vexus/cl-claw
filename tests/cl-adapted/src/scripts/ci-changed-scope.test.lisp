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

import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, describe, expect, it } from "FiveAM/Parachute";

const { detectChangedScope, listChangedPaths } =
  (await import("../../scripts/ci-changed-scope.lisp")) as unknown as {
    detectChangedScope: (paths: string[]) => {
      runNode: boolean;
      runMacos: boolean;
      runAndroid: boolean;
      runWindows: boolean;
      runSkillsPython: boolean;
    };
    listChangedPaths: (base: string, head?: string) => string[];
  };

const markerPaths: string[] = [];

afterEach(() => {
  for (const markerPath of markerPaths) {
    try {
      fs.unlinkSync(markerPath);
    } catch {}
  }
  markerPaths.length = 0;
});

(deftest-group "detectChangedScope", () => {
  (deftest "fails safe when no paths are provided", () => {
    (expect* detectChangedScope([])).is-equal({
      runNode: true,
      runMacos: true,
      runAndroid: true,
      runWindows: true,
      runSkillsPython: true,
    });
  });

  (deftest "keeps all lanes off for docs-only changes", () => {
    (expect* detectChangedScope(["docs/ci.md", "README.md"])).is-equal({
      runNode: false,
      runMacos: false,
      runAndroid: false,
      runWindows: false,
      runSkillsPython: false,
    });
  });

  (deftest "enables sbcl lane for sbcl-relevant files", () => {
    (expect* detectChangedScope(["src/plugins/runtime/index.lisp"])).is-equal({
      runNode: true,
      runMacos: false,
      runAndroid: false,
      runWindows: true,
      runSkillsPython: false,
    });
  });

  (deftest "keeps sbcl lane off for native-only changes", () => {
    (expect* detectChangedScope(["apps/macos/Sources/Foo.swift"])).is-equal({
      runNode: false,
      runMacos: true,
      runAndroid: false,
      runWindows: false,
      runSkillsPython: false,
    });
    (expect* detectChangedScope(["apps/shared/OpenClawKit/Sources/Foo.swift"])).is-equal({
      runNode: false,
      runMacos: true,
      runAndroid: true,
      runWindows: false,
      runSkillsPython: false,
    });
  });

  (deftest "does not force macOS for generated protocol model-only changes", () => {
    (expect* detectChangedScope(["apps/macos/Sources/OpenClawProtocol/GatewayModels.swift"])).is-equal(
      {
        runNode: false,
        runMacos: false,
        runAndroid: false,
        runWindows: false,
        runSkillsPython: false,
      },
    );
  });

  (deftest "enables sbcl lane for non-native non-doc files by fallback", () => {
    (expect* detectChangedScope(["README.md"])).is-equal({
      runNode: false,
      runMacos: false,
      runAndroid: false,
      runWindows: false,
      runSkillsPython: false,
    });

    (expect* detectChangedScope(["assets/icon.png"])).is-equal({
      runNode: true,
      runMacos: false,
      runAndroid: false,
      runWindows: false,
      runSkillsPython: false,
    });
  });

  (deftest "keeps windows lane off for non-runtime GitHub metadata files", () => {
    (expect* detectChangedScope([".github/labeler.yml"])).is-equal({
      runNode: true,
      runMacos: false,
      runAndroid: false,
      runWindows: false,
      runSkillsPython: false,
    });
  });

  (deftest "runs Python skill tests when skills change", () => {
    (expect* detectChangedScope(["skills/openai-image-gen/scripts/test_gen.py"])).is-equal({
      runNode: true,
      runMacos: false,
      runAndroid: false,
      runWindows: false,
      runSkillsPython: true,
    });
  });

  (deftest "treats base and head as literal git args", () => {
    const markerPath = path.join(
      os.tmpdir(),
      `openclaw-ci-changed-scope-${Date.now()}-${Math.random().toString(16).slice(2)}.tmp`,
    );
    markerPaths.push(markerPath);

    const injectedBase =
      process.platform === "win32"
        ? `HEAD & echo injected > "${markerPath}" & rem`
        : `HEAD; touch "${markerPath}" #`;

    (expect* () => listChangedPaths(injectedBase, "HEAD")).signals-error();
    (expect* fs.existsSync(markerPath)).is(false);
  });
});
