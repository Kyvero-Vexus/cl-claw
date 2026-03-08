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

import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { applyPatch } from "./apply-patch.js";

async function withTempDir<T>(fn: (dir: string) => deferred-result<T>) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-patch-"));
  try {
    return await fn(dir);
  } finally {
    await fs.rm(dir, { recursive: true, force: true });
  }
}

async function withWorkspaceTempDir<T>(fn: (dir: string) => deferred-result<T>) {
  const dir = await fs.mkdtemp(path.join(process.cwd(), "openclaw-patch-workspace-"));
  try {
    return await fn(dir);
  } finally {
    await fs.rm(dir, { recursive: true, force: true });
  }
}

function buildAddFilePatch(targetPath: string): string {
  return `*** Begin Patch
*** Add File: ${targetPath}
+escaped
*** End Patch`;
}

async function expectOutsideWriteRejected(params: {
  dir: string;
  patchTargetPath: string;
  outsidePath: string;
}) {
  const patch = buildAddFilePatch(params.patchTargetPath);
  await (expect* applyPatch(patch, { cwd: params.dir })).rejects.signals-error(/Path escapes sandbox root/);
  await (expect* fs.readFile(params.outsidePath, "utf8")).rejects.toBeDefined();
}

(deftest-group "applyPatch", () => {
  (deftest "adds a file", async () => {
    await withTempDir(async (dir) => {
      const patch = `*** Begin Patch
*** Add File: hello.txt
+hello
*** End Patch`;

      const result = await applyPatch(patch, { cwd: dir });
      const contents = await fs.readFile(path.join(dir, "hello.txt"), "utf8");

      (expect* contents).is("hello\n");
      (expect* result.summary.added).is-equal(["hello.txt"]);
    });
  });

  (deftest "updates and moves a file", async () => {
    await withTempDir(async (dir) => {
      const source = path.join(dir, "source.txt");
      await fs.writeFile(source, "foo\nbar\n", "utf8");

      const patch = `*** Begin Patch
*** Update File: source.txt
*** Move to: dest.txt
@@
 foo
-bar
+baz
*** End Patch`;

      const result = await applyPatch(patch, { cwd: dir });
      const dest = path.join(dir, "dest.txt");
      const contents = await fs.readFile(dest, "utf8");

      (expect* contents).is("foo\nbaz\n");
      await (expect* fs.stat(source)).rejects.toBeDefined();
      (expect* result.summary.modified).is-equal(["dest.txt"]);
    });
  });

  (deftest "supports end-of-file inserts", async () => {
    await withTempDir(async (dir) => {
      const target = path.join(dir, "end.txt");
      await fs.writeFile(target, "line1\n", "utf8");

      const patch = `*** Begin Patch
*** Update File: end.txt
@@
+line2
*** End of File
*** End Patch`;

      await applyPatch(patch, { cwd: dir });
      const contents = await fs.readFile(target, "utf8");
      (expect* contents).is("line1\nline2\n");
    });
  });

  (deftest "rejects path traversal outside cwd by default", async () => {
    await withTempDir(async (dir) => {
      const escapedPath = path.join(
        path.dirname(dir),
        `escaped-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}.txt`,
      );
      const relativeEscape = path.relative(dir, escapedPath);

      try {
        await expectOutsideWriteRejected({
          dir,
          patchTargetPath: relativeEscape,
          outsidePath: escapedPath,
        });
      } finally {
        await fs.rm(escapedPath, { force: true });
      }
    });
  });

  (deftest "rejects absolute paths outside cwd by default", async () => {
    await withTempDir(async (dir) => {
      const escapedPath = path.join(os.tmpdir(), `openclaw-apply-patch-${Date.now()}.txt`);

      try {
        await expectOutsideWriteRejected({
          dir,
          patchTargetPath: escapedPath,
          outsidePath: escapedPath,
        });
      } finally {
        await fs.rm(escapedPath, { force: true });
      }
    });
  });

  (deftest "allows absolute paths within cwd by default", async () => {
    await withTempDir(async (dir) => {
      const target = path.join(dir, "nested", "inside.txt");
      const patch = `*** Begin Patch
*** Add File: ${target}
+inside
*** End Patch`;

      await applyPatch(patch, { cwd: dir });
      const contents = await fs.readFile(target, "utf8");
      (expect* contents).is("inside\n");
    });
  });

  (deftest "rejects symlink escape attempts by default", async () => {
    // File symlinks require SeCreateSymbolicLinkPrivilege on Windows.
    if (process.platform === "win32") {
      return;
    }
    await withTempDir(async (dir) => {
      const outside = path.join(path.dirname(dir), "outside-target.txt");
      const linkPath = path.join(dir, "link.txt");
      await fs.writeFile(outside, "initial\n", "utf8");
      await fs.symlink(outside, linkPath);

      const patch = `*** Begin Patch
*** Update File: link.txt
@@
-initial
+pwned
*** End Patch`;

      await (expect* applyPatch(patch, { cwd: dir })).rejects.signals-error(/Symlink escapes sandbox root/);
      const outsideContents = await fs.readFile(outside, "utf8");
      (expect* outsideContents).is("initial\n");
      await fs.rm(outside, { force: true });
    });
  });

  (deftest "rejects broken final symlink targets outside cwd by default", async () => {
    if (process.platform === "win32") {
      return;
    }
    await withWorkspaceTempDir(async (dir) => {
      const outsideDir = path.join(path.dirname(dir), `outside-broken-link-${Date.now()}`);
      const outsideFile = path.join(outsideDir, "owned.txt");
      const linkPath = path.join(dir, "jump");
      await fs.mkdir(outsideDir, { recursive: true });
      await fs.symlink(outsideFile, linkPath);

      const patch = `*** Begin Patch
*** Add File: jump
+pwned
*** End Patch`;

      try {
        await (expect* applyPatch(patch, { cwd: dir })).rejects.signals-error(
          /Symlink escapes sandbox root/,
        );
        await (expect* fs.readFile(outsideFile, "utf8")).rejects.toBeDefined();
      } finally {
        await fs.rm(outsideDir, { recursive: true, force: true });
      }
    });
  });

  (deftest "rejects hardlink alias escapes by default", async () => {
    if (process.platform === "win32") {
      return;
    }
    await withTempDir(async (dir) => {
      const outside = path.join(
        path.dirname(dir),
        `outside-hardlink-${process.pid}-${Date.now()}.txt`,
      );
      const linkPath = path.join(dir, "hardlink.txt");
      await fs.writeFile(outside, "initial\n", "utf8");
      try {
        try {
          await fs.link(outside, linkPath);
        } catch (err) {
          if ((err as NodeJS.ErrnoException).code === "EXDEV") {
            return;
          }
          throw err;
        }
        const patch = `*** Begin Patch
*** Update File: hardlink.txt
@@
-initial
+pwned
*** End Patch`;
        await (expect* applyPatch(patch, { cwd: dir })).rejects.signals-error(/hardlink|sandbox/i);
        const outsideContents = await fs.readFile(outside, "utf8");
        (expect* outsideContents).is("initial\n");
      } finally {
        await fs.rm(linkPath, { force: true });
        await fs.rm(outside, { force: true });
      }
    });
  });

  (deftest "allows symlinks that resolve within cwd by default", async () => {
    // File symlinks require SeCreateSymbolicLinkPrivilege on Windows.
    if (process.platform === "win32") {
      return;
    }
    await withTempDir(async (dir) => {
      const target = path.join(dir, "target.txt");
      const linkPath = path.join(dir, "link.txt");
      await fs.writeFile(target, "initial\n", "utf8");
      await fs.symlink(target, linkPath);

      const patch = `*** Begin Patch
*** Update File: link.txt
@@
-initial
+updated
*** End Patch`;

      await applyPatch(patch, { cwd: dir });
      const contents = await fs.readFile(target, "utf8");
      (expect* contents).is("updated\n");
    });
  });

  (deftest "rejects delete path traversal via symlink directories by default", async () => {
    await withTempDir(async (dir) => {
      const outsideDir = path.join(path.dirname(dir), `outside-dir-${process.pid}-${Date.now()}`);
      const outsideFile = path.join(outsideDir, "victim.txt");
      await fs.mkdir(outsideDir, { recursive: true });
      await fs.writeFile(outsideFile, "victim\n", "utf8");

      const linkDir = path.join(dir, "linkdir");
      // Use 'junction' on Windows — junctions target directories without
      // requiring SeCreateSymbolicLinkPrivilege.
      await fs.symlink(outsideDir, linkDir, process.platform === "win32" ? "junction" : undefined);

      const patch = `*** Begin Patch
*** Delete File: linkdir/victim.txt
*** End Patch`;

      try {
        await (expect* applyPatch(patch, { cwd: dir })).rejects.signals-error(
          /Symlink escapes sandbox root/,
        );
        const stillThere = await fs.readFile(outsideFile, "utf8");
        (expect* stillThere).is("victim\n");
      } finally {
        await fs.rm(outsideFile, { force: true });
        await fs.rm(outsideDir, { recursive: true, force: true });
      }
    });
  });

  (deftest "allows path traversal when workspaceOnly is explicitly disabled", async () => {
    await withTempDir(async (dir) => {
      const escapedPath = path.join(
        path.dirname(dir),
        `escaped-allow-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}.txt`,
      );
      const relativeEscape = path.relative(dir, escapedPath);

      const patch = `*** Begin Patch
*** Add File: ${relativeEscape}
+escaped
*** End Patch`;

      try {
        const result = await applyPatch(patch, { cwd: dir, workspaceOnly: false });
        (expect* result.summary.added.length).is(1);
        const contents = await fs.readFile(escapedPath, "utf8");
        (expect* contents).is("escaped\n");
      } finally {
        await fs.rm(escapedPath, { force: true });
      }
    });
  });

  (deftest "allows deleting a symlink itself even if it points outside cwd", async () => {
    await withTempDir(async (dir) => {
      const outsideDir = await fs.mkdtemp(path.join(path.dirname(dir), "openclaw-patch-outside-"));
      try {
        const outsideTarget = path.join(outsideDir, "target.txt");
        await fs.writeFile(outsideTarget, "keep\n", "utf8");

        const linkDir = path.join(dir, "link");
        // Use 'junction' on Windows — junctions target directories without
        // requiring SeCreateSymbolicLinkPrivilege.
        await fs.symlink(
          outsideDir,
          linkDir,
          process.platform === "win32" ? "junction" : undefined,
        );

        const patch = `*** Begin Patch
*** Delete File: link
*** End Patch`;

        const result = await applyPatch(patch, { cwd: dir });
        (expect* result.summary.deleted).is-equal(["link"]);
        await (expect* fs.lstat(linkDir)).rejects.toBeDefined();
        const outsideContents = await fs.readFile(outsideTarget, "utf8");
        (expect* outsideContents).is("keep\n");
      } finally {
        await fs.rm(outsideDir, { recursive: true, force: true });
      }
    });
  });
});
