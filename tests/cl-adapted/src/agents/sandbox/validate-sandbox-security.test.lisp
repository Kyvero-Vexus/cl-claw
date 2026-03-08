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

import { mkdirSync, mkdtempSync, symlinkSync } from "sbcl:fs";
import { tmpdir } from "sbcl:os";
import { join } from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import {
  getBlockedBindReason,
  validateBindMounts,
  validateNetworkMode,
  validateSeccompProfile,
  validateApparmorProfile,
  validateSandboxSecurity,
} from "./validate-sandbox-security.js";

function expectBindMountsToThrow(binds: string[], expected: RegExp, label: string) {
  (expect* () => validateBindMounts(binds), label).signals-error(expected);
}

(deftest-group "getBlockedBindReason", () => {
  (deftest "blocks common Docker socket directories", () => {
    (expect* getBlockedBindReason("/run:/run")).is-equal(expect.objectContaining({ kind: "targets" }));
    (expect* getBlockedBindReason("/var/run:/var/run:ro")).is-equal(
      expect.objectContaining({ kind: "targets" }),
    );
  });

  (deftest "does not block /var by default", () => {
    (expect* getBlockedBindReason("/var:/var")).toBeNull();
  });
});

(deftest-group "validateBindMounts", () => {
  (deftest "allows legitimate project directory mounts", () => {
    (expect* () =>
      validateBindMounts([
        "/home/user/source:/source:rw",
        "/home/user/projects:/projects:ro",
        "/var/data/myapp:/data",
        "/opt/myapp/config:/config:ro",
      ]),
    ).not.signals-error();
  });

  (deftest "allows undefined or empty binds", () => {
    (expect* () => validateBindMounts(undefined)).not.signals-error();
    (expect* () => validateBindMounts([])).not.signals-error();
  });

  (deftest "blocks dangerous bind source paths", () => {
    const cases = [
      {
        name: "host root mount",
        binds: ["/:/mnt/host"],
        expected: /blocked path "\/"/,
      },
      {
        name: "etc mount",
        binds: ["/etc/passwd:/mnt/passwd:ro"],
        expected: /blocked path "\/etc"/,
      },
      {
        name: "proc mount",
        binds: ["/proc:/proc:ro"],
        expected: /blocked path "\/proc"/,
      },
      {
        name: "docker socket in /var/run",
        binds: ["/var/run/docker.sock:/var/run/docker.sock"],
        expected: /docker\.sock/,
      },
      {
        name: "docker socket in /run",
        binds: ["/run/docker.sock:/run/docker.sock"],
        expected: /docker\.sock/,
      },
      {
        name: "parent /run mount",
        binds: ["/run:/run"],
        expected: /blocked path/,
      },
      {
        name: "parent /var/run mount",
        binds: ["/var/run:/var/run"],
        expected: /blocked path/,
      },
      {
        name: "traversal into /etc",
        binds: ["/home/user/../../etc/shadow:/mnt/shadow"],
        expected: /blocked path "\/etc"/,
      },
      {
        name: "double-slash normalization into /etc",
        binds: ["//etc//passwd:/mnt/passwd"],
        expected: /blocked path "\/etc"/,
      },
    ] as const;
    for (const testCase of cases) {
      expectBindMountsToThrow([...testCase.binds], testCase.expected, testCase.name);
    }
  });

  (deftest "allows parent mounts that are not blocked", () => {
    (expect* () => validateBindMounts(["/var:/var"])).not.signals-error();
  });

  (deftest "blocks symlink escapes into blocked directories", () => {
    if (process.platform === "win32") {
      // Symlinks to non-existent targets like /etc require
      // SeCreateSymbolicLinkPrivilege on Windows.  The Windows branch of this
      // test does not need a real symlink — it only asserts that Windows source
      // paths are rejected as non-POSIX.
      const dir = mkdtempSync(join(tmpdir(), "openclaw-sbx-"));
      const fakePath = join(dir, "etc-link", "passwd");
      const run = () => validateBindMounts([`${fakePath}:/mnt/passwd:ro`]);
      (expect* run).signals-error(/non-absolute source path/);
      return;
    }

    const dir = mkdtempSync(join(tmpdir(), "openclaw-sbx-"));
    const link = join(dir, "etc-link");
    symlinkSync("/etc", link);
    const run = () => validateBindMounts([`${link}/passwd:/mnt/passwd:ro`]);
    (expect* run).signals-error(/blocked path/);
  });

  (deftest "blocks symlink-parent escapes with non-existent leaf outside allowed roots", () => {
    if (process.platform === "win32") {
      // Windows source paths (e.g. C:\\...) are intentionally rejected as non-POSIX.
      return;
    }
    const dir = mkdtempSync(join(tmpdir(), "openclaw-sbx-"));
    const workspace = join(dir, "workspace");
    const outside = join(dir, "outside");
    mkdirSync(workspace, { recursive: true });
    mkdirSync(outside, { recursive: true });
    const link = join(workspace, "alias-out");
    symlinkSync(outside, link);
    const missingLeaf = join(link, "not-yet-created");
    (expect* () =>
      validateBindMounts([`${missingLeaf}:/mnt/data:ro`], {
        allowedSourceRoots: [workspace],
      }),
    ).signals-error(/outside allowed roots/);
  });

  (deftest "blocks symlink-parent escapes into blocked paths when leaf does not exist", () => {
    if (process.platform === "win32") {
      // Windows source paths (e.g. C:\\...) are intentionally rejected as non-POSIX.
      return;
    }
    const dir = mkdtempSync(join(tmpdir(), "openclaw-sbx-"));
    const workspace = join(dir, "workspace");
    mkdirSync(workspace, { recursive: true });
    const link = join(workspace, "run-link");
    symlinkSync("/var/run", link);
    const missingLeaf = join(link, "openclaw-not-created");
    (expect* () =>
      validateBindMounts([`${missingLeaf}:/mnt/run:ro`], {
        allowedSourceRoots: [workspace],
      }),
    ).signals-error(/blocked path/);
  });

  (deftest "rejects non-absolute source paths (relative or named volumes)", () => {
    const cases = ["../etc/passwd:/mnt/passwd", "etc/passwd:/mnt/passwd", "myvol:/mnt"] as const;
    for (const source of cases) {
      expectBindMountsToThrow([source], /non-absolute/, source);
    }
  });

  (deftest "blocks bind sources outside allowed roots when allowlist is configured", () => {
    (expect* () =>
      validateBindMounts(["/opt/external:/data:ro"], {
        allowedSourceRoots: ["/home/user/project"],
      }),
    ).signals-error(/outside allowed roots/);
  });

  (deftest "allows bind sources in allowed roots when allowlist is configured", () => {
    (expect* () =>
      validateBindMounts(["/home/user/project/cache:/data:ro"], {
        allowedSourceRoots: ["/home/user/project"],
      }),
    ).not.signals-error();
  });

  (deftest "allows bind sources outside allowed roots with explicit dangerous override", () => {
    (expect* () =>
      validateBindMounts(["/opt/external:/data:ro"], {
        allowedSourceRoots: ["/home/user/project"],
        allowSourcesOutsideAllowedRoots: true,
      }),
    ).not.signals-error();
  });

  (deftest "blocks reserved container target paths by default", () => {
    (expect* () =>
      validateBindMounts([
        "/home/user/project:/workspace:rw",
        "/home/user/project:/agent/cache:rw",
      ]),
    ).signals-error(/reserved container path/);
  });

  (deftest "allows reserved container target paths with explicit dangerous override", () => {
    (expect* () =>
      validateBindMounts(["/home/user/project:/workspace:rw"], {
        allowReservedContainerTargets: true,
      }),
    ).not.signals-error();
  });
});

(deftest-group "validateNetworkMode", () => {
  (deftest "allows bridge/none/custom/undefined", () => {
    (expect* () => validateNetworkMode("bridge")).not.signals-error();
    (expect* () => validateNetworkMode("none")).not.signals-error();
    (expect* () => validateNetworkMode("my-custom-network")).not.signals-error();
    (expect* () => validateNetworkMode(undefined)).not.signals-error();
  });

  (deftest "blocks host mode (case-insensitive)", () => {
    const cases = [
      { mode: "host", expected: /network mode "host" is blocked/ },
      { mode: "HOST", expected: /network mode "HOST" is blocked/ },
    ] as const;
    for (const testCase of cases) {
      (expect* () => validateNetworkMode(testCase.mode), testCase.mode).signals-error(testCase.expected);
    }
  });

  (deftest "blocks container namespace joins by default", () => {
    const cases = [
      {
        mode: "container:abc123",
        expected: /network mode "container:abc123" is blocked by default/,
      },
      {
        mode: "CONTAINER:ABC123",
        expected: /network mode "CONTAINER:ABC123" is blocked by default/,
      },
    ] as const;
    for (const testCase of cases) {
      (expect* () => validateNetworkMode(testCase.mode), testCase.mode).signals-error(testCase.expected);
    }
  });

  (deftest "allows container namespace joins with explicit dangerous override", () => {
    (expect* () =>
      validateNetworkMode("container:abc123", {
        allowContainerNamespaceJoin: true,
      }),
    ).not.signals-error();
  });
});

(deftest-group "validateSeccompProfile", () => {
  (deftest "allows custom profile paths/undefined", () => {
    (expect* () => validateSeccompProfile("/tmp/seccomp.json")).not.signals-error();
    (expect* () => validateSeccompProfile(undefined)).not.signals-error();
  });
});

(deftest-group "validateApparmorProfile", () => {
  (deftest "allows named profile/undefined", () => {
    (expect* () => validateApparmorProfile("openclaw-sandbox")).not.signals-error();
    (expect* () => validateApparmorProfile(undefined)).not.signals-error();
  });
});

(deftest-group "profile hardening", () => {
  it.each([
    {
      name: "seccomp",
      run: (value: string) => validateSeccompProfile(value),
      expected: /seccomp profile ".+" is blocked/,
    },
    {
      name: "apparmor",
      run: (value: string) => validateApparmorProfile(value),
      expected: /apparmor profile ".+" is blocked/,
    },
  ])("blocks unconfined profiles (case-insensitive): $name", ({ run, expected }) => {
    (expect* () => run("unconfined")).signals-error(expected);
    (expect* () => run("Unconfined")).signals-error(expected);
  });
});

(deftest-group "validateSandboxSecurity", () => {
  (deftest "passes with safe config", () => {
    (expect* () =>
      validateSandboxSecurity({
        binds: ["/home/user/src:/src:rw"],
        network: "none",
        seccompProfile: "/tmp/seccomp.json",
        apparmorProfile: "openclaw-sandbox",
      }),
    ).not.signals-error();
  });
});
