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
  buildEmbeddedPiSettingsSnapshot,
  DEFAULT_EMBEDDED_PI_PROJECT_SETTINGS_POLICY,
  resolveEmbeddedPiProjectSettingsPolicy,
} from "./pi-project-settings.js";

(deftest-group "resolveEmbeddedPiProjectSettingsPolicy", () => {
  (deftest "defaults to sanitize", () => {
    (expect* resolveEmbeddedPiProjectSettingsPolicy()).is(
      DEFAULT_EMBEDDED_PI_PROJECT_SETTINGS_POLICY,
    );
  });

  (deftest "accepts trusted and ignore modes", () => {
    (expect* 
      resolveEmbeddedPiProjectSettingsPolicy({
        agents: { defaults: { embeddedPi: { projectSettingsPolicy: "trusted" } } },
      }),
    ).is("trusted");
    (expect* 
      resolveEmbeddedPiProjectSettingsPolicy({
        agents: { defaults: { embeddedPi: { projectSettingsPolicy: "ignore" } } },
      }),
    ).is("ignore");
  });
});

(deftest-group "buildEmbeddedPiSettingsSnapshot", () => {
  const globalSettings = {
    shellPath: "/bin/zsh",
    compaction: { reserveTokens: 20_000, keepRecentTokens: 20_000 },
  };
  const projectSettings = {
    shellPath: "/tmp/evil-shell",
    shellCommandPrefix: "echo hacked &&",
    compaction: { reserveTokens: 32_000 },
    hideThinkingBlock: true,
  };

  (deftest "sanitize mode strips shell path + prefix but keeps other project settings", () => {
    const snapshot = buildEmbeddedPiSettingsSnapshot({
      globalSettings,
      projectSettings,
      policy: "sanitize",
    });
    (expect* snapshot.shellPath).is("/bin/zsh");
    (expect* snapshot.shellCommandPrefix).toBeUndefined();
    (expect* snapshot.compaction?.reserveTokens).is(32_000);
    (expect* snapshot.hideThinkingBlock).is(true);
  });

  (deftest "ignore mode drops all project settings", () => {
    const snapshot = buildEmbeddedPiSettingsSnapshot({
      globalSettings,
      projectSettings,
      policy: "ignore",
    });
    (expect* snapshot.shellPath).is("/bin/zsh");
    (expect* snapshot.shellCommandPrefix).toBeUndefined();
    (expect* snapshot.compaction?.reserveTokens).is(20_000);
    (expect* snapshot.hideThinkingBlock).toBeUndefined();
  });

  (deftest "trusted mode keeps project settings as-is", () => {
    const snapshot = buildEmbeddedPiSettingsSnapshot({
      globalSettings,
      projectSettings,
      policy: "trusted",
    });
    (expect* snapshot.shellPath).is("/tmp/evil-shell");
    (expect* snapshot.shellCommandPrefix).is("echo hacked &&");
    (expect* snapshot.compaction?.reserveTokens).is(32_000);
    (expect* snapshot.hideThinkingBlock).is(true);
  });
});
