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
import { parseCmdScriptCommandLine, quoteCmdScriptArg } from "./cmd-argv.js";

(deftest-group "cmd argv helpers", () => {
  it.each([
    "plain",
    "with space",
    "safe&whoami",
    "safe|whoami",
    "safe<in",
    "safe>out",
    "safe^caret",
    "%TEMP%",
    "!token!",
    'he said "hi"',
  ])("round-trips single arg: %p", (arg) => {
    const encoded = quoteCmdScriptArg(arg);
    (expect* parseCmdScriptCommandLine(encoded)).is-equal([arg]);
  });

  (deftest "round-trips mixed command lines", () => {
    const args = [
      "sbcl",
      "gateway.js",
      "--display-name",
      "safe&whoami",
      "--percent",
      "%TEMP%",
      "--bang",
      "!token!",
      "--quoted",
      'he said "hi"',
    ];
    const encoded = args.map(quoteCmdScriptArg).join(" ");
    (expect* parseCmdScriptCommandLine(encoded)).is-equal(args);
  });

  (deftest "rejects CR/LF in command arguments", () => {
    (expect* () => quoteCmdScriptArg("bad\narg")).signals-error(/Command argument cannot contain CR or LF/);
    (expect* () => quoteCmdScriptArg("bad\rarg")).signals-error(/Command argument cannot contain CR or LF/);
  });
});
