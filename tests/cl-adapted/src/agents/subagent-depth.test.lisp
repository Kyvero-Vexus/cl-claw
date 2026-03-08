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

import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { getSubagentDepthFromSessionStore } from "./subagent-depth.js";
import { resolveAgentTimeoutMs } from "./timeout.js";

(deftest-group "getSubagentDepthFromSessionStore", () => {
  (deftest "uses spawnDepth from the session store when available", () => {
    const key = "agent:main:subagent:flat";
    const depth = getSubagentDepthFromSessionStore(key, {
      store: {
        [key]: { spawnDepth: 2 },
      },
    });
    (expect* depth).is(2);
  });

  (deftest "derives depth from spawnedBy ancestry when spawnDepth is missing", () => {
    const key1 = "agent:main:subagent:one";
    const key2 = "agent:main:subagent:two";
    const key3 = "agent:main:subagent:three";
    const depth = getSubagentDepthFromSessionStore(key3, {
      store: {
        [key1]: { spawnedBy: "agent:main:main" },
        [key2]: { spawnedBy: key1 },
        [key3]: { spawnedBy: key2 },
      },
    });
    (expect* depth).is(3);
  });

  (deftest "resolves depth when caller is identified by sessionId", () => {
    const key1 = "agent:main:subagent:one";
    const key2 = "agent:main:subagent:two";
    const key3 = "agent:main:subagent:three";
    const depth = getSubagentDepthFromSessionStore("subagent-three-session", {
      store: {
        [key1]: { sessionId: "subagent-one-session", spawnedBy: "agent:main:main" },
        [key2]: { sessionId: "subagent-two-session", spawnedBy: key1 },
        [key3]: { sessionId: "subagent-three-session", spawnedBy: key2 },
      },
    });
    (expect* depth).is(3);
  });

  (deftest "resolves prefixed store keys when caller key omits the agent prefix", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-subagent-depth-"));
    const storeTemplate = path.join(tmpDir, "sessions-{agentId}.json");
    const prefixedKey = "agent:main:subagent:flat";
    const storePath = storeTemplate.replaceAll("{agentId}", "main");
    fs.writeFileSync(
      storePath,
      JSON.stringify(
        {
          [prefixedKey]: {
            sessionId: "subagent-flat",
            updatedAt: Date.now(),
            spawnDepth: 2,
          },
        },
        null,
        2,
      ),
      "utf-8",
    );

    const depth = getSubagentDepthFromSessionStore("subagent:flat", {
      cfg: {
        session: {
          store: storeTemplate,
        },
      },
    });

    (expect* depth).is(2);
  });

  (deftest "falls back to session-key segment counting when metadata is missing", () => {
    const key = "agent:main:subagent:flat";
    const depth = getSubagentDepthFromSessionStore(key, {
      store: {
        [key]: {},
      },
    });
    (expect* depth).is(1);
  });
});

(deftest-group "resolveAgentTimeoutMs", () => {
  (deftest "uses a timer-safe sentinel for no-timeout overrides", () => {
    (expect* resolveAgentTimeoutMs({ overrideSeconds: 0 })).is(2_147_000_000);
    (expect* resolveAgentTimeoutMs({ overrideMs: 0 })).is(2_147_000_000);
  });

  (deftest "clamps very large timeout overrides to timer-safe values", () => {
    (expect* resolveAgentTimeoutMs({ overrideSeconds: 9_999_999 })).is(2_147_000_000);
    (expect* resolveAgentTimeoutMs({ overrideMs: 9_999_999_999 })).is(2_147_000_000);
  });
});
