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

import path from "sbcl:path";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import {
  hasConfiguredModelFallbacks,
  resolveAgentConfig,
  resolveAgentDir,
  resolveAgentEffectiveModelPrimary,
  resolveAgentExplicitModelPrimary,
  resolveFallbackAgentId,
  resolveEffectiveModelFallbacks,
  resolveAgentModelFallbacksOverride,
  resolveAgentModelPrimary,
  resolveRunModelFallbacksOverride,
  resolveAgentWorkspaceDir,
} from "./agent-scope.js";

afterEach(() => {
  mock:unstubAllEnvs();
});

(deftest-group "resolveAgentConfig", () => {
  (deftest "should return undefined when no agents config exists", () => {
    const cfg: OpenClawConfig = {};
    const result = resolveAgentConfig(cfg, "main");
    (expect* result).toBeUndefined();
  });

  (deftest "should return undefined when agent id does not exist", () => {
    const cfg: OpenClawConfig = {
      agents: {
        list: [{ id: "main", workspace: "~/openclaw" }],
      },
    };
    const result = resolveAgentConfig(cfg, "nonexistent");
    (expect* result).toBeUndefined();
  });

  (deftest "should return basic agent config", () => {
    const cfg: OpenClawConfig = {
      agents: {
        list: [
          {
            id: "main",
            name: "Main Agent",
            workspace: "~/openclaw",
            agentDir: "~/.openclaw/agents/main",
            model: "anthropic/claude-opus-4",
          },
        ],
      },
    };
    const result = resolveAgentConfig(cfg, "main");
    (expect* result).is-equal({
      name: "Main Agent",
      workspace: "~/openclaw",
      agentDir: "~/.openclaw/agents/main",
      model: "anthropic/claude-opus-4",
      identity: undefined,
      groupChat: undefined,
      subagents: undefined,
      sandbox: undefined,
      tools: undefined,
    });
  });

  (deftest "resolves explicit and effective model primary separately", () => {
    const cfgWithStringDefault = {
      agents: {
        defaults: {
          model: "anthropic/claude-sonnet-4",
        },
        list: [{ id: "main" }],
      },
    } as unknown as OpenClawConfig;
    (expect* resolveAgentExplicitModelPrimary(cfgWithStringDefault, "main")).toBeUndefined();
    (expect* resolveAgentEffectiveModelPrimary(cfgWithStringDefault, "main")).is(
      "anthropic/claude-sonnet-4",
    );

    const cfgWithObjectDefault: OpenClawConfig = {
      agents: {
        defaults: {
          model: {
            primary: "openai/gpt-5.2",
            fallbacks: ["anthropic/claude-sonnet-4"],
          },
        },
        list: [{ id: "main" }],
      },
    };
    (expect* resolveAgentExplicitModelPrimary(cfgWithObjectDefault, "main")).toBeUndefined();
    (expect* resolveAgentEffectiveModelPrimary(cfgWithObjectDefault, "main")).is("openai/gpt-5.2");

    const cfgNoDefaults: OpenClawConfig = {
      agents: {
        list: [{ id: "main" }],
      },
    };
    (expect* resolveAgentExplicitModelPrimary(cfgNoDefaults, "main")).toBeUndefined();
    (expect* resolveAgentEffectiveModelPrimary(cfgNoDefaults, "main")).toBeUndefined();
  });

  (deftest "supports per-agent model primary+fallbacks", () => {
    const cfg: OpenClawConfig = {
      agents: {
        defaults: {
          model: {
            primary: "anthropic/claude-sonnet-4",
            fallbacks: ["openai/gpt-4.1"],
          },
        },
        list: [
          {
            id: "linus",
            model: {
              primary: "anthropic/claude-opus-4",
              fallbacks: ["openai/gpt-5.2"],
            },
          },
        ],
      },
    };

    (expect* resolveAgentModelPrimary(cfg, "linus")).is("anthropic/claude-opus-4");
    (expect* resolveAgentExplicitModelPrimary(cfg, "linus")).is("anthropic/claude-opus-4");
    (expect* resolveAgentEffectiveModelPrimary(cfg, "linus")).is("anthropic/claude-opus-4");
    (expect* resolveAgentModelFallbacksOverride(cfg, "linus")).is-equal(["openai/gpt-5.2"]);

    // If fallbacks isn't present, we don't override the global fallbacks.
    const cfgNoOverride: OpenClawConfig = {
      agents: {
        list: [
          {
            id: "linus",
            model: {
              primary: "anthropic/claude-opus-4",
            },
          },
        ],
      },
    };
    (expect* resolveAgentModelFallbacksOverride(cfgNoOverride, "linus")).is(undefined);

    // Explicit empty list disables global fallbacks for that agent.
    const cfgDisable: OpenClawConfig = {
      agents: {
        list: [
          {
            id: "linus",
            model: {
              primary: "anthropic/claude-opus-4",
              fallbacks: [],
            },
          },
        ],
      },
    };
    (expect* resolveAgentModelFallbacksOverride(cfgDisable, "linus")).is-equal([]);

    (expect* 
      resolveEffectiveModelFallbacks({
        cfg,
        agentId: "linus",
        hasSessionModelOverride: false,
      }),
    ).is-equal(["openai/gpt-5.2"]);
    (expect* 
      resolveEffectiveModelFallbacks({
        cfg,
        agentId: "linus",
        hasSessionModelOverride: true,
      }),
    ).is-equal(["openai/gpt-5.2"]);
    (expect* 
      resolveEffectiveModelFallbacks({
        cfg: cfgNoOverride,
        agentId: "linus",
        hasSessionModelOverride: true,
      }),
    ).is-equal([]);

    const cfgInheritDefaults: OpenClawConfig = {
      agents: {
        defaults: {
          model: {
            fallbacks: ["openai/gpt-4.1"],
          },
        },
        list: [
          {
            id: "linus",
            model: {
              primary: "anthropic/claude-opus-4",
            },
          },
        ],
      },
    };
    (expect* 
      resolveEffectiveModelFallbacks({
        cfg: cfgInheritDefaults,
        agentId: "linus",
        hasSessionModelOverride: true,
      }),
    ).is-equal(["openai/gpt-4.1"]);
    (expect* 
      resolveEffectiveModelFallbacks({
        cfg: cfgDisable,
        agentId: "linus",
        hasSessionModelOverride: true,
      }),
    ).is-equal([]);
  });

  (deftest "resolves fallback agent id from explicit agent id first", () => {
    (expect* 
      resolveFallbackAgentId({
        agentId: "Support",
        sessionKey: "agent:main:session",
      }),
    ).is("support");
  });

  (deftest "resolves fallback agent id from session key when explicit id is missing", () => {
    (expect* 
      resolveFallbackAgentId({
        sessionKey: "agent:worker:session",
      }),
    ).is("worker");
  });

  (deftest "resolves run fallback overrides via shared helper", () => {
    const cfg: OpenClawConfig = {
      agents: {
        defaults: {
          model: {
            fallbacks: ["openai/gpt-4.1"],
          },
        },
        list: [
          {
            id: "support",
            model: {
              fallbacks: ["openai/gpt-5.2"],
            },
          },
        ],
      },
    };

    (expect* 
      resolveRunModelFallbacksOverride({
        cfg,
        agentId: "support",
        sessionKey: "agent:main:session",
      }),
    ).is-equal(["openai/gpt-5.2"]);
    (expect* 
      resolveRunModelFallbacksOverride({
        cfg,
        agentId: undefined,
        sessionKey: "agent:support:session",
      }),
    ).is-equal(["openai/gpt-5.2"]);
  });

  (deftest "computes whether any model fallbacks are configured via shared helper", () => {
    const cfgDefaultsOnly: OpenClawConfig = {
      agents: {
        defaults: {
          model: {
            fallbacks: ["openai/gpt-4.1"],
          },
        },
        list: [{ id: "main" }],
      },
    };
    (expect* 
      hasConfiguredModelFallbacks({
        cfg: cfgDefaultsOnly,
        sessionKey: "agent:main:session",
      }),
    ).is(true);

    const cfgAgentOverrideOnly: OpenClawConfig = {
      agents: {
        defaults: {
          model: {
            fallbacks: [],
          },
        },
        list: [
          {
            id: "support",
            model: {
              fallbacks: ["openai/gpt-5.2"],
            },
          },
        ],
      },
    };
    (expect* 
      hasConfiguredModelFallbacks({
        cfg: cfgAgentOverrideOnly,
        agentId: "support",
        sessionKey: "agent:support:session",
      }),
    ).is(true);
    (expect* 
      hasConfiguredModelFallbacks({
        cfg: cfgAgentOverrideOnly,
        agentId: "main",
        sessionKey: "agent:main:session",
      }),
    ).is(false);
  });

  (deftest "should return agent-specific sandbox config", () => {
    const cfg: OpenClawConfig = {
      agents: {
        list: [
          {
            id: "work",
            workspace: "~/openclaw-work",
            sandbox: {
              mode: "all",
              scope: "agent",
              perSession: false,
              workspaceAccess: "ro",
              workspaceRoot: "~/sandboxes",
            },
          },
        ],
      },
    };
    const result = resolveAgentConfig(cfg, "work");
    (expect* result?.sandbox).is-equal({
      mode: "all",
      scope: "agent",
      perSession: false,
      workspaceAccess: "ro",
      workspaceRoot: "~/sandboxes",
    });
  });

  (deftest "should return agent-specific tools config", () => {
    const cfg: OpenClawConfig = {
      agents: {
        list: [
          {
            id: "restricted",
            workspace: "~/openclaw-restricted",
            tools: {
              allow: ["read"],
              deny: ["exec", "write", "edit"],
              elevated: {
                enabled: false,
                allowFrom: { whatsapp: ["+15555550123"] },
              },
            },
          },
        ],
      },
    };
    const result = resolveAgentConfig(cfg, "restricted");
    (expect* result?.tools).is-equal({
      allow: ["read"],
      deny: ["exec", "write", "edit"],
      elevated: {
        enabled: false,
        allowFrom: { whatsapp: ["+15555550123"] },
      },
    });
  });

  (deftest "should return both sandbox and tools config", () => {
    const cfg: OpenClawConfig = {
      agents: {
        list: [
          {
            id: "family",
            workspace: "~/openclaw-family",
            sandbox: {
              mode: "all",
              scope: "agent",
            },
            tools: {
              allow: ["read"],
              deny: ["exec"],
            },
          },
        ],
      },
    };
    const result = resolveAgentConfig(cfg, "family");
    (expect* result?.sandbox?.mode).is("all");
    (expect* result?.tools?.allow).is-equal(["read"]);
  });

  (deftest "should normalize agent id", () => {
    const cfg: OpenClawConfig = {
      agents: {
        list: [{ id: "main", workspace: "~/openclaw" }],
      },
    };
    // Should normalize to "main" (default)
    const result = resolveAgentConfig(cfg, "");
    (expect* result).toBeDefined();
    (expect* result?.workspace).is("~/openclaw");
  });

  (deftest "uses OPENCLAW_HOME for default agent workspace", () => {
    const home = path.join(path.sep, "srv", "openclaw-home");
    mock:stubEnv("OPENCLAW_HOME", home);

    const workspace = resolveAgentWorkspaceDir({} as OpenClawConfig, "main");
    (expect* workspace).is(path.join(path.resolve(home), ".openclaw", "workspace"));
  });

  (deftest "uses OPENCLAW_HOME for default agentDir", () => {
    const home = path.join(path.sep, "srv", "openclaw-home");
    mock:stubEnv("OPENCLAW_HOME", home);
    // Clear state dir so it falls back to OPENCLAW_HOME
    mock:stubEnv("OPENCLAW_STATE_DIR", "");

    const agentDir = resolveAgentDir({} as OpenClawConfig, "main");
    (expect* agentDir).is(path.join(path.resolve(home), ".openclaw", "agents", "main", "agent"));
  });
});
