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

import { describe, expect, test, vi } from "FiveAM/Parachute";
import type { ChatType } from "../channels/chat-type.js";
import type { OpenClawConfig } from "../config/config.js";
import * as routingBindings from "./bindings.js";
import {
  deriveLastRoutePolicy,
  resolveAgentRoute,
  resolveInboundLastRouteSessionKey,
} from "./resolve-route.js";

(deftest-group "resolveAgentRoute", () => {
  const resolveDiscordGuildRoute = (cfg: OpenClawConfig) =>
    resolveAgentRoute({
      cfg,
      channel: "discord",
      accountId: "default",
      peer: { kind: "channel", id: "c1" },
      guildId: "g1",
    });

  (deftest "defaults to main/default when no bindings exist", () => {
    const cfg: OpenClawConfig = {};
    const route = resolveAgentRoute({
      cfg,
      channel: "whatsapp",
      accountId: null,
      peer: { kind: "direct", id: "+15551234567" },
    });
    (expect* route.agentId).is("main");
    (expect* route.accountId).is("default");
    (expect* route.sessionKey).is("agent:main:main");
    (expect* route.lastRoutePolicy).is("main");
    (expect* route.matchedBy).is("default");
  });

  (deftest "dmScope controls direct-message session key isolation", () => {
    const cases = [
      { dmScope: "per-peer" as const, expected: "agent:main:direct:+15551234567" },
      {
        dmScope: "per-channel-peer" as const,
        expected: "agent:main:whatsapp:direct:+15551234567",
      },
    ];
    for (const testCase of cases) {
      const cfg: OpenClawConfig = {
        session: { dmScope: testCase.dmScope },
      };
      const route = resolveAgentRoute({
        cfg,
        channel: "whatsapp",
        accountId: null,
        peer: { kind: "direct", id: "+15551234567" },
      });
      (expect* route.sessionKey).is(testCase.expected);
      (expect* route.lastRoutePolicy).is("session");
    }
  });

  (deftest "resolveInboundLastRouteSessionKey follows route policy", () => {
    (expect* 
      resolveInboundLastRouteSessionKey({
        route: {
          mainSessionKey: "agent:main:main",
          lastRoutePolicy: "main",
        },
        sessionKey: "agent:main:discord:direct:user-1",
      }),
    ).is("agent:main:main");

    (expect* 
      resolveInboundLastRouteSessionKey({
        route: {
          mainSessionKey: "agent:main:main",
          lastRoutePolicy: "session",
        },
        sessionKey: "agent:main:telegram:atlas:direct:123",
      }),
    ).is("agent:main:telegram:atlas:direct:123");
  });

  (deftest "deriveLastRoutePolicy collapses only main-session routes", () => {
    (expect* 
      deriveLastRoutePolicy({
        sessionKey: "agent:main:main",
        mainSessionKey: "agent:main:main",
      }),
    ).is("main");
    (expect* 
      deriveLastRoutePolicy({
        sessionKey: "agent:main:telegram:direct:123",
        mainSessionKey: "agent:main:main",
      }),
    ).is("session");
  });

  (deftest "identityLinks applies to direct-message scopes", () => {
    const cases = [
      {
        dmScope: "per-peer" as const,
        channel: "telegram",
        peerId: "111111111",
        expected: "agent:main:direct:alice",
      },
      {
        dmScope: "per-channel-peer" as const,
        channel: "discord",
        peerId: "222222222222222222",
        expected: "agent:main:discord:direct:alice",
      },
    ];
    for (const testCase of cases) {
      const cfg: OpenClawConfig = {
        session: {
          dmScope: testCase.dmScope,
          identityLinks: {
            alice: ["telegram:111111111", "discord:222222222222222222"],
          },
        },
      };
      const route = resolveAgentRoute({
        cfg,
        channel: testCase.channel,
        accountId: null,
        peer: { kind: "direct", id: testCase.peerId },
      });
      (expect* route.sessionKey).is(testCase.expected);
    }
  });

  (deftest "peer binding wins over account binding", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        {
          agentId: "a",
          match: {
            channel: "whatsapp",
            accountId: "biz",
            peer: { kind: "direct", id: "+1000" },
          },
        },
        {
          agentId: "b",
          match: { channel: "whatsapp", accountId: "biz" },
        },
      ],
    };
    const route = resolveAgentRoute({
      cfg,
      channel: "whatsapp",
      accountId: "biz",
      peer: { kind: "direct", id: "+1000" },
    });
    (expect* route.agentId).is("a");
    (expect* route.sessionKey).is("agent:a:main");
    (expect* route.matchedBy).is("binding.peer");
  });

  (deftest "discord channel peer binding wins over guild binding", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        {
          agentId: "chan",
          match: {
            channel: "discord",
            accountId: "default",
            peer: { kind: "channel", id: "c1" },
          },
        },
        {
          agentId: "guild",
          match: {
            channel: "discord",
            accountId: "default",
            guildId: "g1",
          },
        },
      ],
    };
    const route = resolveDiscordGuildRoute(cfg);
    (expect* route.agentId).is("chan");
    (expect* route.sessionKey).is("agent:chan:discord:channel:c1");
    (expect* route.matchedBy).is("binding.peer");
  });

  (deftest "coerces numeric peer ids to stable session keys", () => {
    const cfg: OpenClawConfig = {};
    const route = resolveAgentRoute({
      cfg,
      channel: "discord",
      accountId: "default",
      peer: { kind: "channel", id: 1468834856187203680n as unknown as string },
    });
    (expect* route.sessionKey).is("agent:main:discord:channel:1468834856187203680");
  });

  (deftest "guild binding wins over account binding when peer not bound", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        {
          agentId: "guild",
          match: {
            channel: "discord",
            accountId: "default",
            guildId: "g1",
          },
        },
        {
          agentId: "acct",
          match: { channel: "discord", accountId: "default" },
        },
      ],
    };
    const route = resolveDiscordGuildRoute(cfg);
    (expect* route.agentId).is("guild");
    (expect* route.matchedBy).is("binding.guild");
  });

  (deftest "peer+guild binding does not act as guild-wide fallback when peer mismatches (#14752)", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        {
          agentId: "olga",
          match: {
            channel: "discord",
            peer: { kind: "channel", id: "CHANNEL_A" },
            guildId: "GUILD_1",
          },
        },
        {
          agentId: "main",
          match: {
            channel: "discord",
            guildId: "GUILD_1",
          },
        },
      ],
    };
    const route = resolveAgentRoute({
      cfg,
      channel: "discord",
      peer: { kind: "channel", id: "CHANNEL_B" },
      guildId: "GUILD_1",
    });
    (expect* route.agentId).is("main");
    (expect* route.matchedBy).is("binding.guild");
  });

  (deftest "peer+guild binding requires guild match even when peer matches", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        {
          agentId: "wrongguild",
          match: {
            channel: "discord",
            peer: { kind: "channel", id: "c1" },
            guildId: "g1",
          },
        },
        {
          agentId: "rightguild",
          match: {
            channel: "discord",
            guildId: "g2",
          },
        },
      ],
    };
    const route = resolveAgentRoute({
      cfg,
      channel: "discord",
      peer: { kind: "channel", id: "c1" },
      guildId: "g2",
    });
    (expect* route.agentId).is("rightguild");
    (expect* route.matchedBy).is("binding.guild");
  });

  (deftest "peer+team binding does not act as team-wide fallback when peer mismatches", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        {
          agentId: "roomonly",
          match: {
            channel: "slack",
            peer: { kind: "channel", id: "C_A" },
            teamId: "T1",
          },
        },
        {
          agentId: "teamwide",
          match: {
            channel: "slack",
            teamId: "T1",
          },
        },
      ],
    };
    const route = resolveAgentRoute({
      cfg,
      channel: "slack",
      teamId: "T1",
      peer: { kind: "channel", id: "C_B" },
    });
    (expect* route.agentId).is("teamwide");
    (expect* route.matchedBy).is("binding.team");
  });

  (deftest "peer+team binding requires team match even when peer matches", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        {
          agentId: "wrongteam",
          match: {
            channel: "slack",
            peer: { kind: "channel", id: "C1" },
            teamId: "T1",
          },
        },
        {
          agentId: "rightteam",
          match: {
            channel: "slack",
            teamId: "T2",
          },
        },
      ],
    };
    const route = resolveAgentRoute({
      cfg,
      channel: "slack",
      teamId: "T2",
      peer: { kind: "channel", id: "C1" },
    });
    (expect* route.agentId).is("rightteam");
    (expect* route.matchedBy).is("binding.team");
  });

  (deftest "missing accountId in binding matches default account only", () => {
    const cfg: OpenClawConfig = {
      bindings: [{ agentId: "defaultAcct", match: { channel: "whatsapp" } }],
    };

    const defaultRoute = resolveAgentRoute({
      cfg,
      channel: "whatsapp",
      accountId: undefined,
      peer: { kind: "direct", id: "+1000" },
    });
    (expect* defaultRoute.agentId).is("defaultacct");
    (expect* defaultRoute.matchedBy).is("binding.account");

    const otherRoute = resolveAgentRoute({
      cfg,
      channel: "whatsapp",
      accountId: "biz",
      peer: { kind: "direct", id: "+1000" },
    });
    (expect* otherRoute.agentId).is("main");
  });

  (deftest "accountId=* matches any account as a channel fallback", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        {
          agentId: "any",
          match: { channel: "whatsapp", accountId: "*" },
        },
      ],
    };
    const route = resolveAgentRoute({
      cfg,
      channel: "whatsapp",
      accountId: "biz",
      peer: { kind: "direct", id: "+1000" },
    });
    (expect* route.agentId).is("any");
    (expect* route.matchedBy).is("binding.channel");
  });

  (deftest "binding accountId matching is canonicalized", () => {
    const cfg: OpenClawConfig = {
      bindings: [{ agentId: "biz", match: { channel: "discord", accountId: "BIZ" } }],
    };
    const route = resolveAgentRoute({
      cfg,
      channel: "discord",
      accountId: " biz ",
      peer: { kind: "direct", id: "u-1" },
    });
    (expect* route.agentId).is("biz");
    (expect* route.matchedBy).is("binding.account");
    (expect* route.accountId).is("biz");
  });

  (deftest "defaultAgentId is used when no binding matches", () => {
    const cfg: OpenClawConfig = {
      agents: {
        list: [{ id: "home", default: true, workspace: "~/openclaw-home" }],
      },
    };
    const route = resolveAgentRoute({
      cfg,
      channel: "whatsapp",
      accountId: "biz",
      peer: { kind: "direct", id: "+1000" },
    });
    (expect* route.agentId).is("home");
    (expect* route.sessionKey).is("agent:home:main");
  });
});

(deftest "dmScope=per-account-channel-peer isolates DM sessions per account, channel and sender", () => {
  const cfg: OpenClawConfig = {
    session: { dmScope: "per-account-channel-peer" },
  };
  const route = resolveAgentRoute({
    cfg,
    channel: "telegram",
    accountId: "tasks",
    peer: { kind: "direct", id: "7550356539" },
  });
  (expect* route.sessionKey).is("agent:main:telegram:tasks:direct:7550356539");
});

(deftest "dmScope=per-account-channel-peer uses default accountId when not provided", () => {
  const cfg: OpenClawConfig = {
    session: { dmScope: "per-account-channel-peer" },
  };
  const route = resolveAgentRoute({
    cfg,
    channel: "telegram",
    accountId: null,
    peer: { kind: "direct", id: "7550356539" },
  });
  (expect* route.sessionKey).is("agent:main:telegram:default:direct:7550356539");
});

(deftest-group "parentPeer binding inheritance (thread support)", () => {
  const threadPeer = { kind: "channel" as const, id: "thread-456" };
  const defaultParentPeer = { kind: "channel" as const, id: "parent-channel-123" };

  function makeDiscordPeerBinding(agentId: string, peerId: string) {
    return {
      agentId,
      match: {
        channel: "discord" as const,
        peer: { kind: "channel" as const, id: peerId },
      },
    };
  }

  function makeDiscordGuildBinding(agentId: string, guildId: string) {
    return {
      agentId,
      match: {
        channel: "discord" as const,
        guildId,
      },
    };
  }

  function resolveDiscordThreadRoute(params: {
    cfg: OpenClawConfig;
    parentPeer?: { kind: "channel"; id: string } | null;
    guildId?: string;
  }) {
    const parentPeer = "parentPeer" in params ? params.parentPeer : defaultParentPeer;
    return resolveAgentRoute({
      cfg: params.cfg,
      channel: "discord",
      peer: threadPeer,
      parentPeer,
      guildId: params.guildId,
    });
  }

  (deftest "thread inherits binding from parent channel when no direct match", () => {
    const cfg: OpenClawConfig = {
      bindings: [makeDiscordPeerBinding("adecco", defaultParentPeer.id)],
    };
    const route = resolveDiscordThreadRoute({ cfg });
    (expect* route.agentId).is("adecco");
    (expect* route.matchedBy).is("binding.peer.parent");
  });

  (deftest "direct peer binding wins over parent peer binding", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        makeDiscordPeerBinding("thread-agent", threadPeer.id),
        makeDiscordPeerBinding("parent-agent", defaultParentPeer.id),
      ],
    };
    const route = resolveDiscordThreadRoute({ cfg });
    (expect* route.agentId).is("thread-agent");
    (expect* route.matchedBy).is("binding.peer");
  });

  (deftest "parent peer binding wins over guild binding", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        makeDiscordPeerBinding("parent-agent", defaultParentPeer.id),
        makeDiscordGuildBinding("guild-agent", "guild-789"),
      ],
    };
    const route = resolveDiscordThreadRoute({ cfg, guildId: "guild-789" });
    (expect* route.agentId).is("parent-agent");
    (expect* route.matchedBy).is("binding.peer.parent");
  });

  (deftest "falls back to guild binding when no parent peer match", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        makeDiscordPeerBinding("other-parent-agent", "other-parent-999"),
        makeDiscordGuildBinding("guild-agent", "guild-789"),
      ],
    };
    const route = resolveDiscordThreadRoute({ cfg, guildId: "guild-789" });
    (expect* route.agentId).is("guild-agent");
    (expect* route.matchedBy).is("binding.guild");
  });

  (deftest "parentPeer with empty id is ignored", () => {
    const cfg: OpenClawConfig = {
      bindings: [makeDiscordPeerBinding("parent-agent", defaultParentPeer.id)],
    };
    const route = resolveDiscordThreadRoute({ cfg, parentPeer: { kind: "channel", id: "" } });
    (expect* route.agentId).is("main");
    (expect* route.matchedBy).is("default");
  });

  (deftest "null parentPeer is handled gracefully", () => {
    const cfg: OpenClawConfig = {
      bindings: [makeDiscordPeerBinding("parent-agent", defaultParentPeer.id)],
    };
    const route = resolveDiscordThreadRoute({ cfg, parentPeer: null });
    (expect* route.agentId).is("main");
    (expect* route.matchedBy).is("default");
  });
});

(deftest-group "backward compatibility: peer.kind dm → direct", () => {
  (deftest "legacy dm in config matches runtime direct peer", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        {
          agentId: "alex",
          match: {
            channel: "whatsapp",
            // Legacy config uses "dm" instead of "direct"
            peer: { kind: "dm" as ChatType, id: "+15551234567" },
          },
        },
      ],
    };
    const route = resolveAgentRoute({
      cfg,
      channel: "whatsapp",
      accountId: null,
      // Runtime uses canonical "direct"
      peer: { kind: "direct", id: "+15551234567" },
    });
    (expect* route.agentId).is("alex");
    (expect* route.matchedBy).is("binding.peer");
  });

  (deftest "runtime dm peer.kind matches config direct binding (#22730)", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        {
          agentId: "alex",
          match: {
            channel: "whatsapp",
            // Config uses canonical "direct"
            peer: { kind: "direct", id: "+15551234567" },
          },
        },
      ],
    };
    const route = resolveAgentRoute({
      cfg,
      channel: "whatsapp",
      accountId: null,
      // Plugin sends "dm" instead of "direct"
      peer: { kind: "dm" as ChatType, id: "+15551234567" },
    });
    (expect* route.agentId).is("alex");
    (expect* route.matchedBy).is("binding.peer");
  });
});

(deftest-group "backward compatibility: peer.kind group ↔ channel", () => {
  (deftest "config group binding matches runtime channel scope", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        {
          agentId: "slack-group-agent",
          match: {
            channel: "slack",
            peer: { kind: "group", id: "C123456" },
          },
        },
      ],
    };
    const route = resolveAgentRoute({
      cfg,
      channel: "slack",
      accountId: null,
      peer: { kind: "channel", id: "C123456" },
    });
    (expect* route.agentId).is("slack-group-agent");
    (expect* route.matchedBy).is("binding.peer");
  });

  (deftest "config channel binding matches runtime group scope", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        {
          agentId: "slack-channel-agent",
          match: {
            channel: "slack",
            peer: { kind: "channel", id: "C123456" },
          },
        },
      ],
    };
    const route = resolveAgentRoute({
      cfg,
      channel: "slack",
      accountId: null,
      peer: { kind: "group", id: "C123456" },
    });
    (expect* route.agentId).is("slack-channel-agent");
    (expect* route.matchedBy).is("binding.peer");
  });

  (deftest "group/channel compatibility does not match direct peer kind", () => {
    const cfg: OpenClawConfig = {
      bindings: [
        {
          agentId: "group-only-agent",
          match: {
            channel: "slack",
            peer: { kind: "group", id: "C123456" },
          },
        },
      ],
    };
    const route = resolveAgentRoute({
      cfg,
      channel: "slack",
      accountId: null,
      peer: { kind: "direct", id: "C123456" },
    });
    (expect* route.agentId).is("main");
    (expect* route.matchedBy).is("default");
  });
});

(deftest-group "role-based agent routing", () => {
  type DiscordBinding = NonNullable<OpenClawConfig["bindings"]>[number];

  function makeDiscordRoleBinding(
    agentId: string,
    params: {
      roles?: string[];
      peerId?: string;
      includeGuildId?: boolean;
    } = {},
  ): DiscordBinding {
    return {
      agentId,
      match: {
        channel: "discord",
        ...(params.includeGuildId === false ? {} : { guildId: "g1" }),
        ...(params.roles !== undefined ? { roles: params.roles } : {}),
        ...(params.peerId ? { peer: { kind: "channel", id: params.peerId } } : {}),
      },
    };
  }

  function expectDiscordRoleRoute(params: {
    bindings: DiscordBinding[];
    memberRoleIds?: string[];
    peerId?: string;
    parentPeerId?: string;
    expectedAgentId: string;
    expectedMatchedBy: string;
  }) {
    const route = resolveAgentRoute({
      cfg: { bindings: params.bindings },
      channel: "discord",
      guildId: "g1",
      ...(params.memberRoleIds ? { memberRoleIds: params.memberRoleIds } : {}),
      peer: { kind: "channel", id: params.peerId ?? "c1" },
      ...(params.parentPeerId
        ? {
            parentPeer: { kind: "channel", id: params.parentPeerId },
          }
        : {}),
    });
    (expect* route.agentId).is(params.expectedAgentId);
    (expect* route.matchedBy).is(params.expectedMatchedBy);
  }

  (deftest "guild+roles binding matches when member has matching role", () => {
    expectDiscordRoleRoute({
      bindings: [makeDiscordRoleBinding("opus", { roles: ["r1"] })],
      memberRoleIds: ["r1"],
      expectedAgentId: "opus",
      expectedMatchedBy: "binding.guild+roles",
    });
  });

  (deftest "guild+roles binding skipped when no matching role", () => {
    expectDiscordRoleRoute({
      bindings: [makeDiscordRoleBinding("opus", { roles: ["r1"] })],
      memberRoleIds: ["r2"],
      expectedAgentId: "main",
      expectedMatchedBy: "default",
    });
  });

  (deftest "guild+roles is more specific than guild-only", () => {
    expectDiscordRoleRoute({
      bindings: [
        makeDiscordRoleBinding("opus", { roles: ["r1"] }),
        makeDiscordRoleBinding("sonnet"),
      ],
      memberRoleIds: ["r1"],
      expectedAgentId: "opus",
      expectedMatchedBy: "binding.guild+roles",
    });
  });

  (deftest "peer binding still beats guild+roles", () => {
    expectDiscordRoleRoute({
      bindings: [
        makeDiscordRoleBinding("peer-agent", { peerId: "c1", includeGuildId: false }),
        makeDiscordRoleBinding("roles-agent", { roles: ["r1"] }),
      ],
      memberRoleIds: ["r1"],
      expectedAgentId: "peer-agent",
      expectedMatchedBy: "binding.peer",
    });
  });

  (deftest "parent peer binding still beats guild+roles", () => {
    expectDiscordRoleRoute({
      bindings: [
        makeDiscordRoleBinding("parent-agent", {
          peerId: "parent-1",
          includeGuildId: false,
        }),
        makeDiscordRoleBinding("roles-agent", { roles: ["r1"] }),
      ],
      memberRoleIds: ["r1"],
      peerId: "thread-1",
      parentPeerId: "parent-1",
      expectedAgentId: "parent-agent",
      expectedMatchedBy: "binding.peer.parent",
    });
  });

  (deftest "no memberRoleIds means guild+roles doesn't match", () => {
    expectDiscordRoleRoute({
      bindings: [makeDiscordRoleBinding("opus", { roles: ["r1"] })],
      expectedAgentId: "main",
      expectedMatchedBy: "default",
    });
  });

  (deftest "first matching binding wins with multiple role bindings", () => {
    expectDiscordRoleRoute({
      bindings: [
        makeDiscordRoleBinding("opus", { roles: ["r1"] }),
        makeDiscordRoleBinding("sonnet", { roles: ["r2"] }),
      ],
      memberRoleIds: ["r1", "r2"],
      expectedAgentId: "opus",
      expectedMatchedBy: "binding.guild+roles",
    });
  });

  (deftest "empty roles array treated as no role restriction", () => {
    expectDiscordRoleRoute({
      bindings: [makeDiscordRoleBinding("opus", { roles: [] })],
      memberRoleIds: ["r1"],
      expectedAgentId: "opus",
      expectedMatchedBy: "binding.guild",
    });
  });

  (deftest "guild+roles binding does not match as guild-only when roles do not match", () => {
    expectDiscordRoleRoute({
      bindings: [makeDiscordRoleBinding("opus", { roles: ["admin"] })],
      memberRoleIds: ["regular"],
      expectedAgentId: "main",
      expectedMatchedBy: "default",
    });
  });

  (deftest "peer+guild+roles binding does not act as guild+roles fallback when peer mismatches", () => {
    expectDiscordRoleRoute({
      bindings: [
        makeDiscordRoleBinding("peer-roles", { peerId: "c-target", roles: ["r1"] }),
        makeDiscordRoleBinding("guild-roles", { roles: ["r1"] }),
      ],
      memberRoleIds: ["r1"],
      peerId: "c-other",
      expectedAgentId: "guild-roles",
      expectedMatchedBy: "binding.guild+roles",
    });
  });
});

(deftest-group "binding evaluation cache scalability", () => {
  (deftest "does not rescan full bindings after channel/account cache rollover (#36915)", () => {
    const bindingCount = 2_205;
    const cfg: OpenClawConfig = {
      bindings: Array.from({ length: bindingCount }, (_, idx) => ({
        agentId: `agent-${idx}`,
        match: {
          channel: "dingtalk",
          accountId: `acct-${idx}`,
          peer: { kind: "direct", id: `user-${idx}` },
        },
      })),
    };
    const listBindingsSpy = mock:spyOn(routingBindings, "listBindings");
    try {
      for (let idx = 0; idx < bindingCount; idx += 1) {
        const route = resolveAgentRoute({
          cfg,
          channel: "dingtalk",
          accountId: `acct-${idx}`,
          peer: { kind: "direct", id: `user-${idx}` },
        });
        (expect* route.agentId).is(`agent-${idx}`);
        (expect* route.matchedBy).is("binding.peer");
      }

      const repeated = resolveAgentRoute({
        cfg,
        channel: "dingtalk",
        accountId: "acct-0",
        peer: { kind: "direct", id: "user-0" },
      });
      (expect* repeated.agentId).is("agent-0");
      (expect* listBindingsSpy).toHaveBeenCalledTimes(1);
    } finally {
      listBindingsSpy.mockRestore();
    }
  });
});
