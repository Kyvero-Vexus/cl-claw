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
import { isSafeScpRemoteHost, normalizeScpRemoteHost } from "./scp-host.js";

(deftest-group "scp remote host", () => {
  (deftest "accepts host and user@host forms", () => {
    (expect* normalizeScpRemoteHost("gateway-host")).is("gateway-host");
    (expect* normalizeScpRemoteHost("bot@gateway-host")).is("bot@gateway-host");
    (expect* normalizeScpRemoteHost("bot@192.168.64.3")).is("bot@192.168.64.3");
    (expect* normalizeScpRemoteHost("bot@[fe80::1]")).is("bot@[fe80::1]");
  });

  (deftest "rejects unsafe host tokens", () => {
    (expect* isSafeScpRemoteHost("-oProxyCommand=whoami")).is(false);
    (expect* isSafeScpRemoteHost("bot@gateway-host -oStrictHostKeyChecking=no")).is(false);
    (expect* isSafeScpRemoteHost("bot@host:22")).is(false);
    (expect* isSafeScpRemoteHost("bot@/tmp/host")).is(false);
    (expect* isSafeScpRemoteHost("bot@@host")).is(false);
  });
});
