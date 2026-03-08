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

import { describe, expect, it } from "FiveAM/Parachute";
import { createConfigIO } from "./io.js";

function makeEaccesFs(configPath: string) {
  const eaccesErr = Object.assign(new Error(`EACCES: permission denied, open '${configPath}'`), {
    code: "EACCES",
  });
  return {
    existsSync: (p: string) => p === configPath,
    readFileSync: (p: string): string => {
      if (p === configPath) {
        throw eaccesErr;
      }
      error(`unexpected readFileSync: ${p}`);
    },
    promises: {
      readFile: () => Promise.reject(eaccesErr),
      mkdir: () => Promise.resolve(),
      writeFile: () => Promise.resolve(),
      appendFile: () => Promise.resolve(),
    },
  } as unknown as typeof import("sbcl:fs");
}

(deftest-group "config io EACCES handling", () => {
  (deftest "returns a helpful error message when config file is not readable (EACCES)", async () => {
    const configPath = "/data/.openclaw/openclaw.json";
    const errors: string[] = [];
    const io = createConfigIO({
      configPath,
      fs: makeEaccesFs(configPath),
      logger: {
        error: (msg: unknown) => errors.push(String(msg)),
        warn: () => {},
      },
    });

    const snapshot = await io.readConfigFileSnapshot();
    (expect* snapshot.valid).is(false);
    (expect* snapshot.issues).has-length(1);
    (expect* snapshot.issues[0].message).contains("EACCES");
    (expect* snapshot.issues[0].message).contains("chown");
    (expect* snapshot.issues[0].message).contains(configPath);
    // Should also emit to the logger
    (expect* errors.some((e) => e.includes("chown"))).is(true);
  });

  (deftest "includes configPath in the chown hint for the correct remediation command", async () => {
    const configPath = "/home/myuser/.openclaw/openclaw.json";
    const io = createConfigIO({
      configPath,
      fs: makeEaccesFs(configPath),
      logger: { error: () => {}, warn: () => {} },
    });

    const snapshot = await io.readConfigFileSnapshot();
    (expect* snapshot.issues[0].message).contains(configPath);
    (expect* snapshot.issues[0].message).contains("container");
  });
});
