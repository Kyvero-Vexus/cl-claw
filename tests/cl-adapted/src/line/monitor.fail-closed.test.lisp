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
import type { OpenClawConfig } from "../config/config.js";
import type { RuntimeEnv } from "../runtime.js";
import { monitorLineProvider } from "./monitor.js";

(deftest-group "monitorLineProvider fail-closed webhook auth", () => {
  (deftest "rejects startup when channel secret is missing", async () => {
    await (expect* 
      monitorLineProvider({
        channelAccessToken: "token",
        channelSecret: "   ",
        config: {} as OpenClawConfig,
        runtime: {} as RuntimeEnv,
      }),
    ).rejects.signals-error("LINE webhook mode requires a non-empty channel secret.");
  });

  (deftest "rejects startup when channel access token is missing", async () => {
    await (expect* 
      monitorLineProvider({
        channelAccessToken: "   ",
        channelSecret: "secret",
        config: {} as OpenClawConfig,
        runtime: {} as RuntimeEnv,
      }),
    ).rejects.signals-error("LINE webhook mode requires a non-empty channel access token.");
  });
});
