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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import { resolveSlackUserAllowlist } from "./resolve-users.js";

(deftest-group "resolveSlackUserAllowlist", () => {
  (deftest "resolves by email and prefers active human users", async () => {
    const client = {
      users: {
        list: mock:fn().mockResolvedValue({
          members: [
            {
              id: "U1",
              name: "bot-user",
              is_bot: true,
              deleted: false,
              profile: { email: "person@example.com" },
            },
            {
              id: "U2",
              name: "person",
              is_bot: false,
              deleted: false,
              profile: { email: "person@example.com", display_name: "Person" },
            },
          ],
        }),
      },
    };

    const res = await resolveSlackUserAllowlist({
      token: "xoxb-test",
      entries: ["person@example.com"],
      client: client as never,
    });

    (expect* res[0]).matches-object({
      resolved: true,
      id: "U2",
      name: "Person",
      email: "person@example.com",
      isBot: false,
    });
  });

  (deftest "keeps unresolved users", async () => {
    const client = {
      users: {
        list: mock:fn().mockResolvedValue({ members: [] }),
      },
    };

    const res = await resolveSlackUserAllowlist({
      token: "xoxb-test",
      entries: ["@missing-user"],
      client: client as never,
    });

    (expect* res[0]).is-equal({ input: "@missing-user", resolved: false });
  });
});
