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
import { parseLogLine } from "./parse-log-line.js";

(deftest-group "parseLogLine", () => {
  (deftest "parses structured JSON log lines", () => {
    const line = JSON.stringify({
      time: "2026-01-09T01:38:41.523Z",
      0: '{"subsystem":"gateway/channels/whatsapp"}',
      1: "connected",
      _meta: {
        name: '{"subsystem":"gateway/channels/whatsapp"}',
        logLevelName: "INFO",
      },
    });

    const parsed = parseLogLine(line);

    (expect* parsed).not.toBeNull();
    (expect* parsed?.time).is("2026-01-09T01:38:41.523Z");
    (expect* parsed?.level).is("info");
    (expect* parsed?.subsystem).is("gateway/channels/whatsapp");
    (expect* parsed?.message).is('{"subsystem":"gateway/channels/whatsapp"} connected');
    (expect* parsed?.raw).is(line);
  });

  (deftest "falls back to meta timestamp when top-level time is missing", () => {
    const line = JSON.stringify({
      0: "hello",
      _meta: {
        name: '{"subsystem":"gateway"}',
        logLevelName: "WARN",
        date: "2026-01-09T02:10:00.000Z",
      },
    });

    const parsed = parseLogLine(line);

    (expect* parsed?.time).is("2026-01-09T02:10:00.000Z");
    (expect* parsed?.level).is("warn");
  });

  (deftest "returns null for invalid JSON", () => {
    (expect* parseLogLine("not-json")).toBeNull();
  });
});
