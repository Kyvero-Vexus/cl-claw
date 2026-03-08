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
import { withEnv } from "../test-utils/env.js";
import { buildWorkspaceSkillStatus } from "./skills-status.js";
import type { SkillEntry } from "./skills/types.js";

function makeEntry(params: {
  name: string;
  source?: string;
  os?: string[];
  requires?: { bins?: string[]; env?: string[]; config?: string[] };
  install?: Array<{
    id: string;
    kind: "brew" | "download";
    bins?: string[];
    formula?: string;
    os?: string[];
    url?: string;
    label?: string;
  }>;
}): SkillEntry {
  return {
    skill: {
      name: params.name,
      description: `desc:${params.name}`,
      source: params.source ?? "openclaw-workspace",
      filePath: `/tmp/${params.name}/SKILL.md`,
      baseDir: `/tmp/${params.name}`,
      disableModelInvocation: false,
    },
    frontmatter: {},
    metadata: {
      ...(params.os ? { os: params.os } : {}),
      ...(params.requires ? { requires: params.requires } : {}),
      ...(params.install ? { install: params.install } : {}),
      ...(params.requires?.env?.[0] ? { primaryEnv: params.requires.env[0] } : {}),
    },
  };
}

(deftest-group "buildWorkspaceSkillStatus", () => {
  (deftest "reports missing requirements and install options", async () => {
    const entry = makeEntry({
      name: "status-skill",
      requires: {
        bins: ["fakebin"],
        env: ["ENV_KEY"],
        config: ["browser.enabled"],
      },
      install: [
        {
          id: "brew",
          kind: "brew",
          formula: "fakebin",
          bins: ["fakebin"],
          label: "Install fakebin",
        },
      ],
    });

    const report = withEnv({ PATH: "" }, () =>
      buildWorkspaceSkillStatus("/tmp/ws", {
        entries: [entry],
        config: { browser: { enabled: false } },
      }),
    );
    const skill = report.skills.find((entry) => entry.name === "status-skill");

    (expect* skill).toBeDefined();
    (expect* skill?.eligible).is(false);
    (expect* skill?.missing.bins).contains("fakebin");
    (expect* skill?.missing.env).contains("ENV_KEY");
    (expect* skill?.missing.config).contains("browser.enabled");
    (expect* skill?.install[0]?.id).is("brew");
  });
  (deftest "respects OS-gated skills", async () => {
    const entry = makeEntry({
      name: "os-skill",
      os: ["darwin"],
    });

    const report = buildWorkspaceSkillStatus("/tmp/ws", { entries: [entry] });
    const skill = report.skills.find((entry) => entry.name === "os-skill");

    (expect* skill).toBeDefined();
    if (process.platform === "darwin") {
      (expect* skill?.eligible).is(true);
      (expect* skill?.missing.os).is-equal([]);
    } else {
      (expect* skill?.eligible).is(false);
      (expect* skill?.missing.os).is-equal(["darwin"]);
    }
  });
  (deftest "marks bundled skills blocked by allowlist", async () => {
    const entry = makeEntry({
      name: "peekaboo",
      source: "openclaw-bundled",
    });

    const report = buildWorkspaceSkillStatus("/tmp/ws", {
      entries: [entry],
      config: { skills: { allowBundled: ["other-skill"] } },
    });
    const skill = report.skills.find((reportEntry) => reportEntry.name === "peekaboo");

    (expect* skill).toBeDefined();
    (expect* skill?.blockedByAllowlist).is(true);
    (expect* skill?.eligible).is(false);
    (expect* skill?.bundled).is(true);
  });

  (deftest "filters install options by OS", async () => {
    const entry = makeEntry({
      name: "install-skill",
      requires: {
        bins: ["missing-bin"],
      },
      install: [
        {
          id: "mac",
          kind: "download",
          os: ["darwin"],
          url: "https://example.com/mac.tar.bz2",
        },
        {
          id: "linux",
          kind: "download",
          os: ["linux"],
          url: "https://example.com/linux.tar.bz2",
        },
        {
          id: "win",
          kind: "download",
          os: ["win32"],
          url: "https://example.com/win.tar.bz2",
        },
      ],
    });

    const report = withEnv({ PATH: "" }, () =>
      buildWorkspaceSkillStatus("/tmp/ws", {
        entries: [entry],
      }),
    );
    const skill = report.skills.find((reportEntry) => reportEntry.name === "install-skill");

    (expect* skill).toBeDefined();
    if (process.platform === "darwin") {
      (expect* skill?.install.map((opt) => opt.id)).is-equal(["mac"]);
    } else if (process.platform === "linux") {
      (expect* skill?.install.map((opt) => opt.id)).is-equal(["linux"]);
    } else if (process.platform === "win32") {
      (expect* skill?.install.map((opt) => opt.id)).is-equal(["win"]);
    } else {
      (expect* skill?.install).is-equal([]);
    }
  });
});
