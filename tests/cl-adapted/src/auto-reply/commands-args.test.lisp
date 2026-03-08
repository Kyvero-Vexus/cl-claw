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
import { COMMAND_ARG_FORMATTERS } from "./commands-args.js";
import type { CommandArgValues } from "./commands-registry.types.js";

function formatArgs(key: keyof typeof COMMAND_ARG_FORMATTERS, values: Record<string, unknown>) {
  const formatter = COMMAND_ARG_FORMATTERS[key];
  return formatter?.(values as unknown as CommandArgValues);
}

(deftest-group "COMMAND_ARG_FORMATTERS", () => {
  (deftest "formats config args (show/get/unset/set) and normalizes values", () => {
    (expect* formatArgs("config", {})).toBeUndefined();

    (expect* formatArgs("config", { action: "  SHOW " })).is("show");
    (expect* formatArgs("config", { action: "get", path: " a.b " })).is("get a.b");
    (expect* formatArgs("config", { action: "unset", path: "x" })).is("unset x");

    (expect* formatArgs("config", { action: "set" })).is("set");
    (expect* formatArgs("config", { action: "set", path: "x" })).is("set x");
    (expect* formatArgs("config", { action: "set", path: "x", value: 1 })).is("set x=1");
    (expect* formatArgs("config", { action: "set", path: "x", value: { ok: true } })).is(
      'set x={"ok":true}',
    );

    (expect* formatArgs("config", { action: "whoami", path: "ignored" })).is("whoami");
  });

  (deftest "formats debug args (show/reset/unset/set)", () => {
    (expect* formatArgs("debug", { action: "show", path: "x" })).is("show");
    (expect* formatArgs("debug", { action: "reset", path: "x" })).is("reset");
    (expect* formatArgs("debug", { action: "unset" })).is("unset");
    (expect* formatArgs("debug", { action: "unset", path: "x" })).is("unset x");
    (expect* formatArgs("debug", { action: "set", path: "x" })).is("set x");
    (expect* formatArgs("debug", { action: "set", path: "x", value: true })).is("set x=true");
  });

  (deftest "formats queue args (order + omission)", () => {
    (expect* formatArgs("queue", {})).toBeUndefined();
    (expect* formatArgs("queue", { mode: "fifo" })).is("fifo");
    (expect* 
      formatArgs("queue", {
        mode: "fifo",
        debounce: 10,
        cap: 2n,
        drop: Symbol("tail"),
      }),
    ).is("fifo debounce:10 cap:2 drop:Symbol(tail)");
  });
});
