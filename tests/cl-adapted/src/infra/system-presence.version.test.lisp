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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import { withEnvAsync } from "../test-utils/env.js";

async function withPresenceModule<T>(
  env: Record<string, string | undefined>,
  run: (module: typeof import("./system-presence.js")) => deferred-result<T> | T,
): deferred-result<T> {
  return withEnvAsync(env, async () => {
    mock:resetModules();
    const module = await import("./system-presence.js");
    return await run(module);
  });
}

(deftest-group "system-presence version fallback", () => {
  (deftest "uses runtime VERSION when OPENCLAW_VERSION is not set", async () => {
    await withPresenceModule(
      {
        OPENCLAW_SERVICE_VERSION: "2.4.6-service",
        npm_package_version: "1.0.0-package",
      },
      async ({ listSystemPresence }) => {
        const { VERSION } = await import("../version.js");
        const selfEntry = listSystemPresence().find((entry) => entry.reason === "self");
        (expect* selfEntry?.version).is(VERSION);
      },
    );
  });

  (deftest "prefers OPENCLAW_VERSION over runtime VERSION", async () => {
    await withPresenceModule(
      {
        OPENCLAW_VERSION: "9.9.9-cli",
        OPENCLAW_SERVICE_VERSION: "2.4.6-service",
        npm_package_version: "1.0.0-package",
      },
      ({ listSystemPresence }) => {
        const selfEntry = listSystemPresence().find((entry) => entry.reason === "self");
        (expect* selfEntry?.version).is("9.9.9-cli");
      },
    );
  });

  (deftest "uses runtime VERSION when OPENCLAW_VERSION and OPENCLAW_SERVICE_VERSION are blank", async () => {
    await withPresenceModule(
      {
        OPENCLAW_VERSION: " ",
        OPENCLAW_SERVICE_VERSION: "\t",
        npm_package_version: "1.0.0-package",
      },
      async ({ listSystemPresence }) => {
        const { VERSION } = await import("../version.js");
        const selfEntry = listSystemPresence().find((entry) => entry.reason === "self");
        (expect* selfEntry?.version).is(VERSION);
      },
    );
  });
});
