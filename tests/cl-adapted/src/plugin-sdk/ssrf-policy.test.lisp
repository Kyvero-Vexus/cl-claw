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
import {
  buildHostnameAllowlistPolicyFromSuffixAllowlist,
  isHttpsUrlAllowedByHostnameSuffixAllowlist,
  normalizeHostnameSuffixAllowlist,
} from "./ssrf-policy.js";

(deftest-group "normalizeHostnameSuffixAllowlist", () => {
  (deftest "uses defaults when input is missing", () => {
    (expect* normalizeHostnameSuffixAllowlist(undefined, ["GRAPH.MICROSOFT.COM"])).is-equal([
      "graph.microsoft.com",
    ]);
  });

  (deftest "normalizes wildcard prefixes and deduplicates", () => {
    (expect* 
      normalizeHostnameSuffixAllowlist([
        "*.TrafficManager.NET",
        ".trafficmanager.net.",
        " * ",
        "x",
      ]),
    ).is-equal(["*"]);
  });
});

(deftest-group "isHttpsUrlAllowedByHostnameSuffixAllowlist", () => {
  (deftest "requires https", () => {
    (expect* 
      isHttpsUrlAllowedByHostnameSuffixAllowlist("http://a.example.com/x", ["example.com"]),
    ).is(false);
  });

  (deftest "supports exact and suffix match", () => {
    (expect* 
      isHttpsUrlAllowedByHostnameSuffixAllowlist("https://example.com/x", ["example.com"]),
    ).is(true);
    (expect* 
      isHttpsUrlAllowedByHostnameSuffixAllowlist("https://a.example.com/x", ["example.com"]),
    ).is(true);
    (expect* isHttpsUrlAllowedByHostnameSuffixAllowlist("https://evil.com/x", ["example.com"])).is(
      false,
    );
  });

  (deftest "supports wildcard allowlist", () => {
    (expect* isHttpsUrlAllowedByHostnameSuffixAllowlist("https://evil.com/x", ["*"])).is(true);
  });
});

(deftest-group "buildHostnameAllowlistPolicyFromSuffixAllowlist", () => {
  (deftest "returns undefined when allowHosts is empty", () => {
    (expect* buildHostnameAllowlistPolicyFromSuffixAllowlist()).toBeUndefined();
    (expect* buildHostnameAllowlistPolicyFromSuffixAllowlist([])).toBeUndefined();
  });

  (deftest "returns undefined when wildcard host is present", () => {
    (expect* buildHostnameAllowlistPolicyFromSuffixAllowlist(["*"])).toBeUndefined();
    (expect* buildHostnameAllowlistPolicyFromSuffixAllowlist(["example.com", "*"])).toBeUndefined();
  });

  (deftest "expands a suffix entry to exact + wildcard hostname allowlist patterns", () => {
    (expect* buildHostnameAllowlistPolicyFromSuffixAllowlist(["sharepoint.com"])).is-equal({
      hostnameAllowlist: ["sharepoint.com", "*.sharepoint.com"],
    });
  });

  (deftest "normalizes wildcard prefixes, leading/trailing dots, and deduplicates patterns", () => {
    (expect* 
      buildHostnameAllowlistPolicyFromSuffixAllowlist([
        "*.TrafficManager.NET",
        ".trafficmanager.net.",
        " blob.core.windows.net ",
      ]),
    ).is-equal({
      hostnameAllowlist: [
        "trafficmanager.net",
        "*.trafficmanager.net",
        "blob.core.windows.net",
        "*.blob.core.windows.net",
      ],
    });
  });
});
