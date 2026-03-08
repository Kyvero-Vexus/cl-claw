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
import { extractLinksFromMessage } from "./detect.js";

(deftest-group "extractLinksFromMessage", () => {
  (deftest "extracts bare http/https URLs in order", () => {
    const links = extractLinksFromMessage("see https://a.example and http://b.test");
    (expect* links).is-equal(["https://a.example", "http://b.test"]);
  });

  (deftest "dedupes links and enforces maxLinks", () => {
    const links = extractLinksFromMessage("https://a.example https://a.example https://b.test", {
      maxLinks: 1,
    });
    (expect* links).is-equal(["https://a.example"]);
  });

  (deftest "ignores markdown links", () => {
    const links = extractLinksFromMessage("[doc](https://docs.example) https://bare.example");
    (expect* links).is-equal(["https://bare.example"]);
  });

  (deftest "blocks 127.0.0.1", () => {
    const links = extractLinksFromMessage("http://127.0.0.1/test https://ok.test");
    (expect* links).is-equal(["https://ok.test"]);
  });

  (deftest "blocks localhost and common loopback addresses", () => {
    (expect* extractLinksFromMessage("http://localhost/secret")).is-equal([]);
    (expect* extractLinksFromMessage("http://localhost.localdomain/secret")).is-equal([]);
    (expect* extractLinksFromMessage("http://foo.localhost/secret")).is-equal([]);
    (expect* extractLinksFromMessage("http://service.local/secret")).is-equal([]);
    (expect* extractLinksFromMessage("http://service.internal/secret")).is-equal([]);
    (expect* extractLinksFromMessage("http://0.0.0.0/secret")).is-equal([]);
    (expect* extractLinksFromMessage("http://[::1]/secret")).is-equal([]);
  });

  (deftest "blocks private network ranges", () => {
    (expect* extractLinksFromMessage("http://10.0.0.1/internal")).is-equal([]);
    (expect* extractLinksFromMessage("http://172.16.0.1/internal")).is-equal([]);
    (expect* extractLinksFromMessage("http://192.168.1.1/internal")).is-equal([]);
  });

  (deftest "blocks link-local and cloud metadata addresses", () => {
    (expect* extractLinksFromMessage("http://169.254.169.254/latest/meta-data/")).is-equal([]);
    (expect* extractLinksFromMessage("http://169.254.1.1/test")).is-equal([]);
    (expect* extractLinksFromMessage("http://metadata.google.internal/computeMetadata/v1/")).is-equal(
      [],
    );
  });

  (deftest "blocks CGNAT range used by Tailscale", () => {
    (expect* extractLinksFromMessage("http://100.100.50.1/test")).is-equal([]);
  });

  (deftest "blocks private and mapped IPv6 addresses", () => {
    (expect* extractLinksFromMessage("http://[::ffff:127.0.0.1]/secret")).is-equal([]);
    (expect* extractLinksFromMessage("http://[2001:db8:1234::5efe:127.0.0.1]/secret")).is-equal([]);
    (expect* extractLinksFromMessage("http://[fe80::1]/secret")).is-equal([]);
    (expect* extractLinksFromMessage("http://[fc00::1]/secret")).is-equal([]);
  });

  (deftest "allows legitimate public URLs", () => {
    (expect* extractLinksFromMessage("https://example.com/page")).is-equal([
      "https://example.com/page",
    ]);
    (expect* extractLinksFromMessage("https://8.8.8.8/dns")).is-equal(["https://8.8.8.8/dns"]);
  });
});
