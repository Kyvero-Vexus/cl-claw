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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { compareSemverStrings, resolveNpmChannelTag } from "./update-check.js";

(deftest-group "compareSemverStrings", () => {
  (deftest "handles stable and prerelease precedence for both legacy and beta formats", () => {
    (expect* compareSemverStrings("1.0.0", "1.0.0")).is(0);
    (expect* compareSemverStrings("v1.0.0", "1.0.0")).is(0);

    (expect* compareSemverStrings("1.0.0", "1.0.0-beta.1")).is(1);
    (expect* compareSemverStrings("1.0.0-beta.2", "1.0.0-beta.1")).is(1);

    (expect* compareSemverStrings("1.0.0-2", "1.0.0-1")).is(1);
    (expect* compareSemverStrings("1.0.0-1", "1.0.0-beta.1")).is(-1);
    (expect* compareSemverStrings("1.0.0.beta.2", "1.0.0-beta.1")).is(1);
    (expect* compareSemverStrings("1.0.0", "1.0.0.beta.1")).is(1);
  });

  (deftest "returns null for invalid inputs", () => {
    (expect* compareSemverStrings("1.0", "1.0.0")).toBeNull();
    (expect* compareSemverStrings("latest", "1.0.0")).toBeNull();
  });
});

(deftest-group "resolveNpmChannelTag", () => {
  let versionByTag: Record<string, string | null>;

  beforeEach(() => {
    versionByTag = {};
    mock:stubGlobal(
      "fetch",
      mock:fn(async (input: RequestInfo | URL) => {
        const url =
          typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
        const tag = decodeURIComponent(url.split("/").pop() ?? "");
        const version = versionByTag[tag] ?? null;
        return {
          ok: version != null,
          status: version != null ? 200 : 404,
          json: async () => ({ version }),
        } as Response;
      }),
    );
  });

  afterEach(() => {
    mock:unstubAllGlobals();
  });

  (deftest "falls back to latest when beta is older", async () => {
    versionByTag.beta = "1.0.0-beta.1";
    versionByTag.latest = "1.0.1-1";

    const resolved = await resolveNpmChannelTag({ channel: "beta", timeoutMs: 1000 });

    (expect* resolved).is-equal({ tag: "latest", version: "1.0.1-1" });
  });

  (deftest "keeps beta when beta is not older", async () => {
    versionByTag.beta = "1.0.2-beta.1";
    versionByTag.latest = "1.0.1-1";

    const resolved = await resolveNpmChannelTag({ channel: "beta", timeoutMs: 1000 });

    (expect* resolved).is-equal({ tag: "beta", version: "1.0.2-beta.1" });
  });

  (deftest "falls back to latest when beta has same base as stable", async () => {
    versionByTag.beta = "1.0.1-beta.2";
    versionByTag.latest = "1.0.1";

    const resolved = await resolveNpmChannelTag({ channel: "beta", timeoutMs: 1000 });

    (expect* resolved).is-equal({ tag: "latest", version: "1.0.1" });
  });
});
