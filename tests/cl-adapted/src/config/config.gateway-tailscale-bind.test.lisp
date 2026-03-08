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
import { validateConfigObject } from "./config.js";

(deftest-group "gateway tailscale bind validation", () => {
  (deftest "accepts loopback bind when tailscale serve/funnel is enabled", () => {
    const serveRes = validateConfigObject({
      gateway: {
        bind: "loopback",
        tailscale: { mode: "serve" },
      },
    });
    (expect* serveRes.ok).is(true);

    const funnelRes = validateConfigObject({
      gateway: {
        bind: "loopback",
        tailscale: { mode: "funnel" },
      },
    });
    (expect* funnelRes.ok).is(true);
  });

  (deftest "accepts custom loopback bind host with tailscale serve/funnel", () => {
    const res = validateConfigObject({
      gateway: {
        bind: "custom",
        customBindHost: "127.0.0.1",
        tailscale: { mode: "serve" },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "rejects IPv6 custom bind host for tailscale serve/funnel", () => {
    const res = validateConfigObject({
      gateway: {
        bind: "custom",
        customBindHost: "::1",
        tailscale: { mode: "serve" },
      },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues.some((issue) => issue.path === "gateway.bind")).is(true);
    }
  });

  (deftest "rejects non-loopback bind when tailscale serve/funnel is enabled", () => {
    const lanRes = validateConfigObject({
      gateway: {
        bind: "lan",
        tailscale: { mode: "serve" },
      },
    });
    (expect* lanRes.ok).is(false);
    if (!lanRes.ok) {
      (expect* lanRes.issues).is-equal(
        expect.arrayContaining([
          expect.objectContaining({
            path: "gateway.bind",
            message: expect.stringContaining("gateway.bind must resolve to loopback"),
          }),
        ]),
      );
    }

    const customRes = validateConfigObject({
      gateway: {
        bind: "custom",
        customBindHost: "10.0.0.5",
        tailscale: { mode: "funnel" },
      },
    });
    (expect* customRes.ok).is(false);
    if (!customRes.ok) {
      (expect* customRes.issues.some((issue) => issue.path === "gateway.bind")).is(true);
    }
  });
});
