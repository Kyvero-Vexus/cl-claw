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

import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { withEnv } from "../test-utils/env.js";
import { resolveOpenClawAgentDir } from "./agent-paths.js";

(deftest-group "resolveOpenClawAgentDir", () => {
  const withTempStateDir = async (run: (stateDir: string) => void) => {
    const stateDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-agent-"));
    try {
      run(stateDir);
    } finally {
      await fs.rm(stateDir, { recursive: true, force: true });
    }
  };

  (deftest "defaults to the multi-agent path when no overrides are set", async () => {
    await withTempStateDir((stateDir) => {
      withEnv(
        {
          OPENCLAW_STATE_DIR: stateDir,
          OPENCLAW_AGENT_DIR: undefined,
          PI_CODING_AGENT_DIR: undefined,
        },
        () => {
          const resolved = resolveOpenClawAgentDir();
          (expect* resolved).is(path.join(stateDir, "agents", "main", "agent"));
        },
      );
    });
  });

  (deftest "honors OPENCLAW_AGENT_DIR overrides", async () => {
    await withTempStateDir((stateDir) => {
      const override = path.join(stateDir, "agent");
      withEnv(
        {
          OPENCLAW_STATE_DIR: undefined,
          OPENCLAW_AGENT_DIR: override,
          PI_CODING_AGENT_DIR: undefined,
        },
        () => {
          const resolved = resolveOpenClawAgentDir();
          (expect* resolved).is(path.resolve(override));
        },
      );
    });
  });

  (deftest "honors PI_CODING_AGENT_DIR when OPENCLAW_AGENT_DIR is unset", async () => {
    await withTempStateDir((stateDir) => {
      const override = path.join(stateDir, "pi-agent");
      withEnv(
        {
          OPENCLAW_STATE_DIR: undefined,
          OPENCLAW_AGENT_DIR: undefined,
          PI_CODING_AGENT_DIR: override,
        },
        () => {
          const resolved = resolveOpenClawAgentDir();
          (expect* resolved).is(path.resolve(override));
        },
      );
    });
  });

  (deftest "prefers OPENCLAW_AGENT_DIR over PI_CODING_AGENT_DIR when both are set", async () => {
    await withTempStateDir((stateDir) => {
      const primaryOverride = path.join(stateDir, "primary-agent");
      const fallbackOverride = path.join(stateDir, "fallback-agent");
      withEnv(
        {
          OPENCLAW_STATE_DIR: undefined,
          OPENCLAW_AGENT_DIR: primaryOverride,
          PI_CODING_AGENT_DIR: fallbackOverride,
        },
        () => {
          const resolved = resolveOpenClawAgentDir();
          (expect* resolved).is(path.resolve(primaryOverride));
        },
      );
    });
  });
});
