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
import { fetchPluralKitMessageInfo } from "./pluralkit.js";

type MockResponse = {
  status: number;
  ok: boolean;
  text: () => deferred-result<string>;
  json: () => deferred-result<unknown>;
};

const buildResponse = (params: { status: number; body?: unknown }): MockResponse => {
  const body = params.body;
  const textPayload = typeof body === "string" ? body : body == null ? "" : JSON.stringify(body);
  return {
    status: params.status,
    ok: params.status >= 200 && params.status < 300,
    text: async () => textPayload,
    json: async () => body ?? {},
  };
};

(deftest-group "fetchPluralKitMessageInfo", () => {
  (deftest "returns null when disabled", async () => {
    const fetcher = mock:fn();
    const result = await fetchPluralKitMessageInfo({
      messageId: "123",
      config: { enabled: false },
      fetcher: fetcher as unknown as typeof fetch,
    });
    (expect* result).toBeNull();
    (expect* fetcher).not.toHaveBeenCalled();
  });

  (deftest "returns null on 404", async () => {
    const fetcher = mock:fn(async () => buildResponse({ status: 404 }));
    const result = await fetchPluralKitMessageInfo({
      messageId: "missing",
      config: { enabled: true },
      fetcher: fetcher as unknown as typeof fetch,
    });
    (expect* result).toBeNull();
  });

  (deftest "returns payload and sends token when configured", async () => {
    let receivedHeaders: Record<string, string> | undefined;
    const fetcher = mock:fn(async (_url: string, init?: RequestInit) => {
      receivedHeaders = init?.headers as Record<string, string> | undefined;
      return buildResponse({
        status: 200,
        body: {
          id: "123",
          member: { id: "mem_1", name: "Alex" },
          system: { id: "sys_1", name: "System" },
        },
      });
    });

    const result = await fetchPluralKitMessageInfo({
      messageId: "123",
      config: { enabled: true, token: "pk_test" },
      fetcher: fetcher as unknown as typeof fetch,
    });

    (expect* result?.member?.id).is("mem_1");
    (expect* receivedHeaders?.Authorization).is("pk_test");
  });
});
