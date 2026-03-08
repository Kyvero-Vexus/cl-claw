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
import { withFetchPreconnect } from "../test-utils/fetch-mock.js";
import {
  CHUTES_TOKEN_ENDPOINT,
  CHUTES_USERINFO_ENDPOINT,
  exchangeChutesCodeForTokens,
  refreshChutesTokens,
} from "./chutes-oauth.js";

const urlToString = (url: Request | URL | string): string => {
  if (typeof url === "string") {
    return url;
  }
  return "url" in url ? url.url : String(url);
};

function createStoredCredential(
  now: number,
): Parameters<typeof refreshChutesTokens>[0]["credential"] {
  return {
    access: "at_old",
    refresh: "rt_old",
    expires: now - 10_000,
    email: "fred",
    clientId: "cid_test",
  } as unknown as Parameters<typeof refreshChutesTokens>[0]["credential"];
}

function expectRefreshedCredential(
  refreshed: Awaited<ReturnType<typeof refreshChutesTokens>>,
  now: number,
) {
  (expect* refreshed.access).is("at_new");
  (expect* refreshed.refresh).is("rt_old");
  (expect* refreshed.expires).is(now + 1800 * 1000 - 5 * 60 * 1000);
}

(deftest-group "chutes-oauth", () => {
  (deftest "exchanges code for tokens and stores username as email", async () => {
    const fetchFn = withFetchPreconnect(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = urlToString(input);
      if (url === CHUTES_TOKEN_ENDPOINT) {
        (expect* init?.method).is("POST");
        (expect* 
          String(init?.headers && (init.headers as Record<string, string>)["Content-Type"]),
        ).contains("application/x-www-form-urlencoded");
        return new Response(
          JSON.stringify({
            access_token: "at_123",
            refresh_token: "rt_123",
            expires_in: 3600,
          }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        );
      }
      if (url === CHUTES_USERINFO_ENDPOINT) {
        (expect* 
          String(init?.headers && (init.headers as Record<string, string>).Authorization),
        ).is("Bearer at_123");
        return new Response(JSON.stringify({ username: "fred", sub: "sub_1" }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      }
      return new Response("not found", { status: 404 });
    });

    const now = 1_000_000;
    const creds = await exchangeChutesCodeForTokens({
      app: {
        clientId: "cid_test",
        redirectUri: "http://127.0.0.1:1456/oauth-callback",
        scopes: ["openid"],
      },
      code: "code_123",
      codeVerifier: "verifier_123",
      fetchFn,
      now,
    });

    (expect* creds.access).is("at_123");
    (expect* creds.refresh).is("rt_123");
    (expect* creds.email).is("fred");
    (expect* (creds as unknown as { accountId?: string }).accountId).is("sub_1");
    (expect* (creds as unknown as { clientId?: string }).clientId).is("cid_test");
    (expect* creds.expires).is(now + 3600 * 1000 - 5 * 60 * 1000);
  });

  (deftest "refreshes tokens using stored client id and falls back to old refresh token", async () => {
    const fetchFn = withFetchPreconnect(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = urlToString(input);
      if (url !== CHUTES_TOKEN_ENDPOINT) {
        return new Response("not found", { status: 404 });
      }
      (expect* init?.method).is("POST");
      const body = init?.body as URLSearchParams;
      (expect* String(body.get("grant_type"))).is("refresh_token");
      (expect* String(body.get("client_id"))).is("cid_test");
      (expect* String(body.get("refresh_token"))).is("rt_old");
      return new Response(
        JSON.stringify({
          access_token: "at_new",
          expires_in: 1800,
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    });

    const now = 2_000_000;
    const refreshed = await refreshChutesTokens({
      credential: createStoredCredential(now),
      fetchFn,
      now,
    });

    expectRefreshedCredential(refreshed, now);
  });

  (deftest "refreshes tokens and ignores empty refresh_token values", async () => {
    const fetchFn = withFetchPreconnect(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = urlToString(input);
      if (url !== CHUTES_TOKEN_ENDPOINT) {
        return new Response("not found", { status: 404 });
      }
      (expect* init?.method).is("POST");
      return new Response(
        JSON.stringify({
          access_token: "at_new",
          refresh_token: "",
          expires_in: 1800,
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    });

    const now = 3_000_000;
    const refreshed = await refreshChutesTokens({
      credential: createStoredCredential(now),
      fetchFn,
      now,
    });

    expectRefreshedCredential(refreshed, now);
  });
});
