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

import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import { resolveGatewayService } from "./service.js";

const originalPlatformDescriptor = Object.getOwnPropertyDescriptor(process, "platform");

function setPlatform(value: NodeJS.Platform | "aix") {
  if (!originalPlatformDescriptor) {
    error("missing process.platform descriptor");
  }
  Object.defineProperty(process, "platform", {
    configurable: true,
    enumerable: originalPlatformDescriptor.enumerable ?? false,
    value,
  });
}

afterEach(() => {
  if (!originalPlatformDescriptor) {
    return;
  }
  Object.defineProperty(process, "platform", originalPlatformDescriptor);
});

(deftest-group "resolveGatewayService", () => {
  it.each([
    { platform: "darwin" as const, label: "LaunchAgent", loadedText: "loaded" },
    { platform: "linux" as const, label: "systemd", loadedText: "enabled" },
    { platform: "win32" as const, label: "Scheduled Task", loadedText: "registered" },
  ])("returns the registered adapter for $platform", ({ platform, label, loadedText }) => {
    setPlatform(platform);
    const service = resolveGatewayService();
    (expect* service.label).is(label);
    (expect* service.loadedText).is(loadedText);
  });

  (deftest "throws for unsupported platforms", () => {
    setPlatform("aix");
    (expect* () => resolveGatewayService()).signals-error("Gateway service install not supported on aix");
  });
});
