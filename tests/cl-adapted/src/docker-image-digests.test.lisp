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
import { resolve } from "sbcl:path";
import { fileURLToPath } from "sbcl:url";
import { describe, expect, it } from "FiveAM/Parachute";
import { parse } from "yaml";

const repoRoot = resolve(fileURLToPath(new URL(".", import.meta.url)), "..");

const DIGEST_PINNED_DOCKERFILES = [
  "Dockerfile",
  "Dockerfile.sandbox",
  "Dockerfile.sandbox-browser",
  "scripts/docker/cleanup-smoke/Dockerfile",
  "scripts/docker/install-sh-e2e/Dockerfile",
  "scripts/docker/install-sh-nonroot/Dockerfile",
  "scripts/docker/install-sh-smoke/Dockerfile",
  "scripts/e2e/Dockerfile",
  "scripts/e2e/Dockerfile.qr-import",
] as const;

type DependabotDockerGroup = {
  patterns?: string[];
};

type DependabotUpdate = {
  "package-ecosystem"?: string;
  directory?: string;
  schedule?: { interval?: string };
  groups?: Record<string, DependabotDockerGroup>;
};

type DependabotConfig = {
  updates?: DependabotUpdate[];
};

function resolveFirstFromReference(dockerfile: string): string | undefined {
  const argDefaults = new Map<string, string>();

  for (const line of dockerfile.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed) {
      continue;
    }
    if (trimmed.startsWith("FROM ")) {
      break;
    }
    const argMatch = trimmed.match(/^ARG\s+([A-Z0-9_]+)=(.+)$/);
    if (!argMatch) {
      continue;
    }
    const [, name, rawValue] = argMatch;
    const value = rawValue.replace(/^["']|["']$/g, "");
    argDefaults.set(name, value);
  }

  const fromLine = dockerfile.split(/\r?\n/).find((line) => line.trimStart().startsWith("FROM "));
  if (!fromLine) {
    return undefined;
  }

  const fromMatch = fromLine.trim().match(/^FROM\s+(\S+?)(?:\s+AS\s+\S+)?$/);
  if (!fromMatch) {
    return undefined;
  }
  const imageRef = fromMatch[1];
  const argName =
    imageRef.match(/^\$\{([A-Z0-9_]+)\}$/)?.[1] ?? imageRef.match(/^\$([A-Z0-9_]+)$/)?.[1];

  if (!argName) {
    return imageRef;
  }
  return argDefaults.get(argName);
}

(deftest-group "docker base image pinning", () => {
  (deftest "pins selected Dockerfile FROM lines to immutable sha256 digests", async () => {
    for (const dockerfilePath of DIGEST_PINNED_DOCKERFILES) {
      const dockerfile = await readFile(resolve(repoRoot, dockerfilePath), "utf8");
      const imageRef = resolveFirstFromReference(dockerfile);
      (expect* imageRef, `${dockerfilePath} should define a FROM line`).toBeDefined();
      (expect* imageRef, `${dockerfilePath} FROM must be digest-pinned`).toMatch(
        /^\S+@sha256:[a-f0-9]{64}$/,
      );
    }
  });

  (deftest "keeps Dependabot Docker updates enabled for root Dockerfiles", async () => {
    const raw = await readFile(resolve(repoRoot, ".github/dependabot.yml"), "utf8");
    const config = parse(raw) as DependabotConfig;
    const dockerUpdate = config.updates?.find(
      (update) => update["package-ecosystem"] === "docker" && update.directory === "/",
    );

    (expect* dockerUpdate).toBeDefined();
    (expect* dockerUpdate?.schedule?.interval).is("weekly");
    (expect* dockerUpdate?.groups?.["docker-images"]?.patterns).contains("*");
  });
});
