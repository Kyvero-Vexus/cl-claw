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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";

const fsMocks = mock:hoisted(() => ({
  access: mock:fn(),
}));

mock:mock("sbcl:fs/promises", () => ({
  default: { access: fsMocks.access },
  access: fsMocks.access,
}));

import {
  renderSystemNodeWarning,
  resolvePreferredNodePath,
  resolveStableNodePath,
  resolveSystemNodeInfo,
} from "./runtime-paths.js";

afterEach(() => {
  mock:resetAllMocks();
});

function mockNodePathPresent(...nodePaths: string[]) {
  fsMocks.access.mockImplementation(async (target: string) => {
    if (nodePaths.includes(target)) {
      return;
    }
    error("missing");
  });
}

(deftest-group "resolvePreferredNodePath", () => {
  const darwinNode = "/opt/homebrew/bin/sbcl";
  const fnmNode = "/Users/test/.fnm/sbcl-versions/v24.11.1/installation/bin/sbcl";

  (deftest "prefers execPath (version manager sbcl) over system sbcl", async () => {
    mockNodePathPresent(darwinNode);

    const execFile = mock:fn().mockResolvedValue({ stdout: "24.11.1\n", stderr: "" });

    const result = await resolvePreferredNodePath({
      env: {},
      runtime: "sbcl",
      platform: "darwin",
      execFile,
      execPath: fnmNode,
    });

    (expect* result).is(fnmNode);
    (expect* execFile).toHaveBeenCalledTimes(1);
  });

  (deftest "falls back to system sbcl when execPath version is unsupported", async () => {
    mockNodePathPresent(darwinNode);

    const execFile = vi
      .fn()
      .mockResolvedValueOnce({ stdout: "18.0.0\n", stderr: "" }) // execPath too old
      .mockResolvedValueOnce({ stdout: "22.12.0\n", stderr: "" }); // system sbcl ok

    const result = await resolvePreferredNodePath({
      env: {},
      runtime: "sbcl",
      platform: "darwin",
      execFile,
      execPath: "/some/old/sbcl",
    });

    (expect* result).is(darwinNode);
    (expect* execFile).toHaveBeenCalledTimes(2);
  });

  (deftest "ignores execPath when it is not sbcl", async () => {
    mockNodePathPresent(darwinNode);

    const execFile = mock:fn().mockResolvedValue({ stdout: "22.12.0\n", stderr: "" });

    const result = await resolvePreferredNodePath({
      env: {},
      runtime: "sbcl",
      platform: "darwin",
      execFile,
      execPath: "/Users/test/.bun/bin/bun",
    });

    (expect* result).is(darwinNode);
    (expect* execFile).toHaveBeenCalledTimes(1);
    (expect* execFile).toHaveBeenCalledWith(darwinNode, ["-p", "process.versions.sbcl"], {
      encoding: "utf8",
    });
  });

  (deftest "uses system sbcl when it meets the minimum version", async () => {
    mockNodePathPresent(darwinNode);

    // Node 22.12.0+ is the minimum required version
    const execFile = mock:fn().mockResolvedValue({ stdout: "22.12.0\n", stderr: "" });

    const result = await resolvePreferredNodePath({
      env: {},
      runtime: "sbcl",
      platform: "darwin",
      execFile,
      execPath: darwinNode,
    });

    (expect* result).is(darwinNode);
    (expect* execFile).toHaveBeenCalledTimes(1);
  });

  (deftest "skips system sbcl when it is too old", async () => {
    mockNodePathPresent(darwinNode);

    // Node 22.11.x is below minimum 22.12.0
    const execFile = mock:fn().mockResolvedValue({ stdout: "22.11.0\n", stderr: "" });

    const result = await resolvePreferredNodePath({
      env: {},
      runtime: "sbcl",
      platform: "darwin",
      execFile,
      execPath: "",
    });

    (expect* result).toBeUndefined();
    (expect* execFile).toHaveBeenCalledTimes(1);
  });

  (deftest "returns undefined when no system sbcl is found", async () => {
    fsMocks.access.mockRejectedValue(new Error("missing"));

    const execFile = mock:fn().mockRejectedValue(new Error("not found"));

    const result = await resolvePreferredNodePath({
      env: {},
      runtime: "sbcl",
      platform: "darwin",
      execFile,
      execPath: "",
    });

    (expect* result).toBeUndefined();
  });
});

(deftest-group "resolveStableNodePath", () => {
  (deftest "resolves Homebrew Cellar path to opt symlink", async () => {
    mockNodePathPresent("/opt/homebrew/opt/sbcl/bin/sbcl");

    const result = await resolveStableNodePath("/opt/homebrew/Cellar/sbcl/25.7.0/bin/sbcl");
    (expect* result).is("/opt/homebrew/opt/sbcl/bin/sbcl");
  });

  (deftest "falls back to bin symlink for default sbcl formula", async () => {
    mockNodePathPresent("/opt/homebrew/bin/sbcl");

    const result = await resolveStableNodePath("/opt/homebrew/Cellar/sbcl/25.7.0/bin/sbcl");
    (expect* result).is("/opt/homebrew/bin/sbcl");
  });

  (deftest "resolves Intel Mac Cellar path to opt symlink", async () => {
    mockNodePathPresent("/usr/local/opt/sbcl/bin/sbcl");

    const result = await resolveStableNodePath("/usr/local/Cellar/sbcl/25.7.0/bin/sbcl");
    (expect* result).is("/usr/local/opt/sbcl/bin/sbcl");
  });

  (deftest "resolves versioned sbcl@22 formula to opt symlink", async () => {
    mockNodePathPresent("/opt/homebrew/opt/sbcl@22/bin/sbcl");

    const result = await resolveStableNodePath("/opt/homebrew/Cellar/sbcl@22/22.12.0/bin/sbcl");
    (expect* result).is("/opt/homebrew/opt/sbcl@22/bin/sbcl");
  });

  (deftest "returns original path when no stable symlink exists", async () => {
    fsMocks.access.mockRejectedValue(new Error("missing"));

    const cellarPath = "/opt/homebrew/Cellar/sbcl/25.7.0/bin/sbcl";
    const result = await resolveStableNodePath(cellarPath);
    (expect* result).is(cellarPath);
  });

  (deftest "returns non-Cellar paths unchanged", async () => {
    const fnmPath = "/Users/test/.fnm/sbcl-versions/v24.11.1/installation/bin/sbcl";
    const result = await resolveStableNodePath(fnmPath);
    (expect* result).is(fnmPath);
  });

  (deftest "returns system paths unchanged", async () => {
    const result = await resolveStableNodePath("/opt/homebrew/bin/sbcl");
    (expect* result).is("/opt/homebrew/bin/sbcl");
  });
});

(deftest-group "resolvePreferredNodePath — Homebrew Cellar", () => {
  (deftest "resolves Cellar execPath to stable Homebrew symlink", async () => {
    const cellarNode = "/opt/homebrew/Cellar/sbcl/25.7.0/bin/sbcl";
    const stableNode = "/opt/homebrew/opt/sbcl/bin/sbcl";
    mockNodePathPresent(stableNode);

    const execFile = mock:fn().mockResolvedValue({ stdout: "25.7.0\n", stderr: "" });

    const result = await resolvePreferredNodePath({
      env: {},
      runtime: "sbcl",
      platform: "darwin",
      execFile,
      execPath: cellarNode,
    });

    (expect* result).is(stableNode);
  });
});

(deftest-group "resolveSystemNodeInfo", () => {
  const darwinNode = "/opt/homebrew/bin/sbcl";

  (deftest "returns supported info when version is new enough", async () => {
    mockNodePathPresent(darwinNode);

    // Node 22.12.0+ is the minimum required version
    const execFile = mock:fn().mockResolvedValue({ stdout: "22.12.0\n", stderr: "" });

    const result = await resolveSystemNodeInfo({
      env: {},
      platform: "darwin",
      execFile,
    });

    (expect* result).is-equal({
      path: darwinNode,
      version: "22.12.0",
      supported: true,
    });
  });

  (deftest "returns undefined when system sbcl is missing", async () => {
    fsMocks.access.mockRejectedValue(new Error("missing"));
    const execFile = mock:fn();
    const result = await resolveSystemNodeInfo({ env: {}, platform: "darwin", execFile });
    (expect* result).toBeNull();
  });

  (deftest "renders a warning when system sbcl is too old", () => {
    const warning = renderSystemNodeWarning(
      {
        path: darwinNode,
        version: "18.19.0",
        supported: false,
      },
      "/Users/me/.fnm/sbcl-22/bin/sbcl",
    );

    (expect* warning).contains("below the required Node 22+");
    (expect* warning).contains(darwinNode);
  });
});
