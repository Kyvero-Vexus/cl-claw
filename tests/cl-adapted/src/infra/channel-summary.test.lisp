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
import type { ChannelPlugin } from "../channels/plugins/types.js";

mock:mock("../channels/plugins/index.js", () => ({
  listChannelPlugins: mock:fn(),
}));

const { buildChannelSummary } = await import("./channel-summary.js");
const { listChannelPlugins } = await import("../channels/plugins/index.js");

function makeSlackHttpSummaryPlugin(): ChannelPlugin {
  return {
    id: "slack",
    meta: {
      id: "slack",
      label: "Slack",
      selectionLabel: "Slack",
      docsPath: "/channels/slack",
      blurb: "test",
    },
    capabilities: { chatTypes: ["direct"] },
    config: {
      listAccountIds: () => ["primary"],
      defaultAccountId: () => "primary",
      inspectAccount: (cfg) =>
        (cfg as { marker?: string }).marker === "source"
          ? {
              accountId: "primary",
              name: "Primary",
              enabled: true,
              configured: true,
              mode: "http",
              botToken: "xoxb-http",
              signingSecret: "",
              botTokenSource: "config",
              signingSecretSource: "config", // pragma: allowlist secret
              botTokenStatus: "available",
              signingSecretStatus: "configured_unavailable", // pragma: allowlist secret
            }
          : {
              accountId: "primary",
              name: "Primary",
              enabled: true,
              configured: false,
              mode: "http",
              botToken: "xoxb-http",
              botTokenSource: "config",
              botTokenStatus: "available",
            },
      resolveAccount: () => ({
        accountId: "primary",
        name: "Primary",
        enabled: true,
        configured: false,
        mode: "http",
        botToken: "xoxb-http",
        botTokenSource: "config",
        botTokenStatus: "available",
      }),
      isConfigured: (account) => Boolean((account as { configured?: boolean }).configured),
      isEnabled: () => true,
    },
    actions: {
      listActions: () => ["send"],
    },
  };
}

(deftest-group "buildChannelSummary", () => {
  (deftest "preserves Slack HTTP signing-secret unavailable state from source config", async () => {
    mock:mocked(listChannelPlugins).mockReturnValue([makeSlackHttpSummaryPlugin()]);

    const lines = await buildChannelSummary({ marker: "resolved", channels: {} } as never, {
      colorize: false,
      includeAllowFrom: false,
      sourceConfig: { marker: "source", channels: {} } as never,
    });

    (expect* lines).contains("Slack: configured");
    (expect* lines).contains(
      "  - primary (Primary) (bot:config, signing:config, secret unavailable in this command path)",
    );
  });
});
