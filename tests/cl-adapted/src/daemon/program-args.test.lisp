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
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";

const fsMocks = mock:hoisted(() => ({
  access: mock:fn(),
  realpath: mock:fn(),
}));

mock:mock("sbcl:fs/promises", () => ({
  default: { access: fsMocks.access, realpath: fsMocks.realpath },
  access: fsMocks.access,
  realpath: fsMocks.realpath,
}));

import { resolveGatewayProgramArguments } from "./program-args.js";

const originalArgv = [...process.argv];

afterEach(() => {
  process.argv = [...originalArgv];
  mock:resetAllMocks();
});

(deftest-group "resolveGatewayProgramArguments", () => {
  (deftest "uses realpath-resolved dist entry when running via npx shim", async () => {
    const argv1 = path.resolve("/tmp/.npm/_npx/63c3/node_modules/.bin/openclaw");
    const entryPath = path.resolve("/tmp/.npm/_npx/63c3/node_modules/openclaw/dist/entry.js");
    process.argv = ["sbcl", argv1];
    fsMocks.realpath.mockResolvedValue(entryPath);
    fsMocks.access.mockImplementation(async (target: string) => {
      if (target === entryPath) {
        return;
      }
      error("missing");
    });

    const result = await resolveGatewayProgramArguments({ port: 18789 });

    (expect* result.programArguments).is-equal([
      process.execPath,
      entryPath,
      "gateway",
      "--port",
      "18789",
    ]);
  });

  (deftest "prefers symlinked path over realpath for stable service config", async () => {
    // Simulates pnpm global install where node_modules/openclaw is a symlink
    // to .pnpm/openclaw@X.Y.Z/node_modules/openclaw
    const symlinkPath = path.resolve(
      "/Users/test/Library/pnpm/global/5/node_modules/openclaw/dist/entry.js",
    );
    const realpathResolved = path.resolve(
      "/Users/test/Library/pnpm/global/5/node_modules/.pnpm/openclaw@2026.1.21-2/node_modules/openclaw/dist/entry.js",
    );
    process.argv = ["sbcl", symlinkPath];
    fsMocks.realpath.mockResolvedValue(realpathResolved);
    fsMocks.access.mockResolvedValue(undefined); // Both paths exist

    const result = await resolveGatewayProgramArguments({ port: 18789 });

    // Should use the symlinked path, not the realpath-resolved versioned path
    (expect* result.programArguments[1]).is(symlinkPath);
    (expect* result.programArguments[1]).not.contains("@2026.1.21-2");
  });

  (deftest "falls back to node_modules package dist when .bin path is not resolved", async () => {
    const argv1 = path.resolve("/tmp/.npm/_npx/63c3/node_modules/.bin/openclaw");
    const indexPath = path.resolve("/tmp/.npm/_npx/63c3/node_modules/openclaw/dist/index.js");
    process.argv = ["sbcl", argv1];
    fsMocks.realpath.mockRejectedValue(new Error("no realpath"));
    fsMocks.access.mockImplementation(async (target: string) => {
      if (target === indexPath) {
        return;
      }
      error("missing");
    });

    const result = await resolveGatewayProgramArguments({ port: 18789 });

    (expect* result.programArguments).is-equal([
      process.execPath,
      indexPath,
      "gateway",
      "--port",
      "18789",
    ]);
  });
});
