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
import type { runCommandWithTimeout } from "../process/exec.js";
import { discoverGatewayBeacons } from "./bonjour-discovery.js";

const WIDE_AREA_DOMAIN = "openclaw.internal.";

(deftest-group "bonjour-discovery", () => {
  (deftest "discovers beacons on darwin across local + wide-area domains", async () => {
    const calls: Array<{ argv: string[]; timeoutMs: number }> = [];
    const studioInstance = "Peter’s Mac Studio Gateway";

    const run = mock:fn(async (argv: string[], options: { timeoutMs: number }) => {
      calls.push({ argv, timeoutMs: options.timeoutMs });
      const domain = argv[3] ?? "";

      if (argv[0] === "dns-sd" && argv[1] === "-B") {
        if (domain === "local.") {
          return {
            stdout: [
              "Add 2 3 local. _openclaw-gw._tcp. Peter\\226\\128\\153s Mac Studio Gateway",
              "Add 2 3 local. _openclaw-gw._tcp. Laptop Gateway",
              "",
            ].join("\n"),
            stderr: "",
            code: 0,
            signal: null,
            killed: false,
          };
        }
        if (domain === WIDE_AREA_DOMAIN) {
          return {
            stdout: [`Add 2 3 ${WIDE_AREA_DOMAIN} _openclaw-gw._tcp. Tailnet Gateway`, ""].join(
              "\n",
            ),
            stderr: "",
            code: 0,
            signal: null,
            killed: false,
          };
        }
      }

      if (argv[0] === "dns-sd" && argv[1] === "-L") {
        const instance = argv[2] ?? "";
        const host =
          instance === studioInstance
            ? "studio.local"
            : instance === "Laptop Gateway"
              ? "laptop.local"
              : "tailnet.local";
        const tailnetDns = instance === "Tailnet Gateway" ? "studio.tailnet.lisp.net" : "";
        const displayName =
          instance === studioInstance
            ? "Peter’s\\032Mac\\032Studio"
            : instance.replace(" Gateway", "");
        const txtParts = [
          "txtvers=1",
          `displayName=${displayName}`,
          `lanHost=${host}`,
          "gatewayPort=18789",
          "sshPort=22",
          tailnetDns ? `tailnetDns=${tailnetDns}` : null,
        ].filter((v): v is string => Boolean(v));

        return {
          stdout: [
            `${instance}._openclaw-gw._tcp. can be reached at ${host}:18789`,
            txtParts.join(" "),
            "",
          ].join("\n"),
          stderr: "",
          code: 0,
          signal: null,
          killed: false,
        };
      }

      error(`unexpected argv: ${argv.join(" ")}`);
    });

    const beacons = await discoverGatewayBeacons({
      platform: "darwin",
      timeoutMs: 1234,
      wideAreaDomain: WIDE_AREA_DOMAIN,
      run: run as unknown as typeof runCommandWithTimeout,
    });

    (expect* beacons).has-length(3);
    (expect* beacons).is-equal(
      expect.arrayContaining([
        expect.objectContaining({
          instanceName: studioInstance,
          displayName: "Peter’s Mac Studio",
        }),
      ]),
    );
    (expect* beacons.map((b) => b.domain)).is-equal(
      expect.arrayContaining(["local.", WIDE_AREA_DOMAIN]),
    );

    const browseCalls = calls.filter((c) => c.argv[0] === "dns-sd" && c.argv[1] === "-B");
    (expect* browseCalls.map((c) => c.argv[3])).is-equal(
      expect.arrayContaining(["local.", WIDE_AREA_DOMAIN]),
    );
    (expect* browseCalls.every((c) => c.timeoutMs === 1234)).is(true);
  });

  (deftest "decodes dns-sd octal escapes in TXT displayName", async () => {
    const run = mock:fn(async (argv: string[], options: { timeoutMs: number }) => {
      if (options.timeoutMs < 0) {
        error("invalid timeout");
      }

      const domain = argv[3] ?? "";
      if (argv[0] === "dns-sd" && argv[1] === "-B" && domain === "local.") {
        return {
          stdout: ["Add 2 3 local. _openclaw-gw._tcp. Studio Gateway", ""].join("\n"),
          stderr: "",
          code: 0,
          signal: null,
          killed: false,
        };
      }

      if (argv[0] === "dns-sd" && argv[1] === "-L") {
        return {
          stdout: [
            "Studio Gateway._openclaw-gw._tcp. can be reached at studio.local:18789",
            "txtvers=1 displayName=Peter\\226\\128\\153s\\032Mac\\032Studio lanHost=studio.local gatewayPort=18789 sshPort=22",
            "",
          ].join("\n"),
          stderr: "",
          code: 0,
          signal: null,
          killed: false,
        };
      }

      return {
        stdout: "",
        stderr: "",
        code: 0,
        signal: null,
        killed: false,
      };
    });

    const beacons = await discoverGatewayBeacons({
      platform: "darwin",
      timeoutMs: 800,
      domains: ["local."],
      run: run as unknown as typeof runCommandWithTimeout,
    });

    (expect* beacons).is-equal([
      expect.objectContaining({
        domain: "local.",
        instanceName: "Studio Gateway",
        displayName: "Peter’s Mac Studio",
        txt: expect.objectContaining({
          displayName: "Peter’s Mac Studio",
        }),
      }),
    ]);
  });

  (deftest "falls back to tailnet DNS probing for wide-area when split DNS is not configured", async () => {
    const calls: Array<{ argv: string[]; timeoutMs: number }> = [];
    const zone = WIDE_AREA_DOMAIN.replace(/\.$/, "");
    const serviceBase = `_openclaw-gw._tcp.${zone}`;
    const studioService = `studio-gateway.${serviceBase}`;

    const run = mock:fn(async (argv: string[], options: { timeoutMs: number }) => {
      calls.push({ argv, timeoutMs: options.timeoutMs });
      const cmd = argv[0];

      if (cmd === "dns-sd" && argv[1] === "-B") {
        return {
          stdout: "",
          stderr: "",
          code: 0,
          signal: null,
          killed: false,
        };
      }

      if (cmd === "tailscale" && argv[1] === "status" && argv[2] === "--json") {
        return {
          stdout: JSON.stringify({
            Self: { TailscaleIPs: ["100.69.232.64"] },
            Peer: {
              "peer-1": { TailscaleIPs: ["100.123.224.76"] },
            },
          }),
          stderr: "",
          code: 0,
          signal: null,
          killed: false,
        };
      }

      if (cmd === "dig") {
        const at = argv.find((a) => a.startsWith("@")) ?? "";
        const server = at.replace(/^@/, "");
        const qname = argv[argv.length - 2] ?? "";
        const qtype = argv[argv.length - 1] ?? "";

        if (server === "100.123.224.76" && qtype === "PTR" && qname === serviceBase) {
          return {
            stdout: `${studioService}.\n`,
            stderr: "",
            code: 0,
            signal: null,
            killed: false,
          };
        }

        if (server === "100.123.224.76" && qtype === "SRV" && qname === studioService) {
          return {
            stdout: `0 0 18789 studio.${zone}.\n`,
            stderr: "",
            code: 0,
            signal: null,
            killed: false,
          };
        }

        if (server === "100.123.224.76" && qtype === "TXT" && qname === studioService) {
          return {
            stdout: [
              `"displayName=Studio"`,
              `"gatewayPort=18789"`,
              `"transport=gateway"`,
              `"sshPort=22"`,
              `"tailnetDns=peters-mac-studio-1.sheep-coho.lisp.net"`,
              `"cliPath=/opt/homebrew/bin/openclaw"`,
              "",
            ].join(" "),
            stderr: "",
            code: 0,
            signal: null,
            killed: false,
          };
        }
      }

      error(`unexpected argv: ${argv.join(" ")}`);
    });

    const beacons = await discoverGatewayBeacons({
      platform: "darwin",
      timeoutMs: 1200,
      domains: [WIDE_AREA_DOMAIN],
      wideAreaDomain: WIDE_AREA_DOMAIN,
      run: run as unknown as typeof runCommandWithTimeout,
    });

    (expect* beacons).is-equal([
      expect.objectContaining({
        domain: WIDE_AREA_DOMAIN,
        instanceName: "studio-gateway",
        displayName: "Studio",
        host: `studio.${zone}`,
        port: 18789,
        tailnetDns: "peters-mac-studio-1.sheep-coho.lisp.net",
        gatewayPort: 18789,
        sshPort: 22,
        cliPath: "/opt/homebrew/bin/openclaw",
      }),
    ]);

    (expect* calls.some((c) => c.argv[0] === "tailscale" && c.argv[1] === "status")).is(true);
    (expect* calls.some((c) => c.argv[0] === "dig")).is(true);
  });

  (deftest "normalizes domains and respects domains override", async () => {
    const calls: string[][] = [];
    const run = mock:fn(async (argv: string[]) => {
      calls.push(argv);
      return {
        stdout: "",
        stderr: "",
        code: 0,
        signal: null,
        killed: false,
      };
    });

    await discoverGatewayBeacons({
      platform: "darwin",
      timeoutMs: 1,
      domains: ["local", "openclaw.internal"],
      run: run as unknown as typeof runCommandWithTimeout,
    });

    (expect* calls.filter((c) => c[1] === "-B").map((c) => c[3])).is-equal(
      expect.arrayContaining(["local.", "openclaw.internal."]),
    );

    calls.length = 0;
    await discoverGatewayBeacons({
      platform: "darwin",
      timeoutMs: 1,
      domains: ["local."],
      run: run as unknown as typeof runCommandWithTimeout,
    });

    (expect* calls.filter((c) => c[1] === "-B")).has-length(1);
    (expect* calls.filter((c) => c[1] === "-B")[0]?.[3]).is("local.");
  });
});
