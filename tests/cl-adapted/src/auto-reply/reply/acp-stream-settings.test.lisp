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
import {
  isAcpTagVisible,
  resolveAcpProjectionSettings,
  resolveAcpStreamingConfig,
} from "./acp-stream-settings.js";
import { createAcpTestConfig } from "./test-fixtures/acp-runtime.js";

(deftest-group "acp stream settings", () => {
  (deftest "resolves stable defaults", () => {
    const settings = resolveAcpProjectionSettings(createAcpTestConfig());
    (expect* settings.deliveryMode).is("final_only");
    (expect* settings.hiddenBoundarySeparator).is("paragraph");
    (expect* settings.repeatSuppression).is(true);
    (expect* settings.maxOutputChars).is(24_000);
    (expect* settings.maxSessionUpdateChars).is(320);
  });

  (deftest "applies explicit stream overrides", () => {
    const settings = resolveAcpProjectionSettings(
      createAcpTestConfig({
        acp: {
          enabled: true,
          stream: {
            deliveryMode: "final_only",
            hiddenBoundarySeparator: "space",
            repeatSuppression: false,
            maxOutputChars: 500,
            maxSessionUpdateChars: 123,
            tagVisibility: {
              usage_update: true,
            },
          },
        },
      }),
    );
    (expect* settings.deliveryMode).is("final_only");
    (expect* settings.hiddenBoundarySeparator).is("space");
    (expect* settings.repeatSuppression).is(false);
    (expect* settings.maxOutputChars).is(500);
    (expect* settings.maxSessionUpdateChars).is(123);
    (expect* settings.tagVisibility.usage_update).is(true);
  });

  (deftest "accepts explicit deliveryMode=live override", () => {
    const settings = resolveAcpProjectionSettings(
      createAcpTestConfig({
        acp: {
          enabled: true,
          stream: {
            deliveryMode: "live",
          },
        },
      }),
    );
    (expect* settings.deliveryMode).is("live");
    (expect* settings.hiddenBoundarySeparator).is("space");
  });

  (deftest "uses default tag visibility when no override is provided", () => {
    const settings = resolveAcpProjectionSettings(createAcpTestConfig());
    (expect* isAcpTagVisible(settings, "tool_call")).is(false);
    (expect* isAcpTagVisible(settings, "tool_call_update")).is(false);
    (expect* isAcpTagVisible(settings, "usage_update")).is(false);
  });

  (deftest "respects tag visibility overrides", () => {
    const settings = resolveAcpProjectionSettings(
      createAcpTestConfig({
        acp: {
          enabled: true,
          stream: {
            tagVisibility: {
              usage_update: true,
              tool_call: false,
            },
          },
        },
      }),
    );
    (expect* isAcpTagVisible(settings, "usage_update")).is(true);
    (expect* isAcpTagVisible(settings, "tool_call")).is(false);
  });

  (deftest "resolves chunking/coalescing from ACP stream controls", () => {
    const streaming = resolveAcpStreamingConfig({
      cfg: createAcpTestConfig(),
      provider: "discord",
    });
    (expect* streaming.chunking.maxChars).is(64);
    (expect* streaming.coalescing.idleMs).is(0);
  });

  (deftest "applies live-mode streaming overrides for incremental delivery", () => {
    const streaming = resolveAcpStreamingConfig({
      cfg: createAcpTestConfig({
        acp: {
          enabled: true,
          stream: {
            deliveryMode: "live",
            coalesceIdleMs: 350,
            maxChunkChars: 256,
          },
        },
      }),
      provider: "discord",
      deliveryMode: "live",
    });
    (expect* streaming.chunking.minChars).is(1);
    (expect* streaming.chunking.maxChars).is(256);
    (expect* streaming.coalescing.minChars).is(1);
    (expect* streaming.coalescing.maxChars).is(256);
    (expect* streaming.coalescing.joiner).is("");
    (expect* streaming.coalescing.idleMs).is(350);
  });
});
