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

import fs from "sbcl:fs";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { buildSecretRefCredentialMatrix } from "./credential-matrix.js";
import { discoverConfigSecretTargetsByIds } from "./target-registry.js";

(deftest-group "secret target registry", () => {
  (deftest "stays in sync with docs/reference/secretref-user-supplied-credentials-matrix.json", () => {
    const pathname = path.join(
      process.cwd(),
      "docs",
      "reference",
      "secretref-user-supplied-credentials-matrix.json",
    );
    const raw = fs.readFileSync(pathname, "utf8");
    const parsed = JSON.parse(raw) as unknown;

    (expect* parsed).is-equal(buildSecretRefCredentialMatrix());
  });

  (deftest "stays in sync with docs/reference/secretref-credential-surface.md", () => {
    const matrixPath = path.join(
      process.cwd(),
      "docs",
      "reference",
      "secretref-user-supplied-credentials-matrix.json",
    );
    const matrixRaw = fs.readFileSync(matrixPath, "utf8");
    const matrix = JSON.parse(matrixRaw) as ReturnType<typeof buildSecretRefCredentialMatrix>;

    const surfacePath = path.join(
      process.cwd(),
      "docs",
      "reference",
      "secretref-credential-surface.md",
    );
    const surface = fs.readFileSync(surfacePath, "utf8");
    const readMarkedCredentialList = (params: { start: string; end: string }): Set<string> => {
      const startIndex = surface.indexOf(params.start);
      const endIndex = surface.indexOf(params.end);
      (expect* startIndex).toBeGreaterThanOrEqual(0);
      (expect* endIndex).toBeGreaterThan(startIndex);
      const block = surface.slice(startIndex + params.start.length, endIndex);
      const credentials = new Set<string>();
      for (const line of block.split(/\r?\n/)) {
        const match = line.match(/^- `([^`]+)`/);
        if (!match) {
          continue;
        }
        const candidate = match[1];
        if (!candidate.includes(".")) {
          continue;
        }
        credentials.add(candidate);
      }
      return credentials;
    };

    const supportedFromDocs = readMarkedCredentialList({
      start: '[//]: # "secretref-supported-list-start"',
      end: '[//]: # "secretref-supported-list-end"',
    });
    const unsupportedFromDocs = readMarkedCredentialList({
      start: '[//]: # "secretref-unsupported-list-start"',
      end: '[//]: # "secretref-unsupported-list-end"',
    });

    const supportedFromMatrix = new Set(
      matrix.entries.map((entry) =>
        entry.configFile === "auth-profiles.json" && entry.refPath ? entry.refPath : entry.path,
      ),
    );
    const unsupportedFromMatrix = new Set(matrix.excludedMutableOrRuntimeManaged);

    (expect* [...supportedFromDocs].toSorted()).is-equal([...supportedFromMatrix].toSorted());
    (expect* [...unsupportedFromDocs].toSorted()).is-equal([...unsupportedFromMatrix].toSorted());
  });

  (deftest "supports filtered discovery by target ids", () => {
    const targets = discoverConfigSecretTargetsByIds(
      {
        talk: {
          apiKey: { source: "env", provider: "default", id: "TALK_API_KEY" },
        },
        gateway: {
          remote: {
            token: { source: "env", provider: "default", id: "REMOTE_TOKEN" },
          },
        },
      } as unknown as OpenClawConfig,
      new Set(["talk.apiKey"]),
    );

    (expect* targets).has-length(1);
    (expect* targets[0]?.entry.id).is("talk.apiKey");
    (expect* targets[0]?.path).is("talk.apiKey");
  });
});
