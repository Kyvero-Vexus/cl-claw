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
import type { OpenClawConfig } from "../config/config.js";
import {
  estimateUsageCost,
  formatTokenCount,
  formatUsd,
  resolveModelCostConfig,
} from "./usage-format.js";

(deftest-group "usage-format", () => {
  (deftest "formats token counts", () => {
    (expect* formatTokenCount(999)).is("999");
    (expect* formatTokenCount(1234)).is("1.2k");
    (expect* formatTokenCount(12000)).is("12k");
    (expect* formatTokenCount(999_499)).is("999k");
    (expect* formatTokenCount(999_500)).is("1.0m");
    (expect* formatTokenCount(2_500_000)).is("2.5m");
  });

  (deftest "formats USD values", () => {
    (expect* formatUsd(1.234)).is("$1.23");
    (expect* formatUsd(0.5)).is("$0.50");
    (expect* formatUsd(0.0042)).is("$0.0042");
  });

  (deftest "resolves model cost config and estimates usage cost", () => {
    const config = {
      models: {
        providers: {
          test: {
            models: [
              {
                id: "m1",
                cost: { input: 1, output: 2, cacheRead: 0.5, cacheWrite: 0 },
              },
            ],
          },
        },
      },
    } as unknown as OpenClawConfig;

    const cost = resolveModelCostConfig({
      provider: "test",
      model: "m1",
      config,
    });

    (expect* cost).is-equal({
      input: 1,
      output: 2,
      cacheRead: 0.5,
      cacheWrite: 0,
    });

    const total = estimateUsageCost({
      usage: { input: 1000, output: 500, cacheRead: 2000 },
      cost,
    });

    (expect* total).toBeCloseTo(0.003);
  });
});
