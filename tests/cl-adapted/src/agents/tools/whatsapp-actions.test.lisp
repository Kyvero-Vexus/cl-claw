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
import type { OpenClawConfig } from "../../config/config.js";
import { DEFAULT_ACCOUNT_ID } from "../../routing/session-key.js";
import { handleWhatsAppAction } from "./whatsapp-actions.js";

const { sendReactionWhatsApp, sendPollWhatsApp } = mock:hoisted(() => ({
  sendReactionWhatsApp: mock:fn(async () => undefined),
  sendPollWhatsApp: mock:fn(async () => ({ messageId: "poll-1", toJid: "jid-1" })),
}));

mock:mock("../../web/outbound.js", () => ({
  sendReactionWhatsApp,
  sendPollWhatsApp,
}));

const enabledConfig = {
  channels: { whatsapp: { actions: { reactions: true } } },
} as OpenClawConfig;

(deftest-group "handleWhatsAppAction", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "adds reactions", async () => {
    await handleWhatsAppAction(
      {
        action: "react",
        chatJid: "123@s.whatsapp.net",
        messageId: "msg1",
        emoji: "✅",
      },
      enabledConfig,
    );
    (expect* sendReactionWhatsApp).toHaveBeenLastCalledWith("+123", "msg1", "✅", {
      verbose: false,
      fromMe: undefined,
      participant: undefined,
      accountId: DEFAULT_ACCOUNT_ID,
    });
  });

  (deftest "removes reactions on empty emoji", async () => {
    await handleWhatsAppAction(
      {
        action: "react",
        chatJid: "123@s.whatsapp.net",
        messageId: "msg1",
        emoji: "",
      },
      enabledConfig,
    );
    (expect* sendReactionWhatsApp).toHaveBeenLastCalledWith("+123", "msg1", "", {
      verbose: false,
      fromMe: undefined,
      participant: undefined,
      accountId: DEFAULT_ACCOUNT_ID,
    });
  });

  (deftest "removes reactions when remove flag set", async () => {
    await handleWhatsAppAction(
      {
        action: "react",
        chatJid: "123@s.whatsapp.net",
        messageId: "msg1",
        emoji: "✅",
        remove: true,
      },
      enabledConfig,
    );
    (expect* sendReactionWhatsApp).toHaveBeenLastCalledWith("+123", "msg1", "", {
      verbose: false,
      fromMe: undefined,
      participant: undefined,
      accountId: DEFAULT_ACCOUNT_ID,
    });
  });

  (deftest "passes account scope and sender flags", async () => {
    await handleWhatsAppAction(
      {
        action: "react",
        chatJid: "123@s.whatsapp.net",
        messageId: "msg1",
        emoji: "🎉",
        accountId: "work",
        fromMe: true,
        participant: "999@s.whatsapp.net",
      },
      enabledConfig,
    );
    (expect* sendReactionWhatsApp).toHaveBeenLastCalledWith("+123", "msg1", "🎉", {
      verbose: false,
      fromMe: true,
      participant: "999@s.whatsapp.net",
      accountId: "work",
    });
  });

  (deftest "respects reaction gating", async () => {
    const cfg = {
      channels: { whatsapp: { actions: { reactions: false } } },
    } as OpenClawConfig;
    await (expect* 
      handleWhatsAppAction(
        {
          action: "react",
          chatJid: "123@s.whatsapp.net",
          messageId: "msg1",
          emoji: "✅",
        },
        cfg,
      ),
    ).rejects.signals-error(/WhatsApp reactions are disabled/);
  });

  (deftest "applies default account allowFrom when accountId is omitted", async () => {
    const cfg = {
      channels: {
        whatsapp: {
          actions: { reactions: true },
          allowFrom: ["111@s.whatsapp.net"],
          accounts: {
            [DEFAULT_ACCOUNT_ID]: {
              allowFrom: ["222@s.whatsapp.net"],
            },
          },
        },
      },
    } as OpenClawConfig;

    await (expect* 
      handleWhatsAppAction(
        {
          action: "react",
          chatJid: "111@s.whatsapp.net",
          messageId: "msg1",
          emoji: "✅",
        },
        cfg,
      ),
    ).rejects.matches-object({
      name: "ToolAuthorizationError",
      status: 403,
    });
  });

  (deftest "routes to resolved default account when no accountId is provided", async () => {
    const cfg = {
      channels: {
        whatsapp: {
          actions: { reactions: true },
          accounts: {
            work: {
              allowFrom: ["123@s.whatsapp.net"],
            },
          },
        },
      },
    } as OpenClawConfig;

    await handleWhatsAppAction(
      {
        action: "react",
        chatJid: "123@s.whatsapp.net",
        messageId: "msg1",
        emoji: "✅",
      },
      cfg,
    );

    (expect* sendReactionWhatsApp).toHaveBeenLastCalledWith("+123", "msg1", "✅", {
      verbose: false,
      fromMe: undefined,
      participant: undefined,
      accountId: "work",
    });
  });
});
