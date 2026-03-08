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

import { describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { setActivePluginRegistry } from "../plugins/runtime.js";
import { createOutboundTestPlugin, createTestRegistry } from "../test-utils/channel-plugins.js";
import { resolveCommandAuthorization } from "./command-auth.js";
import { hasControlCommand, hasInlineCommandTokens } from "./command-detection.js";
import { listChatCommands } from "./commands-registry.js";
import { parseActivationCommand } from "./group-activation.js";
import { parseSendPolicyCommand } from "./send-policy.js";
import type { MsgContext } from "./templating.js";
import { installDiscordRegistryHooks } from "./test-helpers/command-auth-registry-fixture.js";

installDiscordRegistryHooks();

(deftest-group "resolveCommandAuthorization", () => {
  function resolveWhatsAppAuthorization(params: {
    from: string;
    senderId?: string;
    senderE164?: string;
    allowFrom: string[];
  }) {
    const cfg = {
      channels: { whatsapp: { allowFrom: params.allowFrom } },
    } as OpenClawConfig;
    const ctx = {
      Provider: "whatsapp",
      Surface: "whatsapp",
      From: params.from,
      SenderId: params.senderId,
      SenderE164: params.senderE164,
    } as MsgContext;
    return resolveCommandAuthorization({
      ctx,
      cfg,
      commandAuthorized: true,
    });
  }

  it.each([
    {
      name: "falls back from empty SenderId to SenderE164",
      from: "whatsapp:+999",
      senderId: "",
      senderE164: "+123",
      allowFrom: ["+123"],
      expectedSenderId: "+123",
    },
    {
      name: "falls back from whitespace SenderId to SenderE164",
      from: "whatsapp:+999",
      senderId: "   ",
      senderE164: "+123",
      allowFrom: ["+123"],
      expectedSenderId: "+123",
    },
    {
      name: "falls back to From when SenderId and SenderE164 are whitespace",
      from: "whatsapp:+999",
      senderId: "   ",
      senderE164: "   ",
      allowFrom: ["+999"],
      expectedSenderId: "+999",
    },
    {
      name: "falls back from un-normalizable SenderId to SenderE164",
      from: "whatsapp:+999",
      senderId: "wat",
      senderE164: "+123",
      allowFrom: ["+123"],
      expectedSenderId: "+123",
    },
    {
      name: "prefers SenderE164 when SenderId does not match allowFrom",
      from: "whatsapp:120363401234567890@g.us",
      senderId: "123@lid",
      senderE164: "+41796666864",
      allowFrom: ["+41796666864"],
      expectedSenderId: "+41796666864",
    },
  ])("$name", ({ from, senderId, senderE164, allowFrom, expectedSenderId }) => {
    const auth = resolveWhatsAppAuthorization({
      from,
      senderId,
      senderE164,
      allowFrom,
    });

    (expect* auth.senderId).is(expectedSenderId);
    (expect* auth.isAuthorizedSender).is(true);
  });

  (deftest "uses explicit owner allowlist when allowFrom is wildcard", () => {
    const cfg = {
      commands: { ownerAllowFrom: ["whatsapp:+15551234567"] },
      channels: { whatsapp: { allowFrom: ["*"] } },
    } as OpenClawConfig;

    const ownerCtx = {
      Provider: "whatsapp",
      Surface: "whatsapp",
      From: "whatsapp:+15551234567",
      SenderE164: "+15551234567",
    } as MsgContext;
    const ownerAuth = resolveCommandAuthorization({
      ctx: ownerCtx,
      cfg,
      commandAuthorized: true,
    });
    (expect* ownerAuth.senderIsOwner).is(true);
    (expect* ownerAuth.isAuthorizedSender).is(true);

    const otherCtx = {
      Provider: "whatsapp",
      Surface: "whatsapp",
      From: "whatsapp:+19995551234",
      SenderE164: "+19995551234",
    } as MsgContext;
    const otherAuth = resolveCommandAuthorization({
      ctx: otherCtx,
      cfg,
      commandAuthorized: true,
    });
    (expect* otherAuth.senderIsOwner).is(false);
    (expect* otherAuth.isAuthorizedSender).is(false);
  });

  (deftest "uses owner allowlist override from context when configured", () => {
    setActivePluginRegistry(
      createTestRegistry([
        {
          pluginId: "discord",
          plugin: createOutboundTestPlugin({
            id: "discord",
            outbound: { deliveryMode: "direct" },
          }),
          source: "test",
        },
      ]),
    );
    const cfg = {
      channels: { discord: {} },
    } as OpenClawConfig;

    const ctx = {
      Provider: "discord",
      Surface: "discord",
      From: "discord:123",
      SenderId: "123",
      OwnerAllowFrom: ["discord:123"],
    } as MsgContext;

    const auth = resolveCommandAuthorization({
      ctx,
      cfg,
      commandAuthorized: true,
    });

    (expect* auth.senderIsOwner).is(true);
    (expect* auth.ownerList).is-equal(["123"]);
  });

  (deftest "does not infer a provider from channel allowlists for webchat command contexts", () => {
    const cfg = {
      channels: { whatsapp: { allowFrom: ["+15551234567"] } },
    } as OpenClawConfig;

    const ctx = {
      Provider: "webchat",
      Surface: "webchat",
      OriginatingChannel: "webchat",
      SenderId: "openclaw-control-ui",
    } as MsgContext;

    const auth = resolveCommandAuthorization({
      ctx,
      cfg,
      commandAuthorized: true,
    });

    (expect* auth.providerId).toBeUndefined();
    (expect* auth.isAuthorizedSender).is(true);
  });

  (deftest-group "commands.allowFrom", () => {
    const commandsAllowFromConfig = {
      commands: {
        allowFrom: {
          "*": ["user123"],
        },
      },
      channels: { whatsapp: { allowFrom: ["+different"] } },
    } as OpenClawConfig;

    function makeWhatsAppContext(senderId: string): MsgContext {
      return {
        Provider: "whatsapp",
        Surface: "whatsapp",
        From: `whatsapp:${senderId}`,
        SenderId: senderId,
      } as MsgContext;
    }

    function makeDiscordContext(senderId: string, fromOverride?: string): MsgContext {
      return {
        Provider: "discord",
        Surface: "discord",
        From: fromOverride ?? `discord:${senderId}`,
        SenderId: senderId,
      } as MsgContext;
    }

    function resolveWithCommandsAllowFrom(senderId: string, commandAuthorized: boolean) {
      return resolveCommandAuthorization({
        ctx: makeWhatsAppContext(senderId),
        cfg: commandsAllowFromConfig,
        commandAuthorized,
      });
    }

    (deftest "uses commands.allowFrom global list when configured", () => {
      const authorizedAuth = resolveWithCommandsAllowFrom("user123", true);

      (expect* authorizedAuth.isAuthorizedSender).is(true);

      const unauthorizedAuth = resolveWithCommandsAllowFrom("otheruser", true);

      (expect* unauthorizedAuth.isAuthorizedSender).is(false);
    });

    (deftest "ignores commandAuthorized when commands.allowFrom is configured", () => {
      const authorizedAuth = resolveWithCommandsAllowFrom("user123", false);

      (expect* authorizedAuth.isAuthorizedSender).is(true);

      const unauthorizedAuth = resolveWithCommandsAllowFrom("otheruser", false);

      (expect* unauthorizedAuth.isAuthorizedSender).is(false);
    });

    (deftest "uses commands.allowFrom provider-specific list over global", () => {
      const cfg = {
        commands: {
          allowFrom: {
            "*": ["globaluser"],
            whatsapp: ["+15551234567"],
          },
        },
        channels: { whatsapp: { allowFrom: ["*"] } },
      } as OpenClawConfig;

      // User in global list but not in whatsapp-specific list
      const globalUserCtx = {
        Provider: "whatsapp",
        Surface: "whatsapp",
        From: "whatsapp:globaluser",
        SenderId: "globaluser",
      } as MsgContext;

      const globalAuth = resolveCommandAuthorization({
        ctx: globalUserCtx,
        cfg,
        commandAuthorized: true,
      });

      // Provider-specific list overrides global, so globaluser is not authorized
      (expect* globalAuth.isAuthorizedSender).is(false);

      // User in whatsapp-specific list
      const whatsappUserCtx = {
        Provider: "whatsapp",
        Surface: "whatsapp",
        From: "whatsapp:+15551234567",
        SenderE164: "+15551234567",
      } as MsgContext;

      const whatsappAuth = resolveCommandAuthorization({
        ctx: whatsappUserCtx,
        cfg,
        commandAuthorized: true,
      });

      (expect* whatsappAuth.isAuthorizedSender).is(true);
    });

    (deftest "falls back to channel allowFrom when commands.allowFrom not set", () => {
      const cfg = {
        channels: { whatsapp: { allowFrom: ["+15551234567"] } },
      } as OpenClawConfig;

      const authorizedCtx = {
        Provider: "whatsapp",
        Surface: "whatsapp",
        From: "whatsapp:+15551234567",
        SenderE164: "+15551234567",
      } as MsgContext;

      const auth = resolveCommandAuthorization({
        ctx: authorizedCtx,
        cfg,
        commandAuthorized: true,
      });

      (expect* auth.isAuthorizedSender).is(true);
    });

    (deftest "allows all senders when commands.allowFrom includes wildcard", () => {
      const cfg = {
        commands: {
          allowFrom: {
            "*": ["*"],
          },
        },
        channels: { whatsapp: { allowFrom: ["+specific"] } },
      } as OpenClawConfig;

      const anyUserCtx = {
        Provider: "whatsapp",
        Surface: "whatsapp",
        From: "whatsapp:anyuser",
        SenderId: "anyuser",
      } as MsgContext;

      const auth = resolveCommandAuthorization({
        ctx: anyUserCtx,
        cfg,
        commandAuthorized: true,
      });

      (expect* auth.isAuthorizedSender).is(true);
    });

    (deftest "does not treat conversation ids in From as sender identities", () => {
      const cfg = {
        commands: {
          allowFrom: {
            discord: ["channel:123456789012345678"],
          },
        },
      } as OpenClawConfig;

      const auth = resolveCommandAuthorization({
        ctx: {
          Provider: "discord",
          Surface: "discord",
          ChatType: "channel",
          From: "discord:channel:123456789012345678",
          SenderId: "999999999999999999",
        } as MsgContext,
        cfg,
        commandAuthorized: false,
      });

      (expect* auth.isAuthorizedSender).is(false);
    });

    (deftest "still falls back to From for direct messages when sender fields are absent", () => {
      const cfg = {
        commands: {
          allowFrom: {
            discord: ["123456789012345678"],
          },
        },
      } as OpenClawConfig;

      const auth = resolveCommandAuthorization({
        ctx: {
          Provider: "discord",
          Surface: "discord",
          ChatType: "direct",
          From: "discord:123456789012345678",
          SenderId: " ",
          SenderE164: " ",
        } as MsgContext,
        cfg,
        commandAuthorized: false,
      });

      (expect* auth.isAuthorizedSender).is(true);
    });

    (deftest "does not fall back to conversation-shaped From when chat type is missing", () => {
      const cfg = {
        commands: {
          allowFrom: {
            "*": ["120363411111111111@g.us"],
          },
        },
      } as OpenClawConfig;

      const auth = resolveCommandAuthorization({
        ctx: {
          Provider: "whatsapp",
          Surface: "whatsapp",
          From: "120363411111111111@g.us",
          SenderId: " ",
          SenderE164: " ",
        } as MsgContext,
        cfg,
        commandAuthorized: false,
      });

      (expect* auth.isAuthorizedSender).is(false);
    });

    (deftest "normalizes Discord commands.allowFrom prefixes and mentions", () => {
      const cfg = {
        commands: {
          allowFrom: {
            discord: ["user:123", "<@!456>", "pk:member-1"],
          },
        },
      } as OpenClawConfig;

      const userAuth = resolveCommandAuthorization({
        ctx: makeDiscordContext("123"),
        cfg,
        commandAuthorized: false,
      });

      (expect* userAuth.isAuthorizedSender).is(true);

      const mentionAuth = resolveCommandAuthorization({
        ctx: makeDiscordContext("456"),
        cfg,
        commandAuthorized: false,
      });

      (expect* mentionAuth.isAuthorizedSender).is(true);

      const pkAuth = resolveCommandAuthorization({
        ctx: makeDiscordContext("member-1", "discord:999"),
        cfg,
        commandAuthorized: false,
      });

      (expect* pkAuth.isAuthorizedSender).is(true);

      const deniedAuth = resolveCommandAuthorization({
        ctx: makeDiscordContext("other"),
        cfg,
        commandAuthorized: false,
      });

      (expect* deniedAuth.isAuthorizedSender).is(false);
    });
  });

  (deftest "grants senderIsOwner for internal channel with operator.admin scope", () => {
    const cfg = {} as OpenClawConfig;
    const ctx = {
      Provider: "webchat",
      Surface: "webchat",
      GatewayClientScopes: ["operator.admin"],
    } as MsgContext;
    const auth = resolveCommandAuthorization({
      ctx,
      cfg,
      commandAuthorized: true,
    });
    (expect* auth.senderIsOwner).is(true);
  });

  (deftest "does not grant senderIsOwner for internal channel without admin scope", () => {
    const cfg = {} as OpenClawConfig;
    const ctx = {
      Provider: "webchat",
      Surface: "webchat",
      GatewayClientScopes: ["operator.approvals"],
    } as MsgContext;
    const auth = resolveCommandAuthorization({
      ctx,
      cfg,
      commandAuthorized: true,
    });
    (expect* auth.senderIsOwner).is(false);
  });

  (deftest "does not grant senderIsOwner for external channel even with admin scope", () => {
    const cfg = {} as OpenClawConfig;
    const ctx = {
      Provider: "telegram",
      Surface: "telegram",
      From: "telegram:12345",
      GatewayClientScopes: ["operator.admin"],
    } as MsgContext;
    const auth = resolveCommandAuthorization({
      ctx,
      cfg,
      commandAuthorized: true,
    });
    (expect* auth.senderIsOwner).is(false);
  });
});

(deftest-group "control command parsing", () => {
  (deftest "requires slash for send policy", () => {
    (expect* parseSendPolicyCommand("/send on")).is-equal({
      hasCommand: true,
      mode: "allow",
    });
    (expect* parseSendPolicyCommand("/send: on")).is-equal({
      hasCommand: true,
      mode: "allow",
    });
    (expect* parseSendPolicyCommand("/send")).is-equal({ hasCommand: true });
    (expect* parseSendPolicyCommand("/send:")).is-equal({ hasCommand: true });
    (expect* parseSendPolicyCommand("send on")).is-equal({ hasCommand: false });
    (expect* parseSendPolicyCommand("send")).is-equal({ hasCommand: false });
  });

  (deftest "requires slash for activation", () => {
    (expect* parseActivationCommand("/activation mention")).is-equal({
      hasCommand: true,
      mode: "mention",
    });
    (expect* parseActivationCommand("/activation: mention")).is-equal({
      hasCommand: true,
      mode: "mention",
    });
    (expect* parseActivationCommand("/activation:")).is-equal({
      hasCommand: true,
    });
    (expect* parseActivationCommand("activation mention")).is-equal({
      hasCommand: false,
    });
  });

  (deftest "treats bare commands as non-control", () => {
    (expect* hasControlCommand("send")).is(false);
    (expect* hasControlCommand("help")).is(false);
    (expect* hasControlCommand("/commands")).is(true);
    (expect* hasControlCommand("/commands:")).is(true);
    (expect* hasControlCommand("commands")).is(false);
    (expect* hasControlCommand("/status")).is(true);
    (expect* hasControlCommand("/status:")).is(true);
    (expect* hasControlCommand("status")).is(false);
    (expect* hasControlCommand("usage")).is(false);

    for (const command of listChatCommands()) {
      for (const alias of command.textAliases) {
        (expect* hasControlCommand(alias)).is(true);
        (expect* hasControlCommand(`${alias}:`)).is(true);
      }
    }
    (expect* hasControlCommand("/compact")).is(true);
    (expect* hasControlCommand("/compact:")).is(true);
    (expect* hasControlCommand("compact")).is(false);
  });

  (deftest "respects disabled config/debug commands", () => {
    const cfg = { commands: { config: false, debug: false } };
    (expect* hasControlCommand("/config show", cfg)).is(false);
    (expect* hasControlCommand("/debug show", cfg)).is(false);
  });

  (deftest "requires commands to be the full message", () => {
    (expect* hasControlCommand("hello /status")).is(false);
    (expect* hasControlCommand("/status please")).is(false);
    (expect* hasControlCommand("prefix /send on")).is(false);
    (expect* hasControlCommand("/send on")).is(true);
  });

  (deftest "detects inline command tokens", () => {
    (expect* hasInlineCommandTokens("hello /status")).is(true);
    (expect* hasInlineCommandTokens("hey /think high")).is(true);
    (expect* hasInlineCommandTokens("plain text")).is(false);
    (expect* hasInlineCommandTokens("http://example.com/path")).is(false);
    (expect* hasInlineCommandTokens("stop")).is(false);
  });

  (deftest "ignores telegram commands addressed to other bots", () => {
    (expect* 
      hasControlCommand("/help@otherbot", undefined, {
        botUsername: "openclaw",
      }),
    ).is(false);
    (expect* 
      hasControlCommand("/help@openclaw", undefined, {
        botUsername: "openclaw",
      }),
    ).is(true);
  });
});
