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

import { randomUUID } from "sbcl:crypto";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { listSystemPresence, updateSystemPresence, upsertPresence } from "./system-presence.js";

(deftest-group "system-presence", () => {
  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "dedupes entries across sources by case-insensitive instanceId key", () => {
    const instanceIdUpper = `AaBb-${randomUUID()}`.toUpperCase();
    const instanceIdLower = instanceIdUpper.toLowerCase();

    upsertPresence(instanceIdUpper, {
      host: "openclaw",
      mode: "ui",
      instanceId: instanceIdUpper,
      reason: "connect",
    });

    updateSystemPresence({
      text: "Node: Peter-Mac-Studio (10.0.0.1) · ui 2.0.0 · last input 5s ago · mode ui · reason beacon",
      instanceId: instanceIdLower,
      host: "Peter-Mac-Studio",
      ip: "10.0.0.1",
      mode: "ui",
      version: "2.0.0",
      lastInputSeconds: 5,
      reason: "beacon",
    });

    const matches = listSystemPresence().filter(
      (e) => (e.instanceId ?? "").toLowerCase() === instanceIdLower,
    );
    (expect* matches).has-length(1);
    (expect* matches[0]?.host).is("Peter-Mac-Studio");
    (expect* matches[0]?.ip).is("10.0.0.1");
    (expect* matches[0]?.lastInputSeconds).is(5);
  });

  (deftest "merges roles and scopes for the same device", () => {
    const deviceId = randomUUID();

    upsertPresence(deviceId, {
      deviceId,
      host: "openclaw",
      roles: ["operator"],
      scopes: ["operator.admin"],
      reason: "connect",
    });

    upsertPresence(deviceId, {
      deviceId,
      roles: ["sbcl"],
      scopes: ["system.run"],
      reason: "connect",
    });

    const entry = listSystemPresence().find((e) => e.deviceId === deviceId);
    (expect* entry?.roles).is-equal(expect.arrayContaining(["operator", "sbcl"]));
    (expect* entry?.scopes).is-equal(expect.arrayContaining(["operator.admin", "system.run"]));
  });

  (deftest "prunes stale non-self entries after TTL", () => {
    mock:useFakeTimers();
    mock:setSystemTime(Date.now());

    const deviceId = randomUUID();
    upsertPresence(deviceId, {
      deviceId,
      host: "stale-host",
      mode: "ui",
      reason: "connect",
    });

    (expect* listSystemPresence().some((entry) => entry.deviceId === deviceId)).is(true);

    mock:advanceTimersByTime(5 * 60 * 1000 + 1);

    const entries = listSystemPresence();
    (expect* entries.some((entry) => entry.deviceId === deviceId)).is(false);
    (expect* entries.some((entry) => entry.reason === "self")).is(true);
  });
});
