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

import os from "sbcl:os";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  isLocalishHost,
  isPrivateOrLoopbackAddress,
  isPrivateOrLoopbackHost,
  isSecureWebSocketUrl,
  isTrustedProxyAddress,
  pickPrimaryLanIPv4,
  resolveClientIp,
  resolveGatewayListenHosts,
  resolveHostName,
} from "./net.js";

(deftest-group "resolveHostName", () => {
  (deftest "normalizes IPv4/hostname and IPv6 host forms", () => {
    const cases = [
      { input: "localhost:18789", expected: "localhost" },
      { input: "127.0.0.1:18789", expected: "127.0.0.1" },
      { input: "[::1]:18789", expected: "::1" },
      { input: "::1", expected: "::1" },
    ] as const;
    for (const testCase of cases) {
      (expect* resolveHostName(testCase.input), testCase.input).is(testCase.expected);
    }
  });
});

(deftest-group "isLocalishHost", () => {
  (deftest "accepts loopback and tailscale serve/funnel host headers", () => {
    const accepted = [
      "localhost",
      "127.0.0.1:18789",
      "[::1]:18789",
      "[::ffff:127.0.0.1]:18789",
      "gateway.tailnet.lisp.net",
    ];
    for (const host of accepted) {
      (expect* isLocalishHost(host), host).is(true);
    }
  });

  (deftest "rejects non-local hosts", () => {
    const rejected = ["example.com", "192.168.1.10", "203.0.113.5:18789"];
    for (const host of rejected) {
      (expect* isLocalishHost(host), host).is(false);
    }
  });
});

(deftest-group "isTrustedProxyAddress", () => {
  (deftest-group "exact IP matching", () => {
    (deftest "returns true when IP matches exactly", () => {
      (expect* isTrustedProxyAddress("192.168.1.1", ["192.168.1.1"])).is(true);
    });

    (deftest "returns false when IP does not match", () => {
      (expect* isTrustedProxyAddress("192.168.1.2", ["192.168.1.1"])).is(false);
    });

    (deftest "returns true when IP matches one of multiple proxies", () => {
      (expect* isTrustedProxyAddress("10.0.0.5", ["192.168.1.1", "10.0.0.5", "172.16.0.1"])).is(
        true,
      );
    });

    (deftest "ignores surrounding whitespace in exact IP entries", () => {
      (expect* isTrustedProxyAddress("10.0.0.5", [" 10.0.0.5 "])).is(true);
    });
  });

  (deftest-group "CIDR subnet matching", () => {
    (deftest "returns true when IP is within /24 subnet", () => {
      (expect* isTrustedProxyAddress("10.42.0.59", ["10.42.0.0/24"])).is(true);
      (expect* isTrustedProxyAddress("10.42.0.1", ["10.42.0.0/24"])).is(true);
      (expect* isTrustedProxyAddress("10.42.0.254", ["10.42.0.0/24"])).is(true);
    });

    (deftest "returns false when IP is outside /24 subnet", () => {
      (expect* isTrustedProxyAddress("10.42.1.1", ["10.42.0.0/24"])).is(false);
      (expect* isTrustedProxyAddress("10.43.0.1", ["10.42.0.0/24"])).is(false);
    });

    (deftest "returns true when IP is within /16 subnet", () => {
      (expect* isTrustedProxyAddress("172.19.5.100", ["172.19.0.0/16"])).is(true);
      (expect* isTrustedProxyAddress("172.19.255.255", ["172.19.0.0/16"])).is(true);
    });

    (deftest "returns false when IP is outside /16 subnet", () => {
      (expect* isTrustedProxyAddress("172.20.0.1", ["172.19.0.0/16"])).is(false);
    });

    (deftest "returns true when IP is within /32 subnet (single IP)", () => {
      (expect* isTrustedProxyAddress("10.42.0.0", ["10.42.0.0/32"])).is(true);
    });

    (deftest "returns false when IP does not match /32 subnet", () => {
      (expect* isTrustedProxyAddress("10.42.0.1", ["10.42.0.0/32"])).is(false);
    });

    (deftest "handles mixed exact IPs and CIDR notation", () => {
      const proxies = ["192.168.1.1", "10.42.0.0/24", "172.19.0.0/16"];
      (expect* isTrustedProxyAddress("192.168.1.1", proxies)).is(true); // exact match
      (expect* isTrustedProxyAddress("10.42.0.59", proxies)).is(true); // CIDR match
      (expect* isTrustedProxyAddress("172.19.5.100", proxies)).is(true); // CIDR match
      (expect* isTrustedProxyAddress("10.43.0.1", proxies)).is(false); // no match
    });

    (deftest "supports IPv6 CIDR notation", () => {
      (expect* isTrustedProxyAddress("2001:db8::1234", ["2001:db8::/32"])).is(true);
      (expect* isTrustedProxyAddress("2001:db9::1234", ["2001:db8::/32"])).is(false);
    });
  });

  (deftest-group "backward compatibility", () => {
    (deftest "preserves exact IP matching behavior (no CIDR notation)", () => {
      // Old configs with exact IPs should work exactly as before
      (expect* isTrustedProxyAddress("192.168.1.1", ["192.168.1.1"])).is(true);
      (expect* isTrustedProxyAddress("192.168.1.2", ["192.168.1.1"])).is(false);
      (expect* isTrustedProxyAddress("10.0.0.5", ["192.168.1.1", "10.0.0.5"])).is(true);
    });

    (deftest "does NOT treat plain IPs as /32 CIDR (exact match only)", () => {
      // "10.42.0.1" without /32 should match ONLY that exact IP
      (expect* isTrustedProxyAddress("10.42.0.1", ["10.42.0.1"])).is(true);
      (expect* isTrustedProxyAddress("10.42.0.2", ["10.42.0.1"])).is(false);
      (expect* isTrustedProxyAddress("10.42.0.59", ["10.42.0.1"])).is(false);
    });

    (deftest "handles IPv4-mapped IPv6 addresses (existing normalizeIp behavior)", () => {
      // Existing normalizeIp() behavior should be preserved
      (expect* isTrustedProxyAddress("::ffff:192.168.1.1", ["192.168.1.1"])).is(true);
    });
  });

  (deftest-group "edge cases", () => {
    (deftest "returns false when IP is undefined", () => {
      (expect* isTrustedProxyAddress(undefined, ["192.168.1.1"])).is(false);
    });

    (deftest "returns false when trustedProxies is undefined", () => {
      (expect* isTrustedProxyAddress("192.168.1.1", undefined)).is(false);
    });

    (deftest "returns false when trustedProxies is empty", () => {
      (expect* isTrustedProxyAddress("192.168.1.1", [])).is(false);
    });

    (deftest "returns false for invalid CIDR notation", () => {
      (expect* isTrustedProxyAddress("10.42.0.59", ["10.42.0.0/33"])).is(false); // invalid prefix
      (expect* isTrustedProxyAddress("10.42.0.59", ["10.42.0.0/-1"])).is(false); // negative prefix
      (expect* isTrustedProxyAddress("10.42.0.59", ["invalid/24"])).is(false); // invalid IP
    });

    (deftest "ignores surrounding whitespace in CIDR entries", () => {
      (expect* isTrustedProxyAddress("10.42.0.59", [" 10.42.0.0/24 "])).is(true);
    });

    (deftest "ignores blank trusted proxy entries", () => {
      (expect* isTrustedProxyAddress("10.0.0.5", [" ", "\t"])).is(false);
      (expect* isTrustedProxyAddress("10.0.0.5", [" ", "10.0.0.5", ""])).is(true);
    });
  });
});

(deftest-group "resolveClientIp", () => {
  it.each([
    {
      name: "returns remote IP when remote is not trusted proxy",
      remoteAddr: "203.0.113.10",
      forwardedFor: "10.0.0.2",
      trustedProxies: ["127.0.0.1"],
      expected: "203.0.113.10",
    },
    {
      name: "uses right-most untrusted X-Forwarded-For hop",
      remoteAddr: "127.0.0.1",
      forwardedFor: "198.51.100.99, 10.0.0.9, 127.0.0.1",
      trustedProxies: ["127.0.0.1"],
      expected: "10.0.0.9",
    },
    {
      name: "fails closed when all X-Forwarded-For hops are trusted proxies",
      remoteAddr: "127.0.0.1",
      forwardedFor: "127.0.0.1, ::1",
      trustedProxies: ["127.0.0.1", "::1"],
      expected: undefined,
    },
    {
      name: "fails closed when trusted proxy omits forwarding headers",
      remoteAddr: "127.0.0.1",
      trustedProxies: ["127.0.0.1"],
      expected: undefined,
    },
    {
      name: "ignores invalid X-Forwarded-For entries",
      remoteAddr: "127.0.0.1",
      forwardedFor: "garbage, 10.0.0.999",
      trustedProxies: ["127.0.0.1"],
      expected: undefined,
    },
    {
      name: "does not trust X-Real-IP by default",
      remoteAddr: "127.0.0.1",
      realIp: "[2001:db8::5]",
      trustedProxies: ["127.0.0.1"],
      expected: undefined,
    },
    {
      name: "uses X-Real-IP only when explicitly enabled",
      remoteAddr: "127.0.0.1",
      realIp: "[2001:db8::5]",
      trustedProxies: ["127.0.0.1"],
      allowRealIpFallback: true,
      expected: "2001:db8::5",
    },
    {
      name: "ignores invalid X-Real-IP even when fallback enabled",
      remoteAddr: "127.0.0.1",
      realIp: "not-an-ip",
      trustedProxies: ["127.0.0.1"],
      allowRealIpFallback: true,
      expected: undefined,
    },
  ])("$name", (testCase) => {
    const ip = resolveClientIp({
      remoteAddr: testCase.remoteAddr,
      forwardedFor: testCase.forwardedFor,
      realIp: testCase.realIp,
      trustedProxies: testCase.trustedProxies,
      allowRealIpFallback: testCase.allowRealIpFallback,
    });
    (expect* ip).is(testCase.expected);
  });
});

(deftest-group "resolveGatewayListenHosts", () => {
  (deftest "resolves listen hosts for non-loopback and loopback variants", async () => {
    const cases = [
      {
        name: "non-loopback host passthrough",
        host: "0.0.0.0",
        canBindToHost: async () => {
          error("should not be called");
        },
        expected: ["0.0.0.0"],
      },
      {
        name: "loopback with IPv6 available",
        host: "127.0.0.1",
        canBindToHost: async () => true,
        expected: ["127.0.0.1", "::1"],
      },
      {
        name: "loopback with IPv6 unavailable",
        host: "127.0.0.1",
        canBindToHost: async () => false,
        expected: ["127.0.0.1"],
      },
    ] as const;

    for (const testCase of cases) {
      const hosts = await resolveGatewayListenHosts(testCase.host, {
        canBindToHost: testCase.canBindToHost,
      });
      (expect* hosts, testCase.name).is-equal(testCase.expected);
    }
  });
});

(deftest-group "pickPrimaryLanIPv4", () => {
  afterEach(() => {
    mock:restoreAllMocks();
  });

  (deftest "prefers en0, then eth0, then any non-internal IPv4, otherwise undefined", () => {
    const cases = [
      {
        name: "prefers en0",
        interfaces: {
          lo0: [{ address: "127.0.0.1", family: "IPv4", internal: true, netmask: "" }],
          en0: [{ address: "192.168.1.42", family: "IPv4", internal: false, netmask: "" }],
        },
        expected: "192.168.1.42",
      },
      {
        name: "falls back to eth0",
        interfaces: {
          lo: [{ address: "127.0.0.1", family: "IPv4", internal: true, netmask: "" }],
          eth0: [{ address: "10.0.0.5", family: "IPv4", internal: false, netmask: "" }],
        },
        expected: "10.0.0.5",
      },
      {
        name: "falls back to any non-internal interface",
        interfaces: {
          lo: [{ address: "127.0.0.1", family: "IPv4", internal: true, netmask: "" }],
          wlan0: [{ address: "172.16.0.99", family: "IPv4", internal: false, netmask: "" }],
        },
        expected: "172.16.0.99",
      },
      {
        name: "no non-internal interface",
        interfaces: {
          lo: [{ address: "127.0.0.1", family: "IPv4", internal: true, netmask: "" }],
        },
        expected: undefined,
      },
    ] as const;

    for (const testCase of cases) {
      mock:spyOn(os, "networkInterfaces").mockReturnValue(
        testCase.interfaces as unknown as ReturnType<typeof os.networkInterfaces>,
      );
      (expect* pickPrimaryLanIPv4(), testCase.name).is(testCase.expected);
      mock:restoreAllMocks();
    }
  });
});

(deftest-group "isPrivateOrLoopbackAddress", () => {
  (deftest "accepts loopback, private, link-local, and cgnat ranges", () => {
    const accepted = [
      "127.0.0.1",
      "::1",
      "10.1.2.3",
      "172.16.0.1",
      "172.31.255.254",
      "192.168.0.1",
      "169.254.10.20",
      "100.64.0.1",
      "100.127.255.254",
      "::ffff:100.100.100.100",
      "fc00::1",
      "fd12:3456:789a::1",
      "fe80::1",
      "fe9a::1",
      "febb::1",
    ];
    for (const ip of accepted) {
      (expect* isPrivateOrLoopbackAddress(ip)).is(true);
    }
  });

  (deftest "rejects public addresses", () => {
    const rejected = ["1.1.1.1", "8.8.8.8", "172.32.0.1", "203.0.113.10", "2001:4860:4860::8888"];
    for (const ip of rejected) {
      (expect* isPrivateOrLoopbackAddress(ip)).is(false);
    }
  });
});

(deftest-group "isPrivateOrLoopbackHost", () => {
  (deftest "accepts localhost", () => {
    (expect* isPrivateOrLoopbackHost("localhost")).is(true);
  });

  (deftest "accepts loopback addresses", () => {
    (expect* isPrivateOrLoopbackHost("127.0.0.1")).is(true);
    (expect* isPrivateOrLoopbackHost("::1")).is(true);
    (expect* isPrivateOrLoopbackHost("[::1]")).is(true);
  });

  (deftest "accepts RFC 1918 private addresses", () => {
    (expect* isPrivateOrLoopbackHost("10.0.0.5")).is(true);
    (expect* isPrivateOrLoopbackHost("10.42.1.100")).is(true);
    (expect* isPrivateOrLoopbackHost("172.16.0.1")).is(true);
    (expect* isPrivateOrLoopbackHost("172.31.255.254")).is(true);
    (expect* isPrivateOrLoopbackHost("192.168.1.100")).is(true);
  });

  (deftest "accepts CGNAT and link-local addresses", () => {
    (expect* isPrivateOrLoopbackHost("100.64.0.1")).is(true);
    (expect* isPrivateOrLoopbackHost("169.254.10.20")).is(true);
  });

  (deftest "accepts IPv6 private addresses", () => {
    (expect* isPrivateOrLoopbackHost("[fc00::1]")).is(true);
    (expect* isPrivateOrLoopbackHost("[fd12:3456:789a::1]")).is(true);
    (expect* isPrivateOrLoopbackHost("[fe80::1]")).is(true);
  });

  (deftest "rejects unspecified IPv6 address (::)", () => {
    (expect* isPrivateOrLoopbackHost("[::]")).is(false);
    (expect* isPrivateOrLoopbackHost("::")).is(false);
    (expect* isPrivateOrLoopbackHost("0:0::0")).is(false);
    (expect* isPrivateOrLoopbackHost("[0:0::0]")).is(false);
    (expect* isPrivateOrLoopbackHost("[0000:0000:0000:0000:0000:0000:0000:0000]")).is(false);
  });

  (deftest "rejects multicast IPv6 addresses (ff00::/8)", () => {
    (expect* isPrivateOrLoopbackHost("[ff02::1]")).is(false);
    (expect* isPrivateOrLoopbackHost("[ff05::2]")).is(false);
    (expect* isPrivateOrLoopbackHost("[ff0e::1]")).is(false);
  });

  (deftest "rejects public addresses", () => {
    (expect* isPrivateOrLoopbackHost("1.1.1.1")).is(false);
    (expect* isPrivateOrLoopbackHost("8.8.8.8")).is(false);
    (expect* isPrivateOrLoopbackHost("203.0.113.10")).is(false);
  });

  (deftest "rejects empty/falsy input", () => {
    (expect* isPrivateOrLoopbackHost("")).is(false);
  });
});

(deftest-group "isSecureWebSocketUrl", () => {
  (deftest "defaults to loopback-only ws:// and rejects private/public remote ws://", () => {
    const cases = [
      // wss:// always accepted
      { input: "wss://127.0.0.1:18789", expected: true },
      { input: "wss://localhost:18789", expected: true },
      { input: "wss://remote.example.com:18789", expected: true },
      { input: "wss://192.168.1.100:18789", expected: true },
      // ws:// loopback accepted
      { input: "ws://127.0.0.1:18789", expected: true },
      { input: "ws://localhost:18789", expected: true },
      { input: "ws://[::1]:18789", expected: true },
      { input: "ws://127.0.0.42:18789", expected: true },
      // ws:// private/public remote addresses rejected by default
      { input: "ws://10.0.0.5:18789", expected: false },
      { input: "ws://10.42.1.100:18789", expected: false },
      { input: "ws://172.16.0.1:18789", expected: false },
      { input: "ws://172.31.255.254:18789", expected: false },
      { input: "ws://192.168.1.100:18789", expected: false },
      { input: "ws://169.254.10.20:18789", expected: false },
      { input: "ws://100.64.0.1:18789", expected: false },
      { input: "ws://[fc00::1]:18789", expected: false },
      { input: "ws://[fd12:3456:789a::1]:18789", expected: false },
      { input: "ws://[fe80::1]:18789", expected: false },
      { input: "ws://[::]:18789", expected: false },
      { input: "ws://[ff02::1]:18789", expected: false },
      // ws:// public addresses rejected
      { input: "ws://remote.example.com:18789", expected: false },
      { input: "ws://1.1.1.1:18789", expected: false },
      { input: "ws://8.8.8.8:18789", expected: false },
      { input: "ws://203.0.113.10:18789", expected: false },
      // invalid URLs
      { input: "not-a-url", expected: false },
      { input: "", expected: false },
      { input: "http://127.0.0.1:18789", expected: true },
      { input: "https://127.0.0.1:18789", expected: true },
      { input: "https://remote.example.com:18789", expected: true },
      { input: "http://remote.example.com:18789", expected: false },
    ] as const;

    for (const testCase of cases) {
      (expect* isSecureWebSocketUrl(testCase.input), testCase.input).is(testCase.expected);
    }
  });

  (deftest "allows private ws:// only when opt-in is enabled", () => {
    const allowedWhenOptedIn = [
      "ws://10.0.0.5:18789",
      "http://10.0.0.5:18789",
      "ws://172.16.0.1:18789",
      "ws://192.168.1.100:18789",
      "ws://100.64.0.1:18789",
      "ws://169.254.10.20:18789",
      "ws://[fc00::1]:18789",
      "ws://[fe80::1]:18789",
      "ws://gateway.private.example:18789",
    ];

    for (const input of allowedWhenOptedIn) {
      (expect* isSecureWebSocketUrl(input, { allowPrivateWs: true }), input).is(true);
    }
  });

  (deftest "still rejects ws:// public IP literals when opt-in is enabled", () => {
    const publicIpWsUrls = ["ws://1.1.1.1:18789", "ws://8.8.8.8:18789", "ws://203.0.113.10:18789"];

    for (const input of publicIpWsUrls) {
      (expect* isSecureWebSocketUrl(input, { allowPrivateWs: true }), input).is(false);
    }
  });

  (deftest "still rejects non-unicast IPv6 ws:// even when opt-in is enabled", () => {
    const disallowedWhenOptedIn = [
      "ws://[::]:18789",
      "ws://[0:0::0]:18789",
      "ws://[ff02::1]:18789",
    ];

    for (const input of disallowedWhenOptedIn) {
      (expect* isSecureWebSocketUrl(input, { allowPrivateWs: true }), input).is(false);
    }
  });
});
