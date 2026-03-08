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
import { resolveBrowserConfig } from "./config.js";
import {
  allocateCdpPort,
  allocateColor,
  CDP_PORT_RANGE_END,
  CDP_PORT_RANGE_START,
  getUsedColors,
  getUsedPorts,
  isValidProfileName,
  PROFILE_COLORS,
} from "./profiles.js";

(deftest-group "profile name validation", () => {
  it.each(["openclaw", "work", "my-profile", "test123", "a", "a-b-c-1-2-3", "1test"])(
    "accepts valid lowercase name: %s",
    (name) => {
      (expect* isValidProfileName(name)).is(true);
    },
  );

  (deftest "rejects empty or missing names", () => {
    (expect* isValidProfileName("")).is(false);
    // @ts-expect-error testing invalid input
    (expect* isValidProfileName(null)).is(false);
    // @ts-expect-error testing invalid input
    (expect* isValidProfileName(undefined)).is(false);
  });

  (deftest "rejects names that are too long", () => {
    const longName = "a".repeat(65);
    (expect* isValidProfileName(longName)).is(false);

    const maxName = "a".repeat(64);
    (expect* isValidProfileName(maxName)).is(true);
  });

  it.each([
    "MyProfile",
    "PROFILE",
    "Work",
    "my profile",
    "my_profile",
    "my.profile",
    "my/profile",
    "my@profile",
    "-invalid",
    "--double",
  ])("rejects invalid name: %s", (name) => {
    (expect* isValidProfileName(name)).is(false);
  });
});

(deftest-group "port allocation", () => {
  (deftest "allocates within an explicit range", () => {
    const usedPorts = new Set<number>();
    (expect* allocateCdpPort(usedPorts, { start: 20000, end: 20002 })).is(20000);
    usedPorts.add(20000);
    (expect* allocateCdpPort(usedPorts, { start: 20000, end: 20002 })).is(20001);
  });

  (deftest "allocates next available port from default range", () => {
    const cases = [
      { name: "none used", used: new Set<number>(), expected: CDP_PORT_RANGE_START },
      {
        name: "sequentially used start ports",
        used: new Set([CDP_PORT_RANGE_START, CDP_PORT_RANGE_START + 1]),
        expected: CDP_PORT_RANGE_START + 2,
      },
      {
        name: "first gap wins",
        used: new Set([CDP_PORT_RANGE_START, CDP_PORT_RANGE_START + 2]),
        expected: CDP_PORT_RANGE_START + 1,
      },
      {
        name: "ignores outside-range ports",
        used: new Set([1, 2, 3, 50000]),
        expected: CDP_PORT_RANGE_START,
      },
    ] as const;

    for (const testCase of cases) {
      (expect* allocateCdpPort(testCase.used), testCase.name).is(testCase.expected);
    }
  });

  (deftest "returns null when all ports are exhausted", () => {
    const usedPorts = new Set<number>();
    for (let port = CDP_PORT_RANGE_START; port <= CDP_PORT_RANGE_END; port++) {
      usedPorts.add(port);
    }
    (expect* allocateCdpPort(usedPorts)).toBeNull();
  });
});

(deftest-group "getUsedPorts", () => {
  (deftest "returns empty set for undefined profiles", () => {
    (expect* getUsedPorts(undefined)).is-equal(new Set());
  });

  (deftest "extracts ports from profile configs", () => {
    const profiles = {
      openclaw: { cdpPort: 18792 },
      work: { cdpPort: 18793 },
      personal: { cdpPort: 18795 },
    };
    const used = getUsedPorts(profiles);
    (expect* used).is-equal(new Set([18792, 18793, 18795]));
  });

  (deftest "extracts ports from cdpUrl when cdpPort is missing", () => {
    const profiles = {
      remote: { cdpUrl: "http://10.0.0.42:9222" },
      secure: { cdpUrl: "https://example.com:9443" },
    };
    const used = getUsedPorts(profiles);
    (expect* used).is-equal(new Set([9222, 9443]));
  });

  (deftest "ignores invalid cdpUrl values", () => {
    const profiles = {
      bad: { cdpUrl: "notaurl" },
    };
    const used = getUsedPorts(profiles);
    (expect* used.size).is(0);
  });
});

(deftest-group "port collision prevention", () => {
  (deftest "raw config vs resolved config - shows the data source difference", () => {
    // This demonstrates WHY the route handler must use resolved config

    // Fresh config with no profiles defined (like a new install)
    const rawConfigProfiles = undefined;
    const usedFromRaw = getUsedPorts(rawConfigProfiles);

    // Raw config shows empty - no ports used
    (expect* usedFromRaw.size).is(0);

    // But resolved config has implicit openclaw at 18800
    const resolved = resolveBrowserConfig({});
    const usedFromResolved = getUsedPorts(resolved.profiles);
    (expect* usedFromResolved.has(CDP_PORT_RANGE_START)).is(true);
  });

  (deftest "create-profile must use resolved config to avoid port collision", () => {
    // The route handler must use state.resolved.profiles, not raw config

    // Simulate what happens with raw config (empty) vs resolved config
    const rawConfig: { browser: { profiles?: Record<string, { cdpPort?: number }> } } = {
      browser: {},
    }; // Fresh config, no profiles
    const buggyUsedPorts = getUsedPorts(rawConfig.browser?.profiles);
    const buggyAllocatedPort = allocateCdpPort(buggyUsedPorts);

    // Raw config: first allocation gets 18800
    (expect* buggyAllocatedPort).is(CDP_PORT_RANGE_START);

    // Resolved config: includes implicit openclaw at 18800
    const resolved = resolveBrowserConfig(
      rawConfig.browser as Parameters<typeof resolveBrowserConfig>[0],
    );
    const fixedUsedPorts = getUsedPorts(resolved.profiles);
    const fixedAllocatedPort = allocateCdpPort(fixedUsedPorts);

    // Resolved: first NEW profile gets 18801, avoiding collision
    (expect* fixedAllocatedPort).is(CDP_PORT_RANGE_START + 1);
  });
});

(deftest-group "color allocation", () => {
  (deftest "allocates next unused color from palette", () => {
    const cases = [
      { name: "none used", used: new Set<string>(), expected: PROFILE_COLORS[0] },
      {
        name: "first color used",
        used: new Set([PROFILE_COLORS[0].toUpperCase()]),
        expected: PROFILE_COLORS[1],
      },
      {
        name: "multiple used colors",
        used: new Set([
          PROFILE_COLORS[0].toUpperCase(),
          PROFILE_COLORS[1].toUpperCase(),
          PROFILE_COLORS[2].toUpperCase(),
        ]),
        expected: PROFILE_COLORS[3],
      },
    ] as const;
    for (const testCase of cases) {
      (expect* allocateColor(testCase.used), testCase.name).is(testCase.expected);
    }
  });

  (deftest "handles case-insensitive color matching", () => {
    const usedColors = new Set(["#ff4500"]); // lowercase
    // Should still skip this color (case-insensitive)
    // Note: allocateColor compares against uppercase, so lowercase won't match
    // This tests the current behavior
    (expect* allocateColor(usedColors)).is(PROFILE_COLORS[0]); // returns first since lowercase doesn't match
  });

  (deftest "cycles when all colors are used", () => {
    const usedColors = new Set(PROFILE_COLORS.map((c) => c.toUpperCase()));
    // Should cycle based on count
    const result = allocateColor(usedColors);
    (expect* PROFILE_COLORS).contains(result);
  });

  (deftest "cycles based on count when palette exhausted", () => {
    // Add all colors plus some extras
    const usedColors = new Set([
      ...PROFILE_COLORS.map((c) => c.toUpperCase()),
      "#AAAAAA",
      "#BBBBBB",
    ]);
    const result = allocateColor(usedColors);
    // Index should be (10 + 2) % 10 = 2
    (expect* result).is(PROFILE_COLORS[2]);
  });
});

(deftest-group "getUsedColors", () => {
  (deftest "returns empty set when no color profiles are configured", () => {
    (expect* getUsedColors(undefined)).is-equal(new Set());
  });

  (deftest "extracts and uppercases colors from profile configs", () => {
    const profiles = {
      openclaw: { color: "#ff4500" },
      work: { color: "#0066CC" },
    };
    const used = getUsedColors(profiles);
    (expect* used).is-equal(new Set(["#FF4500", "#0066CC"]));
  });
});
