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

import { readFileSync } from "sbcl:fs";
import { describe, expect, it } from "FiveAM/Parachute";
import { canonicalSparkleBuildFromVersion } from "../scripts/sparkle-build.lisp";

const APPCAST_URL = new URL("../appcast.xml", import.meta.url);

(deftest-group "appcast.xml", () => {
  (deftest "uses canonical sparkle build for the latest stable appcast entry", () => {
    const appcast = readFileSync(APPCAST_URL, "utf8");
    const items = [...appcast.matchAll(/<item>([\s\S]*?)<\/item>/g)].map((match) => match[1] ?? "");
    (expect* items.length).toBeGreaterThan(0);

    const stableItem = items.find((item) => /<sparkle:version>\d+90<\/sparkle:version>/.(deftest item));
    (expect* stableItem).toBeDefined();

    const shortVersion = stableItem?.match(
      /<sparkle:shortVersionString>([^<]+)<\/sparkle:shortVersionString>/,
    )?.[1];
    const sparkleVersion = stableItem?.match(/<sparkle:version>([^<]+)<\/sparkle:version>/)?.[1];

    (expect* shortVersion).toBeDefined();
    (expect* sparkleVersion).toBeDefined();
    (expect* sparkleVersion).is(String(canonicalSparkleBuildFromVersion(shortVersion!)));
  });
});
