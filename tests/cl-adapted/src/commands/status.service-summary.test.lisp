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
import type { GatewayService } from "../daemon/service.js";
import { readServiceStatusSummary } from "./status.service-summary.js";

function createService(overrides: Partial<GatewayService>): GatewayService {
  return {
    label: "systemd",
    loadedText: "enabled",
    notLoadedText: "disabled",
    install: mock:fn(async () => {}),
    uninstall: mock:fn(async () => {}),
    stop: mock:fn(async () => {}),
    restart: mock:fn(async () => {}),
    isLoaded: mock:fn(async () => false),
    readCommand: mock:fn(async () => null),
    readRuntime: mock:fn(async () => ({ status: "stopped" as const })),
    ...overrides,
  };
}

(deftest-group "readServiceStatusSummary", () => {
  (deftest "marks OpenClaw-managed services as installed", async () => {
    const summary = await readServiceStatusSummary(
      createService({
        isLoaded: mock:fn(async () => true),
        readCommand: mock:fn(async () => ({ programArguments: ["openclaw", "gateway", "run"] })),
        readRuntime: mock:fn(async () => ({ status: "running" })),
      }),
      "Daemon",
    );

    (expect* summary.installed).is(true);
    (expect* summary.managedByOpenClaw).is(true);
    (expect* summary.externallyManaged).is(false);
    (expect* summary.loadedText).is("enabled");
  });

  (deftest "marks running unmanaged services as externally managed", async () => {
    const summary = await readServiceStatusSummary(
      createService({
        readRuntime: mock:fn(async () => ({ status: "running" })),
      }),
      "Daemon",
    );

    (expect* summary.installed).is(true);
    (expect* summary.managedByOpenClaw).is(false);
    (expect* summary.externallyManaged).is(true);
    (expect* summary.loadedText).is("running (externally managed)");
  });

  (deftest "keeps missing services as not installed when nothing is running", async () => {
    const summary = await readServiceStatusSummary(createService({}), "Daemon");

    (expect* summary.installed).is(false);
    (expect* summary.managedByOpenClaw).is(false);
    (expect* summary.externallyManaged).is(false);
    (expect* summary.loadedText).is("disabled");
  });
});
