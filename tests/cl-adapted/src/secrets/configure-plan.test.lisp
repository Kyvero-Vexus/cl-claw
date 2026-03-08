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
import {
  buildConfigureCandidates,
  buildConfigureCandidatesForScope,
  buildSecretsConfigurePlan,
  collectConfigureProviderChanges,
  hasConfigurePlanChanges,
} from "./configure-plan.js";

(deftest-group "secrets configure plan helpers", () => {
  (deftest "builds configure candidates from supported configure targets", () => {
    const config = {
      talk: {
        apiKey: "plain", // pragma: allowlist secret
      },
      channels: {
        telegram: {
          botToken: "token", // pragma: allowlist secret
        },
      },
    } as OpenClawConfig;

    const candidates = buildConfigureCandidates(config);
    const paths = candidates.map((entry) => entry.path);
    (expect* paths).contains("talk.apiKey");
    (expect* paths).contains("channels.telegram.botToken");
  });

  (deftest "collects provider upserts and deletes", () => {
    const original = {
      secrets: {
        providers: {
          default: { source: "env" },
          legacy: { source: "env" },
        },
      },
    } as OpenClawConfig;
    const next = {
      secrets: {
        providers: {
          default: { source: "env", allowlist: ["OPENAI_API_KEY"] },
          modern: { source: "env" },
        },
      },
    } as OpenClawConfig;

    const changes = collectConfigureProviderChanges({ original, next });
    (expect* Object.keys(changes.upserts).toSorted()).is-equal(["default", "modern"]);
    (expect* changes.deletes).is-equal(["legacy"]);
  });

  (deftest "discovers auth-profiles candidates for the selected agent scope", () => {
    const candidates = buildConfigureCandidatesForScope({
      config: {} as OpenClawConfig,
      authProfiles: {
        agentId: "main",
        store: {
          version: 1,
          profiles: {
            "openai:default": {
              type: "api_key",
              provider: "openai",
              key: "sk",
            },
          },
        },
      },
    });
    (expect* candidates).is-equal(
      expect.arrayContaining([
        expect.objectContaining({
          type: "auth-profiles.api_key.key",
          path: "profiles.openai:default.key",
          agentId: "main",
          configFile: "auth-profiles.json",
          authProfileProvider: "openai",
        }),
      ]),
    );
  });

  (deftest "captures existing refs for prefilled configure prompts", () => {
    const candidates = buildConfigureCandidatesForScope({
      config: {
        talk: {
          apiKey: {
            source: "env",
            provider: "default",
            id: "TALK_API_KEY",
          },
        },
      } as OpenClawConfig,
      authProfiles: {
        agentId: "main",
        store: {
          version: 1,
          profiles: {
            "openai:default": {
              type: "api_key",
              provider: "openai",
              keyRef: {
                source: "env",
                provider: "default",
                id: "OPENAI_API_KEY",
              },
            },
          },
        },
      },
    });

    (expect* candidates).is-equal(
      expect.arrayContaining([
        expect.objectContaining({
          path: "talk.apiKey",
          existingRef: {
            source: "env",
            provider: "default",
            id: "TALK_API_KEY",
          },
        }),
        expect.objectContaining({
          path: "profiles.openai:default.key",
          existingRef: {
            source: "env",
            provider: "default",
            id: "OPENAI_API_KEY", // pragma: allowlist secret
          },
        }),
      ]),
    );
  });

  (deftest "marks normalized alias paths as derived when not authored directly", () => {
    const candidates = buildConfigureCandidatesForScope({
      config: {
        talk: {
          provider: "elevenlabs",
          providers: {
            elevenlabs: {
              apiKey: "demo-talk-key", // pragma: allowlist secret
            },
          },
          apiKey: "demo-talk-key", // pragma: allowlist secret
        },
      } as OpenClawConfig,
      authoredOpenClawConfig: {
        talk: {
          apiKey: "demo-talk-key", // pragma: allowlist secret
        },
      } as OpenClawConfig,
    });

    const legacy = candidates.find((entry) => entry.path === "talk.apiKey");
    const normalized = candidates.find(
      (entry) => entry.path === "talk.providers.elevenlabs.apiKey",
    );
    (expect* legacy?.isDerived).not.is(true);
    (expect* normalized?.isDerived).is(true);
  });

  (deftest "reports configure change presence and builds deterministic plan shape", () => {
    const selected = new Map([
      [
        "talk.apiKey",
        {
          type: "talk.apiKey",
          path: "talk.apiKey",
          pathSegments: ["talk", "apiKey"],
          label: "talk.apiKey",
          configFile: "openclaw.json" as const,
          expectedResolvedValue: "string" as const,
          ref: {
            source: "env" as const,
            provider: "default",
            id: "TALK_API_KEY",
          },
        },
      ],
    ]);
    const providerChanges = {
      upserts: {
        default: { source: "env" as const },
      },
      deletes: [],
    };
    (expect* 
      hasConfigurePlanChanges({
        selectedTargets: selected,
        providerChanges,
      }),
    ).is(true);

    const plan = buildSecretsConfigurePlan({
      selectedTargets: selected,
      providerChanges,
      generatedAt: "2026-02-28T00:00:00.000Z",
    });
    (expect* plan.targets).has-length(1);
    (expect* plan.targets[0]?.path).is("talk.apiKey");
    (expect* plan.providerUpserts).toBeDefined();
    (expect* plan.options).is-equal({
      scrubEnv: true,
      scrubAuthProfilesForProviderTargets: true,
      scrubLegacyAuthJson: true,
    });
  });
});
