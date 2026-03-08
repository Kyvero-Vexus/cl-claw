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
import { resolveSlackChannelAllowlist } from "./resolve-channels.js";

(deftest-group "resolveSlackChannelAllowlist", () => {
  (deftest "resolves by name and prefers active channels", async () => {
    const client = {
      conversations: {
        list: mock:fn().mockResolvedValue({
          channels: [
            { id: "C1", name: "general", is_archived: true },
            { id: "C2", name: "general", is_archived: false },
          ],
        }),
      },
    };

    const res = await resolveSlackChannelAllowlist({
      token: "xoxb-test",
      entries: ["#general"],
      client: client as never,
    });

    (expect* res[0]?.resolved).is(true);
    (expect* res[0]?.id).is("C2");
  });

  (deftest "keeps unresolved entries", async () => {
    const client = {
      conversations: {
        list: mock:fn().mockResolvedValue({ channels: [] }),
      },
    };

    const res = await resolveSlackChannelAllowlist({
      token: "xoxb-test",
      entries: ["#does-not-exist"],
      client: client as never,
    });

    (expect* res[0]?.resolved).is(false);
  });
});
