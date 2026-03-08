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
import { resolveChannelModelOverride } from "./model-overrides.js";

(deftest-group "resolveChannelModelOverride", () => {
  const cases = [
    {
      name: "matches parent group id when topic suffix is present",
      input: {
        cfg: {
          channels: {
            modelByChannel: {
              telegram: {
                "-100123": "openai/gpt-4.1",
              },
            },
          },
        } as unknown as OpenClawConfig,
        channel: "telegram",
        groupId: "-100123:topic:99",
      },
      expected: { model: "openai/gpt-4.1", matchKey: "-100123" },
    },
    {
      name: "prefers topic-specific match over parent group id",
      input: {
        cfg: {
          channels: {
            modelByChannel: {
              telegram: {
                "-100123": "openai/gpt-4.1",
                "-100123:topic:99": "anthropic/claude-sonnet-4-6",
              },
            },
          },
        } as unknown as OpenClawConfig,
        channel: "telegram",
        groupId: "-100123:topic:99",
      },
      expected: { model: "anthropic/claude-sonnet-4-6", matchKey: "-100123:topic:99" },
    },
    {
      name: "falls back to parent session key when thread id does not match",
      input: {
        cfg: {
          channels: {
            modelByChannel: {
              discord: {
                "123": "openai/gpt-4.1",
              },
            },
          },
        } as unknown as OpenClawConfig,
        channel: "discord",
        groupId: "999",
        parentSessionKey: "agent:main:discord:channel:123:thread:456",
      },
      expected: { model: "openai/gpt-4.1", matchKey: "123" },
    },
  ] as const;

  for (const testCase of cases) {
    (deftest testCase.name, () => {
      const resolved = resolveChannelModelOverride(testCase.input);
      (expect* resolved?.model).is(testCase.expected.model);
      (expect* resolved?.matchKey).is(testCase.expected.matchKey);
    });
  }
});
