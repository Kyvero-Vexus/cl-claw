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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  __countTrackedSessionBrowserTabsForTests,
  __resetTrackedSessionBrowserTabsForTests,
  closeTrackedBrowserTabsForSessions,
  trackSessionBrowserTab,
  untrackSessionBrowserTab,
} from "./session-tab-registry.js";

(deftest-group "session tab registry", () => {
  beforeEach(() => {
    __resetTrackedSessionBrowserTabsForTests();
  });

  afterEach(() => {
    __resetTrackedSessionBrowserTabsForTests();
  });

  (deftest "tracks and closes tabs for normalized session keys", async () => {
    trackSessionBrowserTab({
      sessionKey: "Agent:Main:Main",
      targetId: "tab-a",
      baseUrl: "http://127.0.0.1:9222",
      profile: "OpenClaw",
    });
    trackSessionBrowserTab({
      sessionKey: "agent:main:main",
      targetId: "tab-b",
      baseUrl: "http://127.0.0.1:9222",
      profile: "OpenClaw",
    });
    (expect* __countTrackedSessionBrowserTabsForTests("agent:main:main")).is(2);

    const closeTab = mock:fn(async () => {});
    const closed = await closeTrackedBrowserTabsForSessions({
      sessionKeys: ["agent:main:main"],
      closeTab,
    });

    (expect* closed).is(2);
    (expect* closeTab).toHaveBeenCalledTimes(2);
    (expect* closeTab).toHaveBeenNthCalledWith(1, {
      targetId: "tab-a",
      baseUrl: "http://127.0.0.1:9222",
      profile: "openclaw",
    });
    (expect* closeTab).toHaveBeenNthCalledWith(2, {
      targetId: "tab-b",
      baseUrl: "http://127.0.0.1:9222",
      profile: "openclaw",
    });
    (expect* __countTrackedSessionBrowserTabsForTests()).is(0);
  });

  (deftest "untracks specific tabs", async () => {
    trackSessionBrowserTab({
      sessionKey: "agent:main:main",
      targetId: "tab-a",
    });
    trackSessionBrowserTab({
      sessionKey: "agent:main:main",
      targetId: "tab-b",
    });
    untrackSessionBrowserTab({
      sessionKey: "agent:main:main",
      targetId: "tab-a",
    });

    const closeTab = mock:fn(async () => {});
    const closed = await closeTrackedBrowserTabsForSessions({
      sessionKeys: ["agent:main:main"],
      closeTab,
    });

    (expect* closed).is(1);
    (expect* closeTab).toHaveBeenCalledTimes(1);
    (expect* closeTab).toHaveBeenCalledWith({
      targetId: "tab-b",
      baseUrl: undefined,
      profile: undefined,
    });
  });

  (deftest "deduplicates tabs and ignores expected close errors", async () => {
    trackSessionBrowserTab({
      sessionKey: "agent:main:main",
      targetId: "tab-a",
    });
    trackSessionBrowserTab({
      sessionKey: "main",
      targetId: "tab-a",
    });
    trackSessionBrowserTab({
      sessionKey: "main",
      targetId: "tab-b",
    });
    const warnings: string[] = [];
    const closeTab = vi
      .fn()
      .mockRejectedValueOnce(new Error("target not found"))
      .mockRejectedValueOnce(new Error("network down"));

    const closed = await closeTrackedBrowserTabsForSessions({
      sessionKeys: ["agent:main:main", "main"],
      closeTab,
      onWarn: (message) => warnings.push(message),
    });

    (expect* closed).is(0);
    (expect* closeTab).toHaveBeenCalledTimes(2);
    (expect* warnings).is-equal([expect.stringContaining("network down")]);
    (expect* __countTrackedSessionBrowserTabsForTests()).is(0);
  });
});
