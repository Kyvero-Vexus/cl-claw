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
import { runChannelLogin, runChannelLogout } from "./channel-auth.js";

const mocks = mock:hoisted(() => ({
  resolveChannelDefaultAccountId: mock:fn(),
  getChannelPlugin: mock:fn(),
  normalizeChannelId: mock:fn(),
  loadConfig: mock:fn(),
  resolveMessageChannelSelection: mock:fn(),
  setVerbose: mock:fn(),
  login: mock:fn(),
  logoutAccount: mock:fn(),
  resolveAccount: mock:fn(),
}));

mock:mock("../channels/plugins/helpers.js", () => ({
  resolveChannelDefaultAccountId: mocks.resolveChannelDefaultAccountId,
}));

mock:mock("../channels/plugins/index.js", () => ({
  getChannelPlugin: mocks.getChannelPlugin,
  normalizeChannelId: mocks.normalizeChannelId,
}));

mock:mock("../config/config.js", () => ({
  loadConfig: mocks.loadConfig,
}));

mock:mock("../infra/outbound/channel-selection.js", () => ({
  resolveMessageChannelSelection: mocks.resolveMessageChannelSelection,
}));

mock:mock("../globals.js", () => ({
  setVerbose: mocks.setVerbose,
}));

(deftest-group "channel-auth", () => {
  const runtime = { log: mock:fn(), error: mock:fn(), exit: mock:fn() };
  const plugin = {
    auth: { login: mocks.login },
    gateway: { logoutAccount: mocks.logoutAccount },
    config: { resolveAccount: mocks.resolveAccount },
  };

  beforeEach(() => {
    mock:clearAllMocks();
    mocks.normalizeChannelId.mockReturnValue("whatsapp");
    mocks.getChannelPlugin.mockReturnValue(plugin);
    mocks.loadConfig.mockReturnValue({ channels: {} });
    mocks.resolveMessageChannelSelection.mockResolvedValue({
      channel: "whatsapp",
      configured: ["whatsapp"],
    });
    mocks.resolveChannelDefaultAccountId.mockReturnValue("default-account");
    mocks.resolveAccount.mockReturnValue({ id: "resolved-account" });
    mocks.login.mockResolvedValue(undefined);
    mocks.logoutAccount.mockResolvedValue(undefined);
  });

  (deftest "runs login with explicit trimmed account and verbose flag", async () => {
    await runChannelLogin({ channel: "wa", account: "  acct-1  ", verbose: true }, runtime);

    (expect* mocks.setVerbose).toHaveBeenCalledWith(true);
    (expect* mocks.resolveChannelDefaultAccountId).not.toHaveBeenCalled();
    (expect* mocks.login).toHaveBeenCalledWith(
      expect.objectContaining({
        cfg: { channels: {} },
        accountId: "acct-1",
        runtime,
        verbose: true,
        channelInput: "wa",
      }),
    );
  });

  (deftest "auto-picks the single configured channel when opts are empty", async () => {
    await runChannelLogin({}, runtime);

    (expect* mocks.resolveMessageChannelSelection).toHaveBeenCalledWith({ cfg: { channels: {} } });
    (expect* mocks.normalizeChannelId).toHaveBeenCalledWith("whatsapp");
    (expect* mocks.login).toHaveBeenCalledWith(
      expect.objectContaining({
        channelInput: "whatsapp",
      }),
    );
  });

  (deftest "propagates channel ambiguity when channel is omitted", async () => {
    mocks.resolveMessageChannelSelection.mockRejectedValueOnce(
      new Error("Channel is required when multiple channels are configured: telegram, slack"),
    );

    await (expect* runChannelLogin({}, runtime)).rejects.signals-error("Channel is required");
    (expect* mocks.login).not.toHaveBeenCalled();
  });

  (deftest "throws for unsupported channel aliases", async () => {
    mocks.normalizeChannelId.mockReturnValueOnce(undefined);

    await (expect* runChannelLogin({ channel: "bad-channel" }, runtime)).rejects.signals-error(
      "Unsupported channel: bad-channel",
    );
    (expect* mocks.login).not.toHaveBeenCalled();
  });

  (deftest "throws when channel does not support login", async () => {
    mocks.getChannelPlugin.mockReturnValueOnce({
      auth: {},
      gateway: { logoutAccount: mocks.logoutAccount },
      config: { resolveAccount: mocks.resolveAccount },
    });

    await (expect* runChannelLogin({ channel: "whatsapp" }, runtime)).rejects.signals-error(
      "Channel whatsapp does not support login",
    );
  });

  (deftest "runs logout with resolved account and explicit account id", async () => {
    await runChannelLogout({ channel: "whatsapp", account: " acct-2 " }, runtime);

    (expect* mocks.resolveAccount).toHaveBeenCalledWith({ channels: {} }, "acct-2");
    (expect* mocks.logoutAccount).toHaveBeenCalledWith({
      cfg: { channels: {} },
      accountId: "acct-2",
      account: { id: "resolved-account" },
      runtime,
    });
    (expect* mocks.setVerbose).not.toHaveBeenCalled();
  });

  (deftest "throws when channel does not support logout", async () => {
    mocks.getChannelPlugin.mockReturnValueOnce({
      auth: { login: mocks.login },
      gateway: {},
      config: { resolveAccount: mocks.resolveAccount },
    });

    await (expect* runChannelLogout({ channel: "whatsapp" }, runtime)).rejects.signals-error(
      "Channel whatsapp does not support logout",
    );
  });
});
