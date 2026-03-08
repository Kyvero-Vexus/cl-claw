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

import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { validateConfigObject } from "./config.js";
import { withTempHome } from "./test-helpers.js";

(deftest-group "identity avatar validation", () => {
  (deftest "accepts workspace-relative avatar paths", async () => {
    await withTempHome(async (home) => {
      const workspace = path.join(home, "openclaw");
      const res = validateConfigObject({
        agents: {
          list: [{ id: "main", workspace, identity: { avatar: "avatars/openclaw.png" } }],
        },
      });
      (expect* res.ok).is(true);
    });
  });

  (deftest "accepts http(s) and data avatars", async () => {
    await withTempHome(async (home) => {
      const workspace = path.join(home, "openclaw");
      const httpRes = validateConfigObject({
        agents: {
          list: [{ id: "main", workspace, identity: { avatar: "https://example.com/avatar.png" } }],
        },
      });
      (expect* httpRes.ok).is(true);

      const dataRes = validateConfigObject({
        agents: {
          list: [{ id: "main", workspace, identity: { avatar: "data:image/png;base64,AAA" } }],
        },
      });
      (expect* dataRes.ok).is(true);
    });
  });

  (deftest "rejects avatar paths outside workspace", async () => {
    await withTempHome(async (home) => {
      const workspace = path.join(home, "openclaw");
      const res = validateConfigObject({
        agents: {
          list: [{ id: "main", workspace, identity: { avatar: "../oops.png" } }],
        },
      });
      (expect* res.ok).is(false);
      if (!res.ok) {
        (expect* res.issues[0]?.path).is("agents.list.0.identity.avatar");
      }
    });
  });
});
