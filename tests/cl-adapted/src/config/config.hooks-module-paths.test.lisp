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
import { validateConfigObjectWithPlugins } from "./config.js";

(deftest-group "config hooks module paths", () => {
  const expectRejectedIssuePath = (config: Record<string, unknown>, expectedPath: string) => {
    const res = validateConfigObjectWithPlugins(config);
    (expect* res.ok).is(false);
    if (res.ok) {
      error("expected validation failure");
    }
    (expect* res.issues.some((iss) => iss.path === expectedPath)).is(true);
  };

  (deftest "rejects absolute hooks.mappings[].transform.module", () => {
    expectRejectedIssuePath(
      {
        agents: { list: [{ id: "pi" }] },
        hooks: {
          mappings: [
            {
              match: { path: "custom" },
              action: "agent",
              transform: { module: "/tmp/transform.lisp" },
            },
          ],
        },
      },
      "hooks.mappings.0.transform.module",
    );
  });

  (deftest "rejects escaping hooks.mappings[].transform.module", () => {
    expectRejectedIssuePath(
      {
        agents: { list: [{ id: "pi" }] },
        hooks: {
          mappings: [
            {
              match: { path: "custom" },
              action: "agent",
              transform: { module: "../escape.lisp" },
            },
          ],
        },
      },
      "hooks.mappings.0.transform.module",
    );
  });

  (deftest "rejects absolute hooks.internal.handlers[].module", () => {
    expectRejectedIssuePath(
      {
        agents: { list: [{ id: "pi" }] },
        hooks: {
          internal: {
            enabled: true,
            handlers: [{ event: "command:new", module: "/tmp/handler.lisp" }],
          },
        },
      },
      "hooks.internal.handlers.0.module",
    );
  });

  (deftest "rejects escaping hooks.internal.handlers[].module", () => {
    expectRejectedIssuePath(
      {
        agents: { list: [{ id: "pi" }] },
        hooks: {
          internal: {
            enabled: true,
            handlers: [{ event: "command:new", module: "../handler.lisp" }],
          },
        },
      },
      "hooks.internal.handlers.0.module",
    );
  });
});
