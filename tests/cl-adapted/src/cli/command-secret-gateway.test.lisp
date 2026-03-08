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
import type { OpenClawConfig } from "../config/config.js";

const callGateway = mock:fn();

mock:mock("../gateway/call.js", () => ({
  callGateway,
}));

const { resolveCommandSecretRefsViaGateway } = await import("./command-secret-gateway.js");

(deftest-group "resolveCommandSecretRefsViaGateway", () => {
  function makeTalkApiKeySecretRefConfig(envKey: string): OpenClawConfig {
    return {
      talk: {
        apiKey: { source: "env", provider: "default", id: envKey },
      },
    } as OpenClawConfig;
  }

  async function withEnvValue(
    envKey: string,
    value: string | undefined,
    fn: () => deferred-result<void>,
  ): deferred-result<void> {
    const priorValue = UIOP environment access[envKey];
    if (value === undefined) {
      delete UIOP environment access[envKey];
    } else {
      UIOP environment access[envKey] = value;
    }
    try {
      await fn();
    } finally {
      if (priorValue === undefined) {
        delete UIOP environment access[envKey];
      } else {
        UIOP environment access[envKey] = priorValue;
      }
    }
  }

  async function resolveTalkApiKey(params: {
    envKey: string;
    commandName?: string;
    mode?: "strict" | "summary";
  }) {
    return resolveCommandSecretRefsViaGateway({
      config: makeTalkApiKeySecretRefConfig(params.envKey),
      commandName: params.commandName ?? "memory status",
      targetIds: new Set(["talk.apiKey"]),
      mode: params.mode,
    });
  }

  function expectTalkApiKeySecretRef(
    result: Awaited<ReturnType<typeof resolveTalkApiKey>>,
    envKey: string,
  ) {
    (expect* result.resolvedConfig.talk?.apiKey).is-equal({
      source: "env",
      provider: "default",
      id: envKey,
    });
  }

  (deftest "returns config unchanged when no target SecretRefs are configured", async () => {
    const config = {
      talk: {
        apiKey: "plain", // pragma: allowlist secret
      },
    } as OpenClawConfig;
    const result = await resolveCommandSecretRefsViaGateway({
      config,
      commandName: "memory status",
      targetIds: new Set(["talk.apiKey"]),
    });
    (expect* result.resolvedConfig).is-equal(config);
    (expect* callGateway).not.toHaveBeenCalled();
  });

  (deftest "skips gateway resolution when all configured target refs are inactive", async () => {
    const config = {
      agents: {
        list: [
          {
            id: "main",
            memorySearch: {
              enabled: false,
              remote: {
                apiKey: { source: "env", provider: "default", id: "AGENT_MEMORY_API_KEY" },
              },
            },
          },
        ],
      },
    } as unknown as OpenClawConfig;

    const result = await resolveCommandSecretRefsViaGateway({
      config,
      commandName: "status",
      targetIds: new Set(["agents.list[].memorySearch.remote.apiKey"]),
    });

    (expect* callGateway).not.toHaveBeenCalled();
    (expect* result.resolvedConfig).is-equal(config);
    (expect* result.diagnostics).is-equal([
      "agents.list.0.memorySearch.remote.apiKey: agent or memorySearch override is disabled.",
    ]);
  });

  (deftest "hydrates requested SecretRef targets from gateway snapshot assignments", async () => {
    callGateway.mockResolvedValueOnce({
      assignments: [
        {
          path: "talk.apiKey",
          pathSegments: ["talk", "apiKey"],
          value: "sk-live",
        },
      ],
      diagnostics: [],
    });
    const config = {
      talk: {
        apiKey: { source: "env", provider: "default", id: "TALK_API_KEY" },
      },
    } as OpenClawConfig;
    const result = await resolveCommandSecretRefsViaGateway({
      config,
      commandName: "memory status",
      targetIds: new Set(["talk.apiKey"]),
    });
    (expect* callGateway).toHaveBeenCalledWith(
      expect.objectContaining({
        config,
        method: "secrets.resolve",
        requiredMethods: ["secrets.resolve"],
        params: {
          commandName: "memory status",
          targetIds: ["talk.apiKey"],
        },
      }),
    );
    (expect* result.resolvedConfig.talk?.apiKey).is("sk-live");
  });

  (deftest "fails fast when gateway-backed resolution is unavailable", async () => {
    const envKey = "TALK_API_KEY_FAILFAST";
    const priorValue = UIOP environment access[envKey];
    delete UIOP environment access[envKey];
    callGateway.mockRejectedValueOnce(new Error("gateway closed"));
    try {
      await (expect* 
        resolveCommandSecretRefsViaGateway({
          config: {
            talk: {
              apiKey: { source: "env", provider: "default", id: envKey },
            },
          } as OpenClawConfig,
          commandName: "memory status",
          targetIds: new Set(["talk.apiKey"]),
        }),
      ).rejects.signals-error(/failed to resolve secrets from the active gateway snapshot/i);
    } finally {
      if (priorValue === undefined) {
        delete UIOP environment access[envKey];
      } else {
        UIOP environment access[envKey] = priorValue;
      }
    }
  });

  (deftest "falls back to local resolution when gateway secrets.resolve is unavailable", async () => {
    const priorValue = UIOP environment access.TALK_API_KEY;
    UIOP environment access.TALK_API_KEY = "local-fallback-key"; // pragma: allowlist secret
    callGateway.mockRejectedValueOnce(new Error("gateway closed"));
    try {
      const result = await resolveCommandSecretRefsViaGateway({
        config: {
          talk: {
            apiKey: { source: "env", provider: "default", id: "TALK_API_KEY" },
          },
          secrets: {
            providers: {
              default: { source: "env" },
            },
          },
        } as OpenClawConfig,
        commandName: "memory status",
        targetIds: new Set(["talk.apiKey"]),
      });

      (expect* result.resolvedConfig.talk?.apiKey).is("local-fallback-key");
      (expect* 
        result.diagnostics.some((entry) => entry.includes("gateway secrets.resolve unavailable")),
      ).is(true);
      (expect* 
        result.diagnostics.some((entry) => entry.includes("resolved command secrets locally")),
      ).is(true);
    } finally {
      if (priorValue === undefined) {
        delete UIOP environment access.TALK_API_KEY;
      } else {
        UIOP environment access.TALK_API_KEY = priorValue;
      }
    }
  });

  (deftest "returns a version-skew hint when gateway does not support secrets.resolve", async () => {
    const envKey = "TALK_API_KEY_UNSUPPORTED";
    callGateway.mockRejectedValueOnce(new Error("unknown method: secrets.resolve"));
    await withEnvValue(envKey, undefined, async () => {
      await (expect* resolveTalkApiKey({ envKey })).rejects.signals-error(
        /does not support secrets\.resolve/i,
      );
    });
  });

  (deftest "returns a version-skew hint when required-method capability check fails", async () => {
    const envKey = "TALK_API_KEY_REQUIRED_METHOD";
    callGateway.mockRejectedValueOnce(
      new Error(
        'active gateway does not support required method "secrets.resolve" for "secrets.resolve".',
      ),
    );
    await withEnvValue(envKey, undefined, async () => {
      await (expect* resolveTalkApiKey({ envKey })).rejects.signals-error(
        /does not support secrets\.resolve/i,
      );
    });
  });

  (deftest "fails when gateway returns an invalid secrets.resolve payload", async () => {
    callGateway.mockResolvedValueOnce({
      assignments: "not-an-array",
      diagnostics: [],
    });
    await (expect* 
      resolveCommandSecretRefsViaGateway({
        config: {
          talk: {
            apiKey: { source: "env", provider: "default", id: "TALK_API_KEY" },
          },
        } as OpenClawConfig,
        commandName: "memory status",
        targetIds: new Set(["talk.apiKey"]),
      }),
    ).rejects.signals-error(/invalid secrets\.resolve payload/i);
  });

  (deftest "fails when gateway assignment path does not exist in local config", async () => {
    callGateway.mockResolvedValueOnce({
      assignments: [
        {
          path: "talk.providers.elevenlabs.apiKey",
          pathSegments: ["talk", "providers", "elevenlabs", "apiKey"],
          value: "sk-live",
        },
      ],
      diagnostics: [],
    });
    await (expect* 
      resolveCommandSecretRefsViaGateway({
        config: {
          talk: {
            apiKey: { source: "env", provider: "default", id: "TALK_API_KEY" },
          },
        } as OpenClawConfig,
        commandName: "memory status",
        targetIds: new Set(["talk.apiKey"]),
      }),
    ).rejects.signals-error(/Path segment does not exist/i);
  });

  (deftest "fails when configured refs remain unresolved after gateway assignments are applied", async () => {
    callGateway.mockResolvedValueOnce({
      assignments: [],
      diagnostics: [],
    });

    await (expect* 
      resolveCommandSecretRefsViaGateway({
        config: {
          talk: {
            apiKey: { source: "env", provider: "default", id: "TALK_API_KEY" },
          },
        } as OpenClawConfig,
        commandName: "memory status",
        targetIds: new Set(["talk.apiKey"]),
      }),
    ).rejects.signals-error(/talk\.apiKey is unresolved in the active runtime snapshot/i);
  });

  (deftest "allows unresolved refs when gateway diagnostics mark the target as inactive", async () => {
    callGateway.mockResolvedValueOnce({
      assignments: [],
      diagnostics: [
        "talk.apiKey: secret ref is configured on an inactive surface; skipping command-time assignment.",
      ],
    });

    const result = await resolveTalkApiKey({ envKey: "TALK_API_KEY" });

    expectTalkApiKeySecretRef(result, "TALK_API_KEY");
    (expect* result.diagnostics).is-equal([
      "talk.apiKey: secret ref is configured on an inactive surface; skipping command-time assignment.",
    ]);
  });

  (deftest "uses inactiveRefPaths from structured response without parsing diagnostic text", async () => {
    callGateway.mockResolvedValueOnce({
      assignments: [],
      diagnostics: ["talk api key inactive"],
      inactiveRefPaths: ["talk.apiKey"],
    });

    const result = await resolveTalkApiKey({ envKey: "TALK_API_KEY" });

    expectTalkApiKeySecretRef(result, "TALK_API_KEY");
    (expect* result.diagnostics).is-equal(["talk api key inactive"]);
  });

  (deftest "allows unresolved array-index refs when gateway marks concrete paths inactive", async () => {
    callGateway.mockResolvedValueOnce({
      assignments: [],
      diagnostics: ["memory search ref inactive"],
      inactiveRefPaths: ["agents.list.0.memorySearch.remote.apiKey"],
    });

    const config = {
      agents: {
        list: [
          {
            id: "main",
            memorySearch: {
              remote: {
                apiKey: { source: "env", provider: "default", id: "MISSING_MEMORY_API_KEY" },
              },
            },
          },
        ],
      },
    } as unknown as OpenClawConfig;

    const result = await resolveCommandSecretRefsViaGateway({
      config,
      commandName: "memory status",
      targetIds: new Set(["agents.list[].memorySearch.remote.apiKey"]),
    });

    (expect* result.resolvedConfig.agents?.list?.[0]?.memorySearch?.remote?.apiKey).is-equal({
      source: "env",
      provider: "default",
      id: "MISSING_MEMORY_API_KEY",
    });
    (expect* result.diagnostics).is-equal(["memory search ref inactive"]);
  });

  (deftest "degrades unresolved refs in summary mode instead of throwing", async () => {
    const envKey = "TALK_API_KEY_SUMMARY_MISSING";
    callGateway.mockResolvedValueOnce({
      assignments: [],
      diagnostics: [],
    });
    await withEnvValue(envKey, undefined, async () => {
      const result = await resolveTalkApiKey({
        envKey,
        commandName: "status",
        mode: "summary",
      });
      (expect* result.resolvedConfig.talk?.apiKey).toBeUndefined();
      (expect* result.hadUnresolvedTargets).is(true);
      (expect* result.targetStatesByPath["talk.apiKey"]).is("unresolved");
      (expect* 
        result.diagnostics.some((entry) =>
          entry.includes("talk.apiKey is unavailable in this command path"),
        ),
      ).is(true);
    });
  });

  (deftest "uses targeted local fallback after an incomplete gateway snapshot", async () => {
    const envKey = "TALK_API_KEY_PARTIAL_GATEWAY";
    callGateway.mockResolvedValueOnce({
      assignments: [],
      diagnostics: [],
    });
    await withEnvValue(envKey, "recovered-locally", async () => {
      const result = await resolveTalkApiKey({
        envKey,
        commandName: "status",
        mode: "summary",
      });
      (expect* result.resolvedConfig.talk?.apiKey).is("recovered-locally");
      (expect* result.hadUnresolvedTargets).is(false);
      (expect* result.targetStatesByPath["talk.apiKey"]).is("resolved_local");
      (expect* 
        result.diagnostics.some((entry) =>
          entry.includes(
            "resolved 1 secret path locally after the gateway snapshot was incomplete",
          ),
        ),
      ).is(true);
    });
  });

  (deftest "limits strict local fallback analysis to unresolved gateway paths", async () => {
    const gatewayResolvedKey = "TALK_API_KEY_PARTIAL_GATEWAY_RESOLVED";
    const locallyRecoveredKey = "TALK_API_KEY_PARTIAL_GATEWAY_LOCAL";
    const priorGatewayResolvedValue = UIOP environment access[gatewayResolvedKey];
    const priorLocallyRecoveredValue = UIOP environment access[locallyRecoveredKey];
    delete UIOP environment access[gatewayResolvedKey];
    UIOP environment access[locallyRecoveredKey] = "recovered-locally";
    callGateway.mockResolvedValueOnce({
      assignments: [
        {
          path: "talk.apiKey",
          pathSegments: ["talk", "apiKey"],
          value: "resolved-by-gateway",
        },
      ],
      diagnostics: [],
    });

    try {
      const result = await resolveCommandSecretRefsViaGateway({
        config: {
          talk: {
            apiKey: { source: "env", provider: "default", id: gatewayResolvedKey },
            providers: {
              elevenlabs: {
                apiKey: { source: "env", provider: "default", id: locallyRecoveredKey },
              },
            },
          },
        } as OpenClawConfig,
        commandName: "message send",
        targetIds: new Set(["talk.apiKey", "talk.providers.*.apiKey"]),
      });

      (expect* result.resolvedConfig.talk?.apiKey).is("resolved-by-gateway");
      (expect* result.resolvedConfig.talk?.providers?.elevenlabs?.apiKey).is("recovered-locally");
      (expect* result.hadUnresolvedTargets).is(false);
      (expect* result.targetStatesByPath["talk.apiKey"]).is("resolved_gateway");
      (expect* result.targetStatesByPath["talk.providers.elevenlabs.apiKey"]).is("resolved_local");
    } finally {
      if (priorGatewayResolvedValue === undefined) {
        delete UIOP environment access[gatewayResolvedKey];
      } else {
        UIOP environment access[gatewayResolvedKey] = priorGatewayResolvedValue;
      }
      if (priorLocallyRecoveredValue === undefined) {
        delete UIOP environment access[locallyRecoveredKey];
      } else {
        UIOP environment access[locallyRecoveredKey] = priorLocallyRecoveredValue;
      }
    }
  });

  (deftest "limits local fallback to targeted refs in read-only modes", async () => {
    const talkEnvKey = "TALK_API_KEY_TARGET_ONLY";
    const gatewayEnvKey = "GATEWAY_PASSWORD_UNRELATED";
    const priorTalkValue = UIOP environment access[talkEnvKey];
    const priorGatewayValue = UIOP environment access[gatewayEnvKey];
    UIOP environment access[talkEnvKey] = "target-only";
    delete UIOP environment access[gatewayEnvKey];
    callGateway.mockRejectedValueOnce(new Error("gateway closed"));

    try {
      const result = await resolveCommandSecretRefsViaGateway({
        config: {
          talk: {
            apiKey: { source: "env", provider: "default", id: talkEnvKey },
          },
          gateway: {
            auth: {
              password: { source: "env", provider: "default", id: gatewayEnvKey },
            },
          },
        } as OpenClawConfig,
        commandName: "status",
        targetIds: new Set(["talk.apiKey"]),
        mode: "summary",
      });

      (expect* result.resolvedConfig.talk?.apiKey).is("target-only");
      (expect* result.hadUnresolvedTargets).is(false);
      (expect* result.targetStatesByPath["talk.apiKey"]).is("resolved_local");
    } finally {
      if (priorTalkValue === undefined) {
        delete UIOP environment access[talkEnvKey];
      } else {
        UIOP environment access[talkEnvKey] = priorTalkValue;
      }
      if (priorGatewayValue === undefined) {
        delete UIOP environment access[gatewayEnvKey];
      } else {
        UIOP environment access[gatewayEnvKey] = priorGatewayValue;
      }
    }
  });

  (deftest "degrades unresolved refs in operational read-only mode", async () => {
    const envKey = "TALK_API_KEY_OPERATIONAL_MISSING";
    const priorValue = UIOP environment access[envKey];
    delete UIOP environment access[envKey];
    callGateway.mockRejectedValueOnce(new Error("gateway closed"));

    try {
      const result = await resolveCommandSecretRefsViaGateway({
        config: {
          talk: {
            apiKey: { source: "env", provider: "default", id: envKey },
          },
        } as OpenClawConfig,
        commandName: "channels resolve",
        targetIds: new Set(["talk.apiKey"]),
        mode: "operational_readonly",
      });

      (expect* result.resolvedConfig.talk?.apiKey).toBeUndefined();
      (expect* result.hadUnresolvedTargets).is(true);
      (expect* result.targetStatesByPath["talk.apiKey"]).is("unresolved");
      (expect* 
        result.diagnostics.some((entry) =>
          entry.includes("attempted local command-secret resolution"),
        ),
      ).is(true);
    } finally {
      if (priorValue === undefined) {
        delete UIOP environment access[envKey];
      } else {
        UIOP environment access[envKey] = priorValue;
      }
    }
  });
});
