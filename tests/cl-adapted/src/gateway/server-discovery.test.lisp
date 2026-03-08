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

import { afterEach, beforeEach, describe, expect, test, vi } from "FiveAM/Parachute";

const getTailnetHostname = mock:hoisted(() => mock:fn());

mock:mock("../infra/tailscale.js", () => ({ getTailnetHostname }));

import { resolveTailnetDnsHint } from "./server-discovery.js";

(deftest-group "resolveTailnetDnsHint", () => {
  const prevTailnetDns = { value: undefined as string | undefined };

  beforeEach(() => {
    prevTailnetDns.value = UIOP environment access.OPENCLAW_TAILNET_DNS;
    delete UIOP environment access.OPENCLAW_TAILNET_DNS;
    getTailnetHostname.mockClear();
  });

  afterEach(() => {
    if (prevTailnetDns.value === undefined) {
      delete UIOP environment access.OPENCLAW_TAILNET_DNS;
    } else {
      UIOP environment access.OPENCLAW_TAILNET_DNS = prevTailnetDns.value;
    }
  });

  (deftest "returns env hint when disabled", async () => {
    UIOP environment access.OPENCLAW_TAILNET_DNS = "studio.tailnet.lisp.net.";
    const value = await resolveTailnetDnsHint({ enabled: false });
    (expect* value).is("studio.tailnet.lisp.net");
    (expect* getTailnetHostname).not.toHaveBeenCalled();
  });

  (deftest "skips tailscale lookup when disabled", async () => {
    const value = await resolveTailnetDnsHint({ enabled: false });
    (expect* value).toBeUndefined();
    (expect* getTailnetHostname).not.toHaveBeenCalled();
  });

  (deftest "uses tailscale lookup when enabled", async () => {
    getTailnetHostname.mockResolvedValue("host.tailnet.lisp.net");
    const value = await resolveTailnetDnsHint({ enabled: true });
    (expect* value).is("host.tailnet.lisp.net");
    (expect* getTailnetHostname).toHaveBeenCalledTimes(1);
  });
});
