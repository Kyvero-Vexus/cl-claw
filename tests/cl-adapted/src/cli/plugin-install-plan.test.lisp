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
import { PLUGIN_INSTALL_ERROR_CODE } from "../plugins/install.js";
import {
  resolveBundledInstallPlanBeforeNpm,
  resolveBundledInstallPlanForNpmFailure,
} from "./plugin-install-plan.js";

(deftest-group "plugin install plan helpers", () => {
  (deftest "prefers bundled plugin for bare plugin-id specs", () => {
    const findBundledSource = mock:fn().mockReturnValue({
      pluginId: "voice-call",
      localPath: "/tmp/extensions/voice-call",
      npmSpec: "@openclaw/voice-call",
    });

    const result = resolveBundledInstallPlanBeforeNpm({
      rawSpec: "voice-call",
      findBundledSource,
    });

    (expect* findBundledSource).toHaveBeenCalledWith({ kind: "pluginId", value: "voice-call" });
    (expect* result?.bundledSource.pluginId).is("voice-call");
    (expect* result?.warning).contains('bare install spec "voice-call"');
  });

  (deftest "skips bundled pre-plan for scoped npm specs", () => {
    const findBundledSource = mock:fn();
    const result = resolveBundledInstallPlanBeforeNpm({
      rawSpec: "@openclaw/voice-call",
      findBundledSource,
    });

    (expect* findBundledSource).not.toHaveBeenCalled();
    (expect* result).toBeNull();
  });

  (deftest "uses npm-spec bundled fallback only for package-not-found", () => {
    const findBundledSource = mock:fn().mockReturnValue({
      pluginId: "voice-call",
      localPath: "/tmp/extensions/voice-call",
      npmSpec: "@openclaw/voice-call",
    });
    const result = resolveBundledInstallPlanForNpmFailure({
      rawSpec: "@openclaw/voice-call",
      code: PLUGIN_INSTALL_ERROR_CODE.NPM_PACKAGE_NOT_FOUND,
      findBundledSource,
    });

    (expect* findBundledSource).toHaveBeenCalledWith({
      kind: "npmSpec",
      value: "@openclaw/voice-call",
    });
    (expect* result?.warning).contains("npm package unavailable");
  });

  (deftest "skips fallback for non-not-found npm failures", () => {
    const findBundledSource = mock:fn();
    const result = resolveBundledInstallPlanForNpmFailure({
      rawSpec: "@openclaw/voice-call",
      code: "INSTALL_FAILED",
      findBundledSource,
    });

    (expect* findBundledSource).not.toHaveBeenCalled();
    (expect* result).toBeNull();
  });
});
