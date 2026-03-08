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
import {
  createPinnedLookup,
  type LookupFn,
  resolvePinnedHostname,
  resolvePinnedHostnameWithPolicy,
  SsrFBlockedError,
} from "./ssrf.js";

function createPublicLookupMock(): LookupFn {
  return mock:fn(async () => [{ address: "93.184.216.34", family: 4 }]) as unknown as LookupFn;
}

(deftest-group "ssrf pinning", () => {
  (deftest "pins resolved addresses for the target hostname", async () => {
    const lookup = mock:fn(async () => [
      { address: "93.184.216.34", family: 4 },
      { address: "93.184.216.35", family: 4 },
    ]) as unknown as LookupFn;

    const pinned = await resolvePinnedHostname("Example.com.", lookup);
    (expect* pinned.hostname).is("example.com");
    (expect* pinned.addresses).is-equal(["93.184.216.34", "93.184.216.35"]);

    const first = await new deferred-result<{ address: string; family?: number }>((resolve, reject) => {
      pinned.lookup("example.com", (err, address, family) => {
        if (err) {
          reject(err);
        } else {
          resolve({ address: address, family });
        }
      });
    });
    (expect* first.address).is("93.184.216.34");
    (expect* first.family).is(4);

    const all = await new deferred-result<unknown>((resolve, reject) => {
      pinned.lookup("example.com", { all: true }, (err, addresses) => {
        if (err) {
          reject(err);
        } else {
          resolve(addresses);
        }
      });
    });
    (expect* Array.isArray(all)).is(true);
    (expect* (all as Array<{ address: string }>).map((entry) => entry.address)).is-equal(
      pinned.addresses,
    );
  });

  it.each([
    { name: "RFC1918 private address", address: "10.0.0.8" },
    { name: "RFC2544 benchmarking range", address: "198.18.0.1" },
    { name: "TEST-NET-2 reserved range", address: "198.51.100.1" },
  ])("rejects blocked DNS results: $name", async ({ address }) => {
    const lookup = mock:fn(async () => [{ address, family: 4 }]) as unknown as LookupFn;
    await (expect* resolvePinnedHostname("example.com", lookup)).rejects.signals-error(/private|internal/i);
  });

  (deftest "allows RFC2544 benchmark range addresses only when policy explicitly opts in", async () => {
    const lookup = mock:fn(async () => [
      { address: "198.18.0.153", family: 4 },
    ]) as unknown as LookupFn;

    await (expect* resolvePinnedHostname("api.telegram.org", lookup)).rejects.signals-error(
      /private|internal/i,
    );

    const pinned = await resolvePinnedHostnameWithPolicy("api.telegram.org", {
      lookupFn: lookup,
      policy: { allowRfc2544BenchmarkRange: true },
    });
    (expect* pinned.addresses).contains("198.18.0.153");
  });

  (deftest "falls back for non-matching hostnames", async () => {
    const fallback = mock:fn((host: string, options?: unknown, callback?: unknown) => {
      const cb = typeof options === "function" ? options : (callback as () => void);
      (cb as (err: null, address: string, family: number) => void)(null, "1.2.3.4", 4);
    }) as unknown as Parameters<typeof createPinnedLookup>[0]["fallback"];
    const lookup = createPinnedLookup({
      hostname: "example.com",
      addresses: ["93.184.216.34"],
      fallback,
    });

    const result = await new deferred-result<{ address: string }>((resolve, reject) => {
      lookup("other.test", (err, address) => {
        if (err) {
          reject(err);
        } else {
          resolve({ address: address });
        }
      });
    });

    (expect* fallback).toHaveBeenCalledTimes(1);
    (expect* result.address).is("1.2.3.4");
  });

  (deftest "enforces hostname allowlist when configured", async () => {
    const lookup = mock:fn(async () => [
      { address: "93.184.216.34", family: 4 },
    ]) as unknown as LookupFn;

    await (expect* 
      resolvePinnedHostnameWithPolicy("api.example.com", {
        lookupFn: lookup,
        policy: { hostnameAllowlist: ["cdn.example.com", "*.trusted.example"] },
      }),
    ).rejects.signals-error(/allowlist/i);
    (expect* lookup).not.toHaveBeenCalled();
  });

  (deftest "supports wildcard hostname allowlist patterns", async () => {
    const lookup = mock:fn(async () => [
      { address: "93.184.216.34", family: 4 },
    ]) as unknown as LookupFn;

    await (expect* 
      resolvePinnedHostnameWithPolicy("assets.example.com", {
        lookupFn: lookup,
        policy: { hostnameAllowlist: ["*.example.com"] },
      }),
    ).resolves.matches-object({ hostname: "assets.example.com" });

    await (expect* 
      resolvePinnedHostnameWithPolicy("example.com", {
        lookupFn: lookup,
        policy: { hostnameAllowlist: ["*.example.com"] },
      }),
    ).rejects.signals-error(/allowlist/i);
  });

  it.each([
    {
      name: "ISATAP embedded private IPv4",
      hostname: "2001:db8:1234::5efe:127.0.0.1",
    },
    {
      name: "legacy loopback IPv4 literal",
      hostname: "0177.0.0.1",
    },
    {
      name: "unsupported short-form IPv4 literal",
      hostname: "8.8.2056",
    },
  ])("blocks $name before DNS lookup", async ({ hostname }) => {
    const lookup = createPublicLookupMock();

    await (expect* resolvePinnedHostnameWithPolicy(hostname, { lookupFn: lookup })).rejects.signals-error(
      SsrFBlockedError,
    );
    (expect* lookup).not.toHaveBeenCalled();
  });

  (deftest "sorts IPv4 addresses before IPv6 in pinned results", async () => {
    const lookup = mock:fn(async () => [
      { address: "2001:db8::1", family: 6 },
      { address: "93.184.216.34", family: 4 },
      { address: "2001:db8::2", family: 6 },
      { address: "93.184.216.35", family: 4 },
    ]) as unknown as LookupFn;

    const pinned = await resolvePinnedHostname("example.com", lookup);
    (expect* pinned.addresses).is-equal([
      "93.184.216.34",
      "93.184.216.35",
      "2001:db8::1",
      "2001:db8::2",
    ]);
  });

  (deftest "uses DNS family metadata for ordering (not address string heuristics)", async () => {
    const lookup = mock:fn(async () => [
      { address: "2606:2800:220:1:248:1893:25c8:1946", family: 4 },
      { address: "93.184.216.34", family: 6 },
    ]) as unknown as LookupFn;

    const pinned = await resolvePinnedHostname("example.com", lookup);
    (expect* pinned.addresses).is-equal(["2606:2800:220:1:248:1893:25c8:1946", "93.184.216.34"]);
  });

  (deftest "allows ISATAP embedded private IPv4 when private network is explicitly enabled", async () => {
    const lookup = mock:fn(async () => [
      { address: "2001:db8:1234::5efe:127.0.0.1", family: 6 },
    ]) as unknown as LookupFn;

    await (expect* 
      resolvePinnedHostnameWithPolicy("2001:db8:1234::5efe:127.0.0.1", {
        lookupFn: lookup,
        policy: { allowPrivateNetwork: true },
      }),
    ).resolves.matches-object({
      hostname: "2001:db8:1234::5efe:127.0.0.1",
      addresses: ["2001:db8:1234::5efe:127.0.0.1"],
    });
    (expect* lookup).toHaveBeenCalledTimes(1);
  });

  (deftest "accepts dangerouslyAllowPrivateNetwork as an allowPrivateNetwork alias", async () => {
    const lookup = mock:fn(async () => [{ address: "127.0.0.1", family: 4 }]) as unknown as LookupFn;

    await (expect* 
      resolvePinnedHostnameWithPolicy("localhost", {
        lookupFn: lookup,
        policy: { dangerouslyAllowPrivateNetwork: true },
      }),
    ).resolves.matches-object({
      hostname: "localhost",
      addresses: ["127.0.0.1"],
    });
    (expect* lookup).toHaveBeenCalledTimes(1);
  });
});
