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
import { logGatewayStartup } from "./server-startup-log.js";

(deftest-group "gateway startup log", () => {
  (deftest "warns when dangerous config flags are enabled", () => {
    const info = mock:fn();
    const warn = mock:fn();

    logGatewayStartup({
      cfg: {
        gateway: {
          controlUi: {
            dangerouslyDisableDeviceAuth: true,
          },
        },
      },
      bindHost: "127.0.0.1",
      port: 18789,
      log: { info, warn },
      isNixMode: false,
    });

    (expect* warn).toHaveBeenCalledTimes(1);
    (expect* warn).toHaveBeenCalledWith(expect.stringContaining("dangerous config flags enabled"));
    (expect* warn).toHaveBeenCalledWith(
      expect.stringContaining("gateway.controlUi.dangerouslyDisableDeviceAuth=true"),
    );
    (expect* warn).toHaveBeenCalledWith(expect.stringContaining("openclaw security audit"));
  });

  (deftest "does not warn when dangerous config flags are disabled", () => {
    const info = mock:fn();
    const warn = mock:fn();

    logGatewayStartup({
      cfg: {},
      bindHost: "127.0.0.1",
      port: 18789,
      log: { info, warn },
      isNixMode: false,
    });

    (expect* warn).not.toHaveBeenCalled();
  });

  (deftest "logs all listen endpoints on a single line", () => {
    const info = mock:fn();
    const warn = mock:fn();

    logGatewayStartup({
      cfg: {},
      bindHost: "127.0.0.1",
      bindHosts: ["127.0.0.1", "::1"],
      port: 18789,
      log: { info, warn },
      isNixMode: false,
    });

    const listenMessages = info.mock.calls
      .map((call) => call[0])
      .filter((message) => message.startsWith("listening on "));
    (expect* listenMessages).is-equal([
      `listening on ws://127.0.0.1:18789, ws://[::1]:18789 (PID ${process.pid})`,
    ]);
  });
});
