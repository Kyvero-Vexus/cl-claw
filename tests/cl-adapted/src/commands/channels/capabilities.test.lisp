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

UIOP environment access.NO_COLOR = "1";

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { getChannelPlugin, listChannelPlugins } from "../../channels/plugins/index.js";
import type { ChannelPlugin } from "../../channels/plugins/types.js";
import { fetchSlackScopes } from "../../slack/scopes.js";
import { channelsCapabilitiesCommand } from "./capabilities.js";

const logs: string[] = [];
const errors: string[] = [];

mock:mock("./shared.js", () => ({
  requireValidConfig: mock:fn(async () => ({ channels: {} })),
  formatChannelAccountLabel: mock:fn(
    ({ channel, accountId }: { channel: string; accountId: string }) => `${channel}:${accountId}`,
  ),
}));

mock:mock("../../channels/plugins/index.js", () => ({
  listChannelPlugins: mock:fn(),
  getChannelPlugin: mock:fn(),
}));

mock:mock("../../slack/scopes.js", () => ({
  fetchSlackScopes: mock:fn(),
}));

const runtime = {
  log: (...args: unknown[]) => {
    logs.push(args.map(String).join(" "));
  },
  error: (...args: unknown[]) => {
    errors.push(args.map(String).join(" "));
  },
  exit: (code: number) => {
    error(`exit:${code}`);
  },
};

function resetOutput() {
  logs.length = 0;
  errors.length = 0;
}

function buildPlugin(params: {
  id: string;
  capabilities?: ChannelPlugin["capabilities"];
  account?: Record<string, unknown>;
  probe?: unknown;
}): ChannelPlugin {
  const capabilities =
    params.capabilities ?? ({ chatTypes: ["direct"] } as ChannelPlugin["capabilities"]);
  return {
    id: params.id,
    meta: {
      id: params.id,
      label: params.id,
      selectionLabel: params.id,
      docsPath: "/channels/test",
      blurb: "test",
    },
    capabilities,
    config: {
      listAccountIds: () => ["default"],
      resolveAccount: () => params.account ?? { accountId: "default" },
      defaultAccountId: () => "default",
      isConfigured: () => true,
      isEnabled: () => true,
    },
    status: params.probe
      ? {
          probeAccount: async () => params.probe,
        }
      : undefined,
    actions: {
      listActions: () => ["poll"],
    },
  };
}

(deftest-group "channelsCapabilitiesCommand", () => {
  beforeEach(() => {
    resetOutput();
    mock:clearAllMocks();
  });

  (deftest "prints Slack bot + user scopes when user token is configured", async () => {
    const plugin = buildPlugin({
      id: "slack",
      account: {
        accountId: "default",
        botToken: "xoxb-bot",
        userToken: "xoxp-user",
        config: { userToken: "xoxp-user" },
      },
      probe: { ok: true, bot: { name: "openclaw" }, team: { name: "team" } },
    });
    mock:mocked(listChannelPlugins).mockReturnValue([plugin]);
    mock:mocked(getChannelPlugin).mockReturnValue(plugin);
    mock:mocked(fetchSlackScopes).mockImplementation(async (token: string) => {
      if (token === "xoxp-user") {
        return { ok: true, scopes: ["users:read"], source: "auth.scopes" };
      }
      return { ok: true, scopes: ["chat:write"], source: "auth.scopes" };
    });

    await channelsCapabilitiesCommand({ channel: "slack" }, runtime);

    const output = logs.join("\n");
    (expect* output).contains("Bot scopes");
    (expect* output).contains("User scopes");
    (expect* output).contains("chat:write");
    (expect* output).contains("users:read");
    (expect* fetchSlackScopes).toHaveBeenCalledWith("xoxb-bot", expect.any(Number));
    (expect* fetchSlackScopes).toHaveBeenCalledWith("xoxp-user", expect.any(Number));
  });

  (deftest "prints Teams Graph permission hints when present", async () => {
    const plugin = buildPlugin({
      id: "msteams",
      probe: {
        ok: true,
        appId: "app-id",
        graph: {
          ok: true,
          roles: ["ChannelMessage.Read.All", "Files.Read.All"],
        },
      },
    });
    mock:mocked(listChannelPlugins).mockReturnValue([plugin]);
    mock:mocked(getChannelPlugin).mockReturnValue(plugin);

    await channelsCapabilitiesCommand({ channel: "msteams" }, runtime);

    const output = logs.join("\n");
    (expect* output).contains("ChannelMessage.Read.All (channel history)");
    (expect* output).contains("Files.Read.All (files (OneDrive))");
  });
});
