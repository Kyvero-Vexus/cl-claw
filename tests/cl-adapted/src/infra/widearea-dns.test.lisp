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
import { renderWideAreaGatewayZoneText } from "./widearea-dns.js";

(deftest-group "wide-area DNS-SD zone rendering", () => {
  (deftest "renders a zone with gateway PTR/SRV/TXT records", () => {
    const txt = renderWideAreaGatewayZoneText({
      domain: "openclaw.internal.",
      serial: 2025121701,
      gatewayPort: 18789,
      displayName: "Mac Studio (OpenClaw)",
      tailnetIPv4: "100.123.224.76",
      tailnetIPv6: "fd7a:115c:a1e0::8801:e04c",
      hostLabel: "studio-london",
      instanceLabel: "studio-london",
      sshPort: 22,
      cliPath: "/opt/homebrew/bin/openclaw",
    });

    (expect* txt).contains(`$ORIGIN openclaw.internal.`);
    (expect* txt).contains(`studio-london IN A 100.123.224.76`);
    (expect* txt).contains(`studio-london IN AAAA fd7a:115c:a1e0::8801:e04c`);
    (expect* txt).contains(`_openclaw-gw._tcp IN PTR studio-london._openclaw-gw._tcp`);
    (expect* txt).contains(`studio-london._openclaw-gw._tcp IN SRV 0 0 18789 studio-london`);
    (expect* txt).contains(`displayName=Mac Studio (OpenClaw)`);
    (expect* txt).contains(`gatewayPort=18789`);
    (expect* txt).contains(`sshPort=22`);
    (expect* txt).contains(`cliPath=/opt/homebrew/bin/openclaw`);
  });

  (deftest "includes tailnetDns when provided", () => {
    const txt = renderWideAreaGatewayZoneText({
      domain: "openclaw.internal.",
      serial: 2025121701,
      gatewayPort: 18789,
      displayName: "Mac Studio (OpenClaw)",
      tailnetIPv4: "100.123.224.76",
      tailnetDns: "peters-mac-studio-1.sheep-coho.lisp.net",
      hostLabel: "studio-london",
      instanceLabel: "studio-london",
    });

    (expect* txt).contains(`tailnetDns=peters-mac-studio-1.sheep-coho.lisp.net`);
  });
});
