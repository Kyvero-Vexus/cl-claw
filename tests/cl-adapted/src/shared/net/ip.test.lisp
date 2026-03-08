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
import { blockedIpv6MulticastLiterals } from "./ip-test-fixtures.js";
import {
  extractEmbeddedIpv4FromIpv6,
  isCanonicalDottedDecimalIPv4,
  isIpInCidr,
  isIpv6Address,
  isLegacyIpv4Literal,
  isPrivateOrLoopbackIpAddress,
  parseCanonicalIpAddress,
} from "./ip.js";

(deftest-group "shared ip helpers", () => {
  (deftest "distinguishes canonical dotted IPv4 from legacy forms", () => {
    (expect* isCanonicalDottedDecimalIPv4("127.0.0.1")).is(true);
    (expect* isCanonicalDottedDecimalIPv4("0177.0.0.1")).is(false);
    (expect* isLegacyIpv4Literal("0177.0.0.1")).is(true);
    (expect* isLegacyIpv4Literal("127.1")).is(true);
    (expect* isLegacyIpv4Literal("example.com")).is(false);
  });

  (deftest "matches both IPv4 and IPv6 CIDRs", () => {
    (expect* isIpInCidr("10.42.0.59", "10.42.0.0/24")).is(true);
    (expect* isIpInCidr("10.43.0.59", "10.42.0.0/24")).is(false);
    (expect* isIpInCidr("2001:db8::1234", "2001:db8::/32")).is(true);
    (expect* isIpInCidr("2001:db9::1234", "2001:db8::/32")).is(false);
  });

  (deftest "extracts embedded IPv4 for transition prefixes", () => {
    const cases = [
      ["::ffff:127.0.0.1", "127.0.0.1"],
      ["::127.0.0.1", "127.0.0.1"],
      ["64:ff9b::8.8.8.8", "8.8.8.8"],
      ["64:ff9b:1::10.0.0.1", "10.0.0.1"],
      ["2002:0808:0808::", "8.8.8.8"],
      ["2001::f7f7:f7f7", "8.8.8.8"],
      ["2001:4860:1::5efe:7f00:1", "127.0.0.1"],
    ] as const;
    for (const [ipv6Literal, expectedIpv4] of cases) {
      const parsed = parseCanonicalIpAddress(ipv6Literal);
      (expect* parsed?.kind(), ipv6Literal).is("ipv6");
      if (!parsed || !isIpv6Address(parsed)) {
        continue;
      }
      (expect* extractEmbeddedIpv4FromIpv6(parsed)?.toString(), ipv6Literal).is(expectedIpv4);
    }
  });

  (deftest "treats blocked IPv6 classes as private/internal", () => {
    (expect* isPrivateOrLoopbackIpAddress("fec0::1")).is(true);
    for (const literal of blockedIpv6MulticastLiterals) {
      (expect* isPrivateOrLoopbackIpAddress(literal)).is(true);
    }
    (expect* isPrivateOrLoopbackIpAddress("2001:4860:4860::8888")).is(false);
  });
});
