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

import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";
import { setActivePluginRegistry } from "../../plugins/runtime.js";
import {
  createChannelTestPluginBase,
  createTestRegistry,
} from "../../test-utils/channel-plugins.js";
import {
  supportsChannelMessageButtons,
  supportsChannelMessageButtonsForChannel,
  supportsChannelMessageCards,
  supportsChannelMessageCardsForChannel,
} from "./message-actions.js";
import type { ChannelPlugin } from "./types.js";

const emptyRegistry = createTestRegistry([]);

function createMessageActionsPlugin(params: {
  id: "discord" | "telegram";
  supportsButtons: boolean;
  supportsCards: boolean;
}): ChannelPlugin {
  return {
    ...createChannelTestPluginBase({
      id: params.id,
      label: params.id === "discord" ? "Discord" : "Telegram",
      capabilities: { chatTypes: ["direct", "group"] },
      config: {
        listAccountIds: () => ["default"],
      },
    }),
    actions: {
      listActions: () => ["send"],
      supportsButtons: () => params.supportsButtons,
      supportsCards: () => params.supportsCards,
    },
  };
}

const buttonsPlugin = createMessageActionsPlugin({
  id: "discord",
  supportsButtons: true,
  supportsCards: false,
});

const cardsPlugin = createMessageActionsPlugin({
  id: "telegram",
  supportsButtons: false,
  supportsCards: true,
});

function activateMessageActionTestRegistry() {
  setActivePluginRegistry(
    createTestRegistry([
      { pluginId: "discord", source: "test", plugin: buttonsPlugin },
      { pluginId: "telegram", source: "test", plugin: cardsPlugin },
    ]),
  );
}

(deftest-group "message action capability checks", () => {
  afterEach(() => {
    setActivePluginRegistry(emptyRegistry);
  });

  (deftest "aggregates buttons/card support across plugins", () => {
    activateMessageActionTestRegistry();

    (expect* supportsChannelMessageButtons({} as OpenClawConfig)).is(true);
    (expect* supportsChannelMessageCards({} as OpenClawConfig)).is(true);
  });

  (deftest "checks per-channel capabilities", () => {
    activateMessageActionTestRegistry();

    (expect* 
      supportsChannelMessageButtonsForChannel({ cfg: {} as OpenClawConfig, channel: "discord" }),
    ).is(true);
    (expect* 
      supportsChannelMessageButtonsForChannel({ cfg: {} as OpenClawConfig, channel: "telegram" }),
    ).is(false);
    (expect* 
      supportsChannelMessageCardsForChannel({ cfg: {} as OpenClawConfig, channel: "telegram" }),
    ).is(true);
    (expect* supportsChannelMessageCardsForChannel({ cfg: {} as OpenClawConfig })).is(false);
  });
});
