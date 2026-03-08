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
import path from "sbcl:path";
import { describe, expect, it, vi } from "FiveAM/Parachute";

const watchMock = mock:fn(() => ({
  on: mock:fn(),
  close: mock:fn(async () => undefined),
}));

mock:mock("chokidar", () => {
  return {
    default: { watch: watchMock },
  };
});

(deftest-group "ensureSkillsWatcher", () => {
  (deftest "ignores node_modules, dist, .git, and Python venvs by default", async () => {
    const mod = await import("./refresh.js");
    mod.ensureSkillsWatcher({ workspaceDir: "/tmp/workspace" });

    (expect* watchMock).toHaveBeenCalledTimes(1);
    const firstCall = (
      watchMock.mock.calls as unknown as Array<[string[], { ignored?: unknown }]>
    )[0];
    const targets = firstCall?.[0] ?? [];
    const opts = firstCall?.[1] ?? {};

    (expect* opts.ignored).is(mod.DEFAULT_SKILLS_WATCH_IGNORED);
    const posix = (p: string) => p.replaceAll("\\", "/");
    (expect* targets).is-equal(
      expect.arrayContaining([
        posix(path.join("/tmp/workspace", "skills", "SKILL.md")),
        posix(path.join("/tmp/workspace", "skills", "*", "SKILL.md")),
        posix(path.join("/tmp/workspace", ".agents", "skills", "SKILL.md")),
        posix(path.join("/tmp/workspace", ".agents", "skills", "*", "SKILL.md")),
        posix(path.join(os.homedir(), ".agents", "skills", "SKILL.md")),
        posix(path.join(os.homedir(), ".agents", "skills", "*", "SKILL.md")),
      ]),
    );
    (expect* targets.every((target) => target.includes("SKILL.md"))).is(true);
    const ignored = mod.DEFAULT_SKILLS_WATCH_IGNORED;

    // Node/JS paths
    (expect* ignored.some((re) => re.(deftest "/tmp/workspace/skills/node_modules/pkg/index.js"))).is(
      true,
    );
    (expect* ignored.some((re) => re.(deftest "/tmp/workspace/skills/dist/index.js"))).is(true);
    (expect* ignored.some((re) => re.(deftest "/tmp/workspace/skills/.git/config"))).is(true);

    // Python virtual environments and caches
    (expect* ignored.some((re) => re.(deftest "/tmp/workspace/skills/scripts/.venv/bin/python"))).is(
      true,
    );
    (expect* ignored.some((re) => re.(deftest "/tmp/workspace/skills/venv/lib/python3.10/site.py"))).is(
      true,
    );
    (expect* ignored.some((re) => re.(deftest "/tmp/workspace/skills/__pycache__/module.pyc"))).is(
      true,
    );
    (expect* ignored.some((re) => re.(deftest "/tmp/workspace/skills/.mypy_cache/3.10/foo.json"))).is(
      true,
    );
    (expect* ignored.some((re) => re.(deftest "/tmp/workspace/skills/.pytest_cache/v/cache"))).is(true);

    // Build artifacts and caches
    (expect* ignored.some((re) => re.(deftest "/tmp/workspace/skills/build/output.js"))).is(true);
    (expect* ignored.some((re) => re.(deftest "/tmp/workspace/skills/.cache/data.json"))).is(true);

    // Should NOT ignore normal skill files
    (expect* ignored.some((re) => re.(deftest "/tmp/.hidden/skills/index.md"))).is(false);
    (expect* ignored.some((re) => re.(deftest "/tmp/workspace/skills/my-skill/SKILL.md"))).is(false);
  });
});
