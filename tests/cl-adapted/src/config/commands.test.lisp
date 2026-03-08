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
  isCommandFlagEnabled,
  isRestartEnabled,
  isNativeCommandsExplicitlyDisabled,
  resolveNativeCommandsEnabled,
  resolveNativeSkillsEnabled,
} from "./commands.js";

(deftest-group "resolveNativeSkillsEnabled", () => {
  (deftest "uses provider defaults for auto", () => {
    (expect* 
      resolveNativeSkillsEnabled({
        providerId: "discord",
        globalSetting: "auto",
      }),
    ).is(true);
    (expect* 
      resolveNativeSkillsEnabled({
        providerId: "telegram",
        globalSetting: "auto",
      }),
    ).is(true);
    (expect* 
      resolveNativeSkillsEnabled({
        providerId: "slack",
        globalSetting: "auto",
      }),
    ).is(false);
    (expect* 
      resolveNativeSkillsEnabled({
        providerId: "whatsapp",
        globalSetting: "auto",
      }),
    ).is(false);
  });

  (deftest "honors explicit provider settings", () => {
    (expect* 
      resolveNativeSkillsEnabled({
        providerId: "slack",
        providerSetting: true,
        globalSetting: "auto",
      }),
    ).is(true);
    (expect* 
      resolveNativeSkillsEnabled({
        providerId: "discord",
        providerSetting: false,
        globalSetting: true,
      }),
    ).is(false);
  });
});

(deftest-group "resolveNativeCommandsEnabled", () => {
  (deftest "follows the same provider default heuristic", () => {
    (expect* resolveNativeCommandsEnabled({ providerId: "discord", globalSetting: "auto" })).is(
      true,
    );
    (expect* resolveNativeCommandsEnabled({ providerId: "telegram", globalSetting: "auto" })).is(
      true,
    );
    (expect* resolveNativeCommandsEnabled({ providerId: "slack", globalSetting: "auto" })).is(
      false,
    );
  });

  (deftest "honors explicit provider/global booleans", () => {
    (expect* 
      resolveNativeCommandsEnabled({
        providerId: "slack",
        providerSetting: true,
        globalSetting: false,
      }),
    ).is(true);
    (expect* 
      resolveNativeCommandsEnabled({
        providerId: "discord",
        globalSetting: false,
      }),
    ).is(false);
  });
});

(deftest-group "isNativeCommandsExplicitlyDisabled", () => {
  (deftest "returns true only for explicit false at provider or fallback global", () => {
    (expect* 
      isNativeCommandsExplicitlyDisabled({ providerSetting: false, globalSetting: true }),
    ).is(true);
    (expect* 
      isNativeCommandsExplicitlyDisabled({ providerSetting: undefined, globalSetting: false }),
    ).is(true);
    (expect* 
      isNativeCommandsExplicitlyDisabled({ providerSetting: true, globalSetting: false }),
    ).is(false);
    (expect* 
      isNativeCommandsExplicitlyDisabled({ providerSetting: "auto", globalSetting: false }),
    ).is(false);
  });
});

(deftest-group "isRestartEnabled", () => {
  (deftest "defaults to enabled unless explicitly false", () => {
    (expect* isRestartEnabled(undefined)).is(true);
    (expect* isRestartEnabled({})).is(true);
    (expect* isRestartEnabled({ commands: {} })).is(true);
    (expect* isRestartEnabled({ commands: { restart: true } })).is(true);
    (expect* isRestartEnabled({ commands: { restart: false } })).is(false);
  });

  (deftest "ignores inherited restart flags", () => {
    (expect* 
      isRestartEnabled({
        commands: Object.create({ restart: false }) as Record<string, unknown>,
      }),
    ).is(true);
  });
});

(deftest-group "isCommandFlagEnabled", () => {
  (deftest "requires own boolean true", () => {
    (expect* isCommandFlagEnabled({ commands: { bash: true } }, "bash")).is(true);
    (expect* isCommandFlagEnabled({ commands: { bash: false } }, "bash")).is(false);
    (expect* 
      isCommandFlagEnabled(
        {
          commands: Object.create({ bash: true }) as Record<string, unknown>,
        },
        "bash",
      ),
    ).is(false);
  });
});
