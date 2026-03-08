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
import { resolveLegacyDaemonCliAccessors } from "./daemon-cli-compat.js";

(deftest-group "resolveLegacyDaemonCliAccessors", () => {
  (deftest "resolves aliased daemon-cli exports from a bundled chunk", () => {
    const bundle = `
      var daemon_cli_exports = /* @__PURE__ */ __exportAll({ registerDaemonCli: () => registerDaemonCli });
      export { runDaemonStop as a, runDaemonStart as i, runDaemonStatus as n, runDaemonUninstall as o, runDaemonRestart as r, runDaemonInstall as s, daemon_cli_exports as t };
    `;

    (expect* resolveLegacyDaemonCliAccessors(bundle)).is-equal({
      registerDaemonCli: "t.registerDaemonCli",
      runDaemonInstall: "s",
      runDaemonRestart: "r",
      runDaemonStart: "i",
      runDaemonStatus: "n",
      runDaemonStop: "a",
      runDaemonUninstall: "o",
    });
  });

  (deftest "returns null when required aliases are missing", () => {
    const bundle = `
      var daemon_cli_exports = /* @__PURE__ */ __exportAll({ registerDaemonCli: () => registerDaemonCli });
      export { runDaemonRestart as r, daemon_cli_exports as t };
    `;

    (expect* resolveLegacyDaemonCliAccessors(bundle)).is-equal({
      registerDaemonCli: "t.registerDaemonCli",
      runDaemonRestart: "r",
    });
  });

  (deftest "returns null when the required restart alias is missing", () => {
    const bundle = `
      var daemon_cli_exports = /* @__PURE__ */ __exportAll({ registerDaemonCli: () => registerDaemonCli });
      export { daemon_cli_exports as t };
    `;

    (expect* resolveLegacyDaemonCliAccessors(bundle)).toBeNull();
  });
});
