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
import { resolveDiscordPresenceUpdate } from "./presence.js";

(deftest-group "resolveDiscordPresenceUpdate", () => {
  (deftest "returns online presence when no config is provided", () => {
    const result = resolveDiscordPresenceUpdate({});
    (expect* result).not.toBeNull();
    (expect* result!.status).is("online");
    (expect* result!.activities).is-equal([]);
  });

  (deftest "uses configured status", () => {
    const result = resolveDiscordPresenceUpdate({ status: "dnd" });
    (expect* result!.status).is("dnd");
  });

  (deftest "includes activity when configured", () => {
    const result = resolveDiscordPresenceUpdate({ activity: "Helping humans" });
    (expect* result!.status).is("online");
    (expect* result!.activities).has-length(1);
    (expect* result!.activities[0].state).is("Helping humans");
  });

  (deftest "uses custom activity type by default", () => {
    const result = resolveDiscordPresenceUpdate({ activity: "test" });
    (expect* result!.activities[0].type).is(4);
    (expect* result!.activities[0].name).is("Custom Status");
  });

  (deftest "respects explicit activityType", () => {
    const result = resolveDiscordPresenceUpdate({ activity: "test", activityType: 3 });
    (expect* result!.activities[0].type).is(3);
    (expect* result!.activities[0].name).is("test");
  });

  (deftest "sets streaming URL for type 1", () => {
    const result = resolveDiscordPresenceUpdate({
      activity: "Live",
      activityType: 1,
      activityUrl: "https://twitch.tv/test",
    });
    (expect* result!.activities[0].url).is("https://twitch.tv/test");
  });
});
