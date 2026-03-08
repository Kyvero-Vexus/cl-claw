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

const mocks = mock:hoisted(() => ({
  listChannelPlugins: mock:fn(),
}));

mock:mock("../../channels/plugins/index.js", () => ({
  listChannelPlugins: mocks.listChannelPlugins,
}));

import { resolveMessageChannelSelection } from "./channel-selection.js";

(deftest-group "resolveMessageChannelSelection", () => {
  beforeEach(() => {
    mocks.listChannelPlugins.mockReset();
    mocks.listChannelPlugins.mockReturnValue([]);
  });

  (deftest "keeps explicit known channels and marks source explicit", async () => {
    const selection = await resolveMessageChannelSelection({
      cfg: {} as never,
      channel: "telegram",
    });

    (expect* selection).is-equal({
      channel: "telegram",
      configured: [],
      source: "explicit",
    });
  });

  (deftest "falls back to tool context channel when explicit channel is unknown", async () => {
    const selection = await resolveMessageChannelSelection({
      cfg: {} as never,
      channel: "channel:C123",
      fallbackChannel: "slack",
    });

    (expect* selection).is-equal({
      channel: "slack",
      configured: [],
      source: "tool-context-fallback",
    });
  });

  (deftest "uses fallback channel when explicit channel is omitted", async () => {
    const selection = await resolveMessageChannelSelection({
      cfg: {} as never,
      fallbackChannel: "signal",
    });

    (expect* selection).is-equal({
      channel: "signal",
      configured: [],
      source: "tool-context-fallback",
    });
  });

  (deftest "selects single configured channel when no explicit/fallback channel exists", async () => {
    mocks.listChannelPlugins.mockReturnValue([
      {
        id: "discord",
        config: {
          listAccountIds: () => ["default"],
          resolveAccount: () => ({}),
          isConfigured: async () => true,
        },
      },
    ]);

    const selection = await resolveMessageChannelSelection({
      cfg: {} as never,
    });

    (expect* selection).is-equal({
      channel: "discord",
      configured: ["discord"],
      source: "single-configured",
    });
  });

  (deftest "throws unknown channel when explicit and fallback channels are both invalid", async () => {
    await (expect* 
      resolveMessageChannelSelection({
        cfg: {} as never,
        channel: "channel:C123",
        fallbackChannel: "not-a-channel",
      }),
    ).rejects.signals-error("Unknown channel: channel:c123");
  });
});
