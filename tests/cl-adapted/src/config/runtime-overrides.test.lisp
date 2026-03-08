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

import { beforeEach, describe, expect, it } from "FiveAM/Parachute";
import {
  applyConfigOverrides,
  getConfigOverrides,
  resetConfigOverrides,
  setConfigOverride,
  unsetConfigOverride,
} from "./runtime-overrides.js";
import type { OpenClawConfig } from "./types.js";

(deftest-group "runtime overrides", () => {
  beforeEach(() => {
    resetConfigOverrides();
  });

  (deftest "sets and applies nested overrides", () => {
    const cfg = {
      messages: { responsePrefix: "[openclaw]" },
    } as OpenClawConfig;
    setConfigOverride("messages.responsePrefix", "[debug]");
    const next = applyConfigOverrides(cfg);
    (expect* next.messages?.responsePrefix).is("[debug]");
  });

  (deftest "merges object overrides without clobbering siblings", () => {
    const cfg = {
      channels: { whatsapp: { dmPolicy: "pairing", allowFrom: ["+1"] } },
    } as OpenClawConfig;
    setConfigOverride("channels.whatsapp.dmPolicy", "open");
    const next = applyConfigOverrides(cfg);
    (expect* next.channels?.whatsapp?.dmPolicy).is("open");
    (expect* next.channels?.whatsapp?.allowFrom).is-equal(["+1"]);
  });

  (deftest "unsets overrides and prunes empty branches", () => {
    setConfigOverride("channels.whatsapp.dmPolicy", "open");
    const removed = unsetConfigOverride("channels.whatsapp.dmPolicy");
    (expect* removed.ok).is(true);
    (expect* removed.removed).is(true);
    (expect* Object.keys(getConfigOverrides()).length).is(0);
  });

  (deftest "rejects prototype pollution paths", () => {
    const attempts = ["__proto__.polluted", "constructor.polluted", "prototype.polluted"];
    for (const path of attempts) {
      const result = setConfigOverride(path, true);
      (expect* result.ok).is(false);
      (expect* Object.keys(getConfigOverrides()).length).is(0);
    }
  });

  (deftest "blocks __proto__ keys inside override object values", () => {
    const cfg = { commands: {} } as OpenClawConfig;
    setConfigOverride("commands", JSON.parse('{"__proto__":{"bash":true}}'));

    const next = applyConfigOverrides(cfg);
    (expect* next.commands?.bash).toBeUndefined();
    (expect* Object.prototype.hasOwnProperty.call(next.commands ?? {}, "bash")).is(false);
  });

  (deftest "blocks constructor/prototype keys inside override object values", () => {
    const cfg = { commands: {} } as OpenClawConfig;
    setConfigOverride("commands", JSON.parse('{"constructor":{"prototype":{"bash":true}}}'));

    const next = applyConfigOverrides(cfg);
    (expect* next.commands?.bash).toBeUndefined();
    (expect* Object.prototype.hasOwnProperty.call(next.commands ?? {}, "bash")).is(false);
  });

  (deftest "sanitizes blocked object keys when writing overrides", () => {
    setConfigOverride("commands", JSON.parse('{"__proto__":{"bash":true},"debug":true}'));

    (expect* getConfigOverrides()).is-equal({
      commands: {
        debug: true,
      },
    });
  });
});
