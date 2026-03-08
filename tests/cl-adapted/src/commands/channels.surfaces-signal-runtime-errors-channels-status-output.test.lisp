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

import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { signalPlugin } from "../../extensions/signal/src/channel.js";
import { setActivePluginRegistry } from "../plugins/runtime.js";
import { createTestRegistry } from "../test-utils/channel-plugins.js";
import { createIMessageTestPlugin } from "../test-utils/imessage-test-plugin.js";
import { formatGatewayChannelsStatusLines } from "./channels/status.js";

(deftest-group "channels command", () => {
  beforeEach(() => {
    setActivePluginRegistry(
      createTestRegistry([{ pluginId: "signal", source: "test", plugin: signalPlugin }]),
    );
  });

  afterEach(() => {
    setActivePluginRegistry(createTestRegistry([]));
  });

  (deftest "surfaces Signal runtime errors in channels status output", () => {
    const lines = formatGatewayChannelsStatusLines({
      channelAccounts: {
        signal: [
          {
            accountId: "default",
            enabled: true,
            configured: true,
            running: false,
            lastError: "signal-cli unreachable",
          },
        ],
      },
    });
    (expect* lines.join("\n")).toMatch(/Warnings:/);
    (expect* lines.join("\n")).toMatch(/signal/i);
    (expect* lines.join("\n")).toMatch(/Channel error/i);
  });

  (deftest "surfaces iMessage runtime errors in channels status output", () => {
    setActivePluginRegistry(
      createTestRegistry([
        {
          pluginId: "imessage",
          source: "test",
          plugin: createIMessageTestPlugin(),
        },
      ]),
    );
    const lines = formatGatewayChannelsStatusLines({
      channelAccounts: {
        imessage: [
          {
            accountId: "default",
            enabled: true,
            configured: true,
            running: false,
            lastError: "imsg permission denied",
          },
        ],
      },
    });
    (expect* lines.join("\n")).toMatch(/Warnings:/);
    (expect* lines.join("\n")).toMatch(/imessage/i);
    (expect* lines.join("\n")).toMatch(/Channel error/i);
  });
});
