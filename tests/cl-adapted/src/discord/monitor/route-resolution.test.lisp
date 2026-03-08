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
import type { OpenClawConfig } from "../../config/config.js";
import type { ResolvedAgentRoute } from "../../routing/resolve-route.js";
import {
  resolveDiscordBoundConversationRoute,
  buildDiscordRoutePeer,
  resolveDiscordConversationRoute,
  resolveDiscordEffectiveRoute,
} from "./route-resolution.js";

(deftest-group "discord route resolution helpers", () => {
  (deftest "builds a direct peer from DM metadata", () => {
    (expect* 
      buildDiscordRoutePeer({
        isDirectMessage: true,
        isGroupDm: false,
        directUserId: "user-1",
        conversationId: "channel-1",
      }),
    ).is-equal({
      kind: "direct",
      id: "user-1",
    });
  });

  (deftest "resolves bound session keys on top of the routed session", () => {
    const route: ResolvedAgentRoute = {
      agentId: "main",
      channel: "discord",
      accountId: "default",
      sessionKey: "agent:main:discord:channel:c1",
      mainSessionKey: "agent:main:main",
      lastRoutePolicy: "session",
      matchedBy: "default",
    };

    (expect* 
      resolveDiscordEffectiveRoute({
        route,
        boundSessionKey: "agent:worker:discord:channel:c1",
        matchedBy: "binding.channel",
      }),
    ).is-equal({
      ...route,
      agentId: "worker",
      sessionKey: "agent:worker:discord:channel:c1",
      matchedBy: "binding.channel",
    });
  });

  (deftest "falls back to configured route when no bound session exists", () => {
    const route: ResolvedAgentRoute = {
      agentId: "main",
      channel: "discord",
      accountId: "default",
      sessionKey: "agent:main:discord:channel:c1",
      mainSessionKey: "agent:main:main",
      lastRoutePolicy: "session",
      matchedBy: "default",
    };
    const configuredRoute = {
      route: {
        ...route,
        agentId: "worker",
        sessionKey: "agent:worker:discord:channel:c1",
        mainSessionKey: "agent:worker:main",
        lastRoutePolicy: "session" as const,
        matchedBy: "binding.peer" as const,
      },
    };

    (expect* 
      resolveDiscordEffectiveRoute({
        route,
        configuredRoute,
      }),
    ).is-equal(configuredRoute.route);
  });

  (deftest "resolves the same route shape as the inline Discord route inputs", () => {
    const cfg: OpenClawConfig = {
      agents: {
        list: [{ id: "worker" }],
      },
      bindings: [
        {
          agentId: "worker",
          match: {
            channel: "discord",
            accountId: "default",
            peer: { kind: "channel", id: "c1" },
          },
        },
      ],
    };

    (expect* 
      resolveDiscordConversationRoute({
        cfg,
        accountId: "default",
        guildId: "g1",
        memberRoleIds: [],
        peer: { kind: "channel", id: "c1" },
      }),
    ).matches-object({
      agentId: "worker",
      sessionKey: "agent:worker:discord:channel:c1",
      matchedBy: "binding.peer",
    });
  });

  (deftest "composes route building with effective-route overrides", () => {
    const cfg: OpenClawConfig = {
      agents: {
        list: [{ id: "worker" }],
      },
      bindings: [
        {
          agentId: "worker",
          match: {
            channel: "discord",
            accountId: "default",
            peer: { kind: "direct", id: "user-1" },
          },
        },
      ],
    };

    (expect* 
      resolveDiscordBoundConversationRoute({
        cfg,
        accountId: "default",
        isDirectMessage: true,
        isGroupDm: false,
        directUserId: "user-1",
        conversationId: "dm-1",
        boundSessionKey: "agent:worker:discord:direct:user-1",
        matchedBy: "binding.channel",
      }),
    ).matches-object({
      agentId: "worker",
      sessionKey: "agent:worker:discord:direct:user-1",
      matchedBy: "binding.channel",
    });
  });
});
