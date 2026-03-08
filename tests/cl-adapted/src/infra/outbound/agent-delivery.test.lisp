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

const mocks = mock:hoisted(() => ({
  resolveOutboundTarget: mock:fn(() => ({ ok: true as const, to: "+1999" })),
}));

mock:mock("./targets.js", async () => {
  const actual = await mock:importActual<typeof import("./targets.js")>("./targets.js");
  return {
    ...actual,
    resolveOutboundTarget: mocks.resolveOutboundTarget,
  };
});

import type { OpenClawConfig } from "../../config/config.js";
import { resolveAgentDeliveryPlan, resolveAgentOutboundTarget } from "./agent-delivery.js";

(deftest-group "agent delivery helpers", () => {
  (deftest "builds a delivery plan from session delivery context", () => {
    const plan = resolveAgentDeliveryPlan({
      sessionEntry: {
        sessionId: "s1",
        updatedAt: 1,
        deliveryContext: { channel: "whatsapp", to: "+1555", accountId: "work" },
      },
      requestedChannel: "last",
      explicitTo: undefined,
      accountId: undefined,
      wantsDelivery: true,
    });

    (expect* plan.resolvedChannel).is("whatsapp");
    (expect* plan.resolvedTo).is("+1555");
    (expect* plan.resolvedAccountId).is("work");
    (expect* plan.deliveryTargetMode).is("implicit");
  });

  (deftest "resolves fallback targets when no explicit destination is provided", () => {
    const plan = resolveAgentDeliveryPlan({
      sessionEntry: {
        sessionId: "s2",
        updatedAt: 2,
        deliveryContext: { channel: "whatsapp" },
      },
      requestedChannel: "last",
      explicitTo: undefined,
      accountId: undefined,
      wantsDelivery: true,
    });

    const resolved = resolveAgentOutboundTarget({
      cfg: {} as OpenClawConfig,
      plan,
      targetMode: "implicit",
    });

    (expect* mocks.resolveOutboundTarget).toHaveBeenCalledTimes(1);
    (expect* resolved.resolvedTarget?.ok).is(true);
    (expect* resolved.resolvedTo).is("+1999");
  });

  (deftest "does not inject a default deliverable channel when session has none", () => {
    const plan = resolveAgentDeliveryPlan({
      sessionEntry: undefined,
      requestedChannel: "last",
      explicitTo: undefined,
      accountId: undefined,
      wantsDelivery: true,
    });

    (expect* plan.resolvedChannel).is("webchat");
    (expect* plan.deliveryTargetMode).toBeUndefined();
  });

  (deftest "skips outbound target resolution when explicit target validation is disabled", () => {
    const plan = resolveAgentDeliveryPlan({
      sessionEntry: {
        sessionId: "s3",
        updatedAt: 3,
        deliveryContext: { channel: "whatsapp", to: "+1555" },
      },
      requestedChannel: "last",
      explicitTo: "+1555",
      accountId: undefined,
      wantsDelivery: true,
    });

    mocks.resolveOutboundTarget.mockClear();
    const resolved = resolveAgentOutboundTarget({
      cfg: {} as OpenClawConfig,
      plan,
      targetMode: "explicit",
      validateExplicitTarget: false,
    });

    (expect* mocks.resolveOutboundTarget).not.toHaveBeenCalled();
    (expect* resolved.resolvedTo).is("+1555");
  });

  (deftest "prefers turn-source delivery context over session last route", () => {
    const plan = resolveAgentDeliveryPlan({
      sessionEntry: {
        sessionId: "s4",
        updatedAt: 4,
        deliveryContext: { channel: "slack", to: "U_WRONG", accountId: "wrong" },
      },
      requestedChannel: "last",
      turnSourceChannel: "whatsapp",
      turnSourceTo: "+17775550123",
      turnSourceAccountId: "work",
      accountId: undefined,
      wantsDelivery: true,
    });

    (expect* plan.resolvedChannel).is("whatsapp");
    (expect* plan.resolvedTo).is("+17775550123");
    (expect* plan.resolvedAccountId).is("work");
  });

  (deftest "does not reuse mutable session to when only turnSourceChannel is provided", () => {
    const plan = resolveAgentDeliveryPlan({
      sessionEntry: {
        sessionId: "s5",
        updatedAt: 5,
        deliveryContext: { channel: "slack", to: "U_WRONG" },
      },
      requestedChannel: "last",
      turnSourceChannel: "whatsapp",
      accountId: undefined,
      wantsDelivery: true,
    });

    (expect* plan.resolvedChannel).is("whatsapp");
    (expect* plan.resolvedTo).toBeUndefined();
  });
});
