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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { ChannelDirectoryEntry } from "../../channels/plugins/types.js";
import type { OpenClawConfig } from "../../config/config.js";
import { resetDirectoryCache, resolveMessagingTarget } from "./target-resolver.js";

const mocks = mock:hoisted(() => ({
  listGroups: mock:fn(),
  listGroupsLive: mock:fn(),
  getChannelPlugin: mock:fn(),
}));

mock:mock("../../channels/plugins/index.js", () => ({
  getChannelPlugin: (...args: unknown[]) => mocks.getChannelPlugin(...args),
  normalizeChannelId: (value: string) => value,
}));

(deftest-group "resolveMessagingTarget (directory fallback)", () => {
  const cfg = {} as OpenClawConfig;

  beforeEach(() => {
    mocks.listGroups.mockClear();
    mocks.listGroupsLive.mockClear();
    mocks.getChannelPlugin.mockClear();
    resetDirectoryCache();
    mocks.getChannelPlugin.mockReturnValue({
      directory: {
        listGroups: mocks.listGroups,
        listGroupsLive: mocks.listGroupsLive,
      },
    });
  });

  (deftest "uses live directory fallback and caches the result", async () => {
    const entry: ChannelDirectoryEntry = { kind: "group", id: "123456789", name: "support" };
    mocks.listGroups.mockResolvedValue([]);
    mocks.listGroupsLive.mockResolvedValue([entry]);

    const first = await resolveMessagingTarget({
      cfg,
      channel: "discord",
      input: "support",
    });

    (expect* first.ok).is(true);
    if (first.ok) {
      (expect* first.target.source).is("directory");
      (expect* first.target.to).is("123456789");
    }
    (expect* mocks.listGroups).toHaveBeenCalledTimes(1);
    (expect* mocks.listGroupsLive).toHaveBeenCalledTimes(1);

    const second = await resolveMessagingTarget({
      cfg,
      channel: "discord",
      input: "support",
    });

    (expect* second.ok).is(true);
    (expect* mocks.listGroups).toHaveBeenCalledTimes(1);
    (expect* mocks.listGroupsLive).toHaveBeenCalledTimes(1);
  });

  (deftest "skips directory lookup for direct ids", async () => {
    const result = await resolveMessagingTarget({
      cfg,
      channel: "discord",
      input: "123456789",
    });

    (expect* result.ok).is(true);
    if (result.ok) {
      (expect* result.target.source).is("normalized");
      (expect* result.target.to).is("123456789");
    }
    (expect* mocks.listGroups).not.toHaveBeenCalled();
    (expect* mocks.listGroupsLive).not.toHaveBeenCalled();
  });
});
