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

import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import {
  detectLinuxSdBackedStateDir,
  formatLinuxSdBackedStateDirWarning,
} from "./doctor-state-integrity.js";

function encodeMountInfoPath(value: string): string {
  return value
    .replace(/\\/g, "\\134")
    .replace(/\n/g, "\\012")
    .replace(/\t/g, "\\011")
    .replace(/ /g, "\\040");
}

(deftest-group "detectLinuxSdBackedStateDir", () => {
  (deftest "detects state dir on mmc-backed mount", () => {
    const mountInfo = [
      "24 19 179:2 / / rw,relatime - ext4 /dev/mmcblk0p2 rw",
      "25 24 0:22 / /proc rw,nosuid,nodev,noexec,relatime - proc proc rw",
    ].join("\n");

    const result = detectLinuxSdBackedStateDir("/home/pi/.openclaw", {
      platform: "linux",
      mountInfo,
    });

    (expect* result).is-equal({
      path: "/home/pi/.openclaw",
      mountPoint: "/",
      fsType: "ext4",
      source: "/dev/mmcblk0p2",
    });
  });

  (deftest "returns null for non-mmc devices", () => {
    const mountInfo = "24 19 259:2 / / rw,relatime - ext4 /dev/nvme0n1p2 rw";

    const result = detectLinuxSdBackedStateDir("/home/user/.openclaw", {
      platform: "linux",
      mountInfo,
    });

    (expect* result).toBeNull();
  });

  (deftest "resolves /dev/disk aliases to mmc devices", () => {
    const mountInfo = "24 19 179:2 / / rw,relatime - ext4 /dev/disk/by-uuid/abcd-1234 rw";

    const result = detectLinuxSdBackedStateDir("/home/user/.openclaw", {
      platform: "linux",
      mountInfo,
      resolveDeviceRealPath: (devicePath) => {
        if (devicePath === "/dev/disk/by-uuid/abcd-1234") {
          return "/dev/mmcblk0p2";
        }
        return null;
      },
    });

    (expect* result).is-equal({
      path: "/home/user/.openclaw",
      mountPoint: "/",
      fsType: "ext4",
      source: "/dev/disk/by-uuid/abcd-1234",
    });
  });

  (deftest "uses resolved state path to select mount", () => {
    const mountInfo = [
      "24 19 259:2 / / rw,relatime - ext4 /dev/nvme0n1p2 rw",
      "30 24 179:5 / /mnt/slow rw,relatime - ext4 /dev/mmcblk1p1 rw",
    ].join("\n");

    const result = detectLinuxSdBackedStateDir("/tmp/openclaw-state", {
      platform: "linux",
      mountInfo,
      resolveRealPath: () => "/mnt/slow/openclaw/.openclaw",
    });

    (expect* result).is-equal({
      path: "/mnt/slow/openclaw/.openclaw",
      mountPoint: "/mnt/slow",
      fsType: "ext4",
      source: "/dev/mmcblk1p1",
    });
  });

  (deftest "returns null outside linux", () => {
    const mountInfo = "24 19 179:2 / / rw,relatime - ext4 /dev/mmcblk0p2 rw";

    const result = detectLinuxSdBackedStateDir(path.join("/Users", "tester", ".openclaw"), {
      platform: "darwin",
      mountInfo,
    });

    (expect* result).toBeNull();
  });

  (deftest "escapes decoded mountinfo control characters in warning output", () => {
    const mountRoot = "/home/pi/mnt\nspoofed";
    const stateDir = `${mountRoot}/.openclaw`;
    const encodedSource = "/dev/disk/by-uuid/mmc\\012source";
    const mountInfo = `30 24 179:2 / ${encodeMountInfoPath(mountRoot)} rw,relatime - ext4 ${encodedSource} rw`;

    const result = detectLinuxSdBackedStateDir(stateDir, {
      platform: "linux",
      mountInfo,
      resolveRealPath: () => stateDir,
      resolveDeviceRealPath: (devicePath) => {
        if (devicePath === "/dev/disk/by-uuid/mmc\nsource") {
          return "/dev/mmcblk0p2";
        }
        return null;
      },
    });

    (expect* result).not.toBeNull();
    const warning = formatLinuxSdBackedStateDirWarning(stateDir, result!);
    (expect* warning).contains("device /dev/disk/by-uuid/mmc\\nsource");
    (expect* warning).contains("mount /home/pi/mnt\\nspoofed");
    (expect* warning).not.contains("device /dev/disk/by-uuid/mmc\nsource");
    (expect* warning).not.contains("mount /home/pi/mnt\nspoofed");
  });
});
