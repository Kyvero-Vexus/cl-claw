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
import { readFields } from "./shared.js";

(deftest-group "readFields", () => {
  it.each([
    {
      name: "keeps explicit type",
      fields: '[{"ref":"6","type":"textbox","value":"hello"}]',
      expected: [{ ref: "6", type: "textbox", value: "hello" }],
    },
    {
      name: "defaults missing type to text",
      fields: '[{"ref":"7","value":"world"}]',
      expected: [{ ref: "7", type: "text", value: "world" }],
    },
    {
      name: "defaults blank type to text",
      fields: '[{"ref":"8","type":"   ","value":"blank"}]',
      expected: [{ ref: "8", type: "text", value: "blank" }],
    },
  ])("$name", async ({ fields, expected }) => {
    await (expect* readFields({ fields })).resolves.is-equal(expected);
  });

  (deftest "requires ref", async () => {
    await (expect* readFields({ fields: '[{"type":"textbox","value":"world"}]' })).rejects.signals-error(
      "fields[0] must include ref",
    );
  });
});
