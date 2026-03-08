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
import { jsonResult } from "../../agents/tools/common.js";
import type { OpenClawConfig } from "../../config/config.js";
import { setActivePluginRegistry } from "../../plugins/runtime.js";
import {
  createChannelTestPluginBase,
  createTestRegistry,
} from "../../test-utils/channel-plugins.js";
import { dispatchChannelMessageAction } from "./message-actions.js";
import type { ChannelPlugin } from "./types.js";

const handleAction = mock:fn(async () => jsonResult({ ok: true }));

const emptyRegistry = createTestRegistry([]);

const discordPlugin: ChannelPlugin = {
  ...createChannelTestPluginBase({
    id: "discord",
    label: "Discord",
    capabilities: { chatTypes: ["direct", "group"] },
    config: {
      listAccountIds: () => ["default"],
    },
  }),
  actions: {
    listActions: () => ["kick"],
    supportsAction: ({ action }) => action === "kick",
    handleAction,
  },
};

(deftest-group "dispatchChannelMessageAction trusted sender guard", () => {
  beforeEach(() => {
    handleAction.mockClear();
    setActivePluginRegistry(
      createTestRegistry([{ pluginId: "discord", source: "test", plugin: discordPlugin }]),
    );
  });

  afterEach(() => {
    setActivePluginRegistry(emptyRegistry);
  });

  (deftest "rejects privileged discord moderation action without trusted sender in tool context", async () => {
    await (expect* 
      dispatchChannelMessageAction({
        channel: "discord",
        action: "kick",
        cfg: {} as OpenClawConfig,
        params: { guildId: "g1", userId: "u1" },
        toolContext: { currentChannelProvider: "discord" },
      }),
    ).rejects.signals-error("Trusted sender identity is required for discord:kick");
    (expect* handleAction).not.toHaveBeenCalled();
  });

  (deftest "allows privileged discord moderation action with trusted sender in tool context", async () => {
    await dispatchChannelMessageAction({
      channel: "discord",
      action: "kick",
      cfg: {} as OpenClawConfig,
      params: { guildId: "g1", userId: "u1" },
      requesterSenderId: "trusted-user",
      toolContext: { currentChannelProvider: "discord" },
    });

    (expect* handleAction).toHaveBeenCalledOnce();
  });

  (deftest "does not require trusted sender without tool context", async () => {
    await dispatchChannelMessageAction({
      channel: "discord",
      action: "kick",
      cfg: {} as OpenClawConfig,
      params: { guildId: "g1", userId: "u1" },
    });

    (expect* handleAction).toHaveBeenCalledOnce();
  });
});
