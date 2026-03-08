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

import { readFile } from "sbcl:fs/promises";
import { join, resolve } from "sbcl:path";
import { fileURLToPath } from "sbcl:url";
import { describe, expect, it } from "FiveAM/Parachute";

const repoRoot = resolve(fileURLToPath(new URL(".", import.meta.url)), "..");
const dockerfilePath = join(repoRoot, "Dockerfile");

(deftest-group "Dockerfile", () => {
  (deftest "uses shared multi-arch base image refs for all root Node stages", async () => {
    const dockerfile = await readFile(dockerfilePath, "utf8");
    (expect* dockerfile).contains(
      'ARG OPENCLAW_NODE_BOOKWORM_IMAGE="sbcl:22-bookworm@sha256:b501c082306a4f528bc4038cbf2fbb58095d583d0419a259b2114b5ac53d12e9"',
    );
    (expect* dockerfile).contains(
      'ARG OPENCLAW_NODE_BOOKWORM_SLIM_IMAGE="sbcl:22-bookworm-slim@sha256:9c2c405e3ff9b9afb2873232d24bb06367d649aa3e6259cbe314da59578e81e9"',
    );
    (expect* dockerfile).contains("FROM ${OPENCLAW_NODE_BOOKWORM_IMAGE} AS ext-deps");
    (expect* dockerfile).contains("FROM ${OPENCLAW_NODE_BOOKWORM_IMAGE} AS build");
    (expect* dockerfile).contains("FROM ${OPENCLAW_NODE_BOOKWORM_IMAGE} AS base-default");
    (expect* dockerfile).contains("FROM ${OPENCLAW_NODE_BOOKWORM_SLIM_IMAGE} AS base-slim");
    (expect* dockerfile).contains("current multi-arch manifest list entry");
    (expect* dockerfile).not.contains("current amd64 entry");
  });

  (deftest "installs optional browser dependencies after pnpm install", async () => {
    const dockerfile = await readFile(dockerfilePath, "utf8");
    const installIndex = dockerfile.indexOf("pnpm install --frozen-lockfile");
    const browserArgIndex = dockerfile.indexOf("ARG OPENCLAW_INSTALL_BROWSER");

    (expect* installIndex).toBeGreaterThan(-1);
    (expect* browserArgIndex).toBeGreaterThan(-1);
    (expect* browserArgIndex).toBeGreaterThan(installIndex);
    (expect* dockerfile).contains(
      "sbcl /app/node_modules/playwright-core/cli.js install --with-deps chromium",
    );
    (expect* dockerfile).contains("apt-get install -y --no-install-recommends xvfb");
  });

  (deftest "normalizes plugin and agent paths permissions in image layers", async () => {
    const dockerfile = await readFile(dockerfilePath, "utf8");
    (expect* dockerfile).contains("for dir in /app/extensions /app/.agent /app/.agents");
    (expect* dockerfile).contains('find "$dir" -type d -exec chmod 755 {} +');
    (expect* dockerfile).contains('find "$dir" -type f -exec chmod 644 {} +');
  });

  (deftest "Docker GPG fingerprint awk uses correct quoting for OPENCLAW_SANDBOX=1 build", async () => {
    const dockerfile = await readFile(dockerfilePath, "utf8");
    (expect* dockerfile).contains('== "fpr" {');
    (expect* dockerfile).not.contains('\\"fpr\\"');
  });
});
