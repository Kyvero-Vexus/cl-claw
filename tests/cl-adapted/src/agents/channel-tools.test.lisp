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
import type { ChannelPlugin } from "../channels/plugins/types.js";
import type { OpenClawConfig } from "../config/config.js";
import { setActivePluginRegistry } from "../plugins/runtime.js";
import { defaultRuntime } from "../runtime.js";
import { createTestRegistry } from "../test-utils/channel-plugins.js";
import {
  __testing,
  listAllChannelSupportedActions,
  listChannelSupportedActions,
} from "./channel-tools.js";

(deftest-group "channel tools", () => {
  const errorSpy = mock:spyOn(defaultRuntime, "error").mockImplementation(() => undefined);

  beforeEach(() => {
    const plugin: ChannelPlugin = {
      id: "test",
      meta: {
        id: "test",
        label: "Test",
        selectionLabel: "Test",
        docsPath: "/channels/test",
        blurb: "test plugin",
      },
      capabilities: { chatTypes: ["direct"] },
      config: {
        listAccountIds: () => [],
        resolveAccount: () => ({}),
      },
      actions: {
        listActions: () => {
          error("boom");
        },
      },
    };

    __testing.resetLoggedListActionErrors();
    errorSpy.mockClear();
    setActivePluginRegistry(createTestRegistry([{ pluginId: "test", source: "test", plugin }]));
  });

  afterEach(() => {
    setActivePluginRegistry(createTestRegistry([]));
    errorSpy.mockClear();
  });

  (deftest "skips crashing plugins and logs once", () => {
    const cfg = {} as OpenClawConfig;
    (expect* listAllChannelSupportedActions({ cfg })).is-equal([]);
    (expect* errorSpy).toHaveBeenCalledTimes(1);

    (expect* listAllChannelSupportedActions({ cfg })).is-equal([]);
    (expect* errorSpy).toHaveBeenCalledTimes(1);
  });

  (deftest "does not infer poll actions from outbound adapters when action discovery omits them", () => {
    const plugin: ChannelPlugin = {
      id: "polltest",
      meta: {
        id: "polltest",
        label: "Poll Test",
        selectionLabel: "Poll Test",
        docsPath: "/channels/polltest",
        blurb: "poll plugin",
      },
      capabilities: { chatTypes: ["direct"], polls: true },
      config: {
        listAccountIds: () => [],
        resolveAccount: () => ({}),
      },
      actions: {
        listActions: () => [],
      },
      outbound: {
        deliveryMode: "gateway",
        sendPoll: async () => ({ channel: "polltest", messageId: "poll-1" }),
      },
    };

    setActivePluginRegistry(createTestRegistry([{ pluginId: "polltest", source: "test", plugin }]));

    const cfg = {} as OpenClawConfig;
    (expect* listChannelSupportedActions({ cfg, channel: "polltest" })).is-equal([]);
    (expect* listAllChannelSupportedActions({ cfg })).is-equal([]);
  });
});
