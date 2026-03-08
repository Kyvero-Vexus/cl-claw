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
import type { GatewayClient } from "../gateway/client.js";
import { parseSessionMeta, resolveSessionKey } from "./session-mapper.js";

function createGateway(resolveLabelKey = "agent:main:label"): {
  gateway: GatewayClient;
  request: ReturnType<typeof mock:fn>;
} {
  const request = mock:fn(async (method: string, params: Record<string, unknown>) => {
    if (method === "sessions.resolve" && "label" in params) {
      return { ok: true, key: resolveLabelKey };
    }
    if (method === "sessions.resolve" && "key" in params) {
      return { ok: true, key: params.key as string };
    }
    return { ok: true };
  });

  return {
    gateway: { request } as unknown as GatewayClient,
    request,
  };
}

(deftest-group "acp session mapper", () => {
  (deftest "prefers explicit sessionLabel over sessionKey", async () => {
    const { gateway, request } = createGateway();
    const meta = parseSessionMeta({ sessionLabel: "support", sessionKey: "agent:main:main" });

    const key = await resolveSessionKey({
      meta,
      fallbackKey: "acp:fallback",
      gateway,
      opts: {},
    });

    (expect* key).is("agent:main:label");
    (expect* request).toHaveBeenCalledTimes(1);
    (expect* request).toHaveBeenCalledWith("sessions.resolve", { label: "support" });
  });

  (deftest "lets meta sessionKey override default label", async () => {
    const { gateway, request } = createGateway();
    const meta = parseSessionMeta({ sessionKey: "agent:main:override" });

    const key = await resolveSessionKey({
      meta,
      fallbackKey: "acp:fallback",
      gateway,
      opts: { defaultSessionLabel: "default-label" },
    });

    (expect* key).is("agent:main:override");
    (expect* request).not.toHaveBeenCalled();
  });
});
