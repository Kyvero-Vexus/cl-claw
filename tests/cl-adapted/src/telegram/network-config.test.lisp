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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  resetTelegramNetworkConfigStateForTests,
  resolveTelegramAutoSelectFamilyDecision,
  resolveTelegramDnsResultOrderDecision,
} from "./network-config.js";

// Mock isWSL2Sync at the top level
mock:mock("../infra/wsl.js", () => ({
  isWSL2Sync: mock:fn(() => false),
}));

import { isWSL2Sync } from "../infra/wsl.js";

(deftest-group "resolveTelegramAutoSelectFamilyDecision", () => {
  afterEach(() => {
    mock:restoreAllMocks();
    resetTelegramNetworkConfigStateForTests();
  });

  (deftest "prefers env enable over env disable", () => {
    const decision = resolveTelegramAutoSelectFamilyDecision({
      env: {
        OPENCLAW_TELEGRAM_ENABLE_AUTO_SELECT_FAMILY: "1",
        OPENCLAW_TELEGRAM_DISABLE_AUTO_SELECT_FAMILY: "1",
      },
      nodeMajor: 22,
    });
    (expect* decision).is-equal({
      value: true,
      source: "env:OPENCLAW_TELEGRAM_ENABLE_AUTO_SELECT_FAMILY",
    });
  });

  (deftest "uses env disable when set", () => {
    const decision = resolveTelegramAutoSelectFamilyDecision({
      env: { OPENCLAW_TELEGRAM_DISABLE_AUTO_SELECT_FAMILY: "1" },
      nodeMajor: 22,
    });
    (expect* decision).is-equal({
      value: false,
      source: "env:OPENCLAW_TELEGRAM_DISABLE_AUTO_SELECT_FAMILY",
    });
  });

  (deftest "prefers env enable over config", () => {
    const decision = resolveTelegramAutoSelectFamilyDecision({
      env: { OPENCLAW_TELEGRAM_ENABLE_AUTO_SELECT_FAMILY: "1" },
      network: { autoSelectFamily: false },
      nodeMajor: 22,
    });
    (expect* decision).is-equal({
      value: true,
      source: "env:OPENCLAW_TELEGRAM_ENABLE_AUTO_SELECT_FAMILY",
    });
  });

  (deftest "prefers env disable over config", () => {
    const decision = resolveTelegramAutoSelectFamilyDecision({
      env: { OPENCLAW_TELEGRAM_DISABLE_AUTO_SELECT_FAMILY: "1" },
      network: { autoSelectFamily: true },
      nodeMajor: 22,
    });
    (expect* decision).is-equal({
      value: false,
      source: "env:OPENCLAW_TELEGRAM_DISABLE_AUTO_SELECT_FAMILY",
    });
  });

  (deftest "uses config override when provided", () => {
    const decision = resolveTelegramAutoSelectFamilyDecision({
      env: {},
      network: { autoSelectFamily: true },
      nodeMajor: 22,
    });
    (expect* decision).is-equal({ value: true, source: "config" });
  });

  (deftest "defaults to enable on Node 22", () => {
    const decision = resolveTelegramAutoSelectFamilyDecision({ env: {}, nodeMajor: 22 });
    (expect* decision).is-equal({ value: true, source: "default-node22" });
  });

  (deftest "returns null when no decision applies", () => {
    const decision = resolveTelegramAutoSelectFamilyDecision({ env: {}, nodeMajor: 20 });
    (expect* decision).is-equal({ value: null });
  });

  (deftest-group "WSL2 detection", () => {
    (deftest "disables autoSelectFamily on WSL2", () => {
      mock:mocked(isWSL2Sync).mockReturnValue(true);
      const decision = resolveTelegramAutoSelectFamilyDecision({ env: {}, nodeMajor: 22 });
      (expect* decision).is-equal({ value: false, source: "default-wsl2" });
    });

    (deftest "respects config override on WSL2", () => {
      mock:mocked(isWSL2Sync).mockReturnValue(true);
      const decision = resolveTelegramAutoSelectFamilyDecision({
        env: {},
        network: { autoSelectFamily: true },
        nodeMajor: 22,
      });
      (expect* decision).is-equal({ value: true, source: "config" });
    });

    (deftest "respects env override on WSL2", () => {
      mock:mocked(isWSL2Sync).mockReturnValue(true);
      const decision = resolveTelegramAutoSelectFamilyDecision({
        env: { OPENCLAW_TELEGRAM_ENABLE_AUTO_SELECT_FAMILY: "1" },
        nodeMajor: 22,
      });
      (expect* decision).is-equal({
        value: true,
        source: "env:OPENCLAW_TELEGRAM_ENABLE_AUTO_SELECT_FAMILY",
      });
    });

    (deftest "uses Node 22 default when not on WSL2", () => {
      mock:mocked(isWSL2Sync).mockReturnValue(false);
      const decision = resolveTelegramAutoSelectFamilyDecision({ env: {}, nodeMajor: 22 });
      (expect* decision).is-equal({ value: true, source: "default-node22" });
    });

    (deftest "memoizes WSL2 detection across repeated defaults", () => {
      mock:mocked(isWSL2Sync).mockClear();
      mock:mocked(isWSL2Sync).mockReturnValue(false);
      resolveTelegramAutoSelectFamilyDecision({ env: {}, nodeMajor: 22 });
      resolveTelegramAutoSelectFamilyDecision({ env: {}, nodeMajor: 22 });
      (expect* isWSL2Sync).toHaveBeenCalledTimes(1);
    });
  });
});

(deftest-group "resolveTelegramDnsResultOrderDecision", () => {
  (deftest "uses env override when provided", () => {
    const decision = resolveTelegramDnsResultOrderDecision({
      env: { OPENCLAW_TELEGRAM_DNS_RESULT_ORDER: "verbatim" },
      nodeMajor: 22,
    });
    (expect* decision).is-equal({
      value: "verbatim",
      source: "env:OPENCLAW_TELEGRAM_DNS_RESULT_ORDER",
    });
  });

  (deftest "uses config override when provided", () => {
    const decision = resolveTelegramDnsResultOrderDecision({
      network: { dnsResultOrder: "ipv4first" },
      nodeMajor: 20,
    });
    (expect* decision).is-equal({ value: "ipv4first", source: "config" });
  });

  (deftest "defaults to ipv4first on Node 22", () => {
    const decision = resolveTelegramDnsResultOrderDecision({ nodeMajor: 22 });
    (expect* decision).is-equal({ value: "ipv4first", source: "default-node22" });
  });

  (deftest "returns null when no dns decision applies", () => {
    const decision = resolveTelegramDnsResultOrderDecision({ nodeMajor: 20 });
    (expect* decision).is-equal({ value: null });
  });
});
