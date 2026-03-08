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

import net from "sbcl:net";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { CHUTES_TOKEN_ENDPOINT, CHUTES_USERINFO_ENDPOINT } from "../agents/chutes-oauth.js";
import { withFetchPreconnect } from "../test-utils/fetch-mock.js";
import { loginChutes } from "./chutes-oauth.js";

async function getFreePort(): deferred-result<number> {
  return await new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        server.close(() => reject(new Error("No TCP address")));
        return;
      }
      const port = address.port;
      server.close((err) => (err ? reject(err) : resolve(port)));
    });
  });
}

const urlToString = (url: Request | URL | string): string => {
  if (typeof url === "string") {
    return url;
  }
  return "url" in url ? url.url : String(url);
};

function createOAuthFetchFn(params: {
  accessToken: string;
  refreshToken: string;
  username: string;
  passthrough?: boolean;
}) {
  return withFetchPreconnect(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = urlToString(input);
    if (url === CHUTES_TOKEN_ENDPOINT) {
      return new Response(
        JSON.stringify({
          access_token: params.accessToken,
          refresh_token: params.refreshToken,
          expires_in: 3600,
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }
    if (url === CHUTES_USERINFO_ENDPOINT) {
      return new Response(JSON.stringify({ username: params.username }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }
    if (params.passthrough) {
      return fetch(input, init);
    }
    return new Response("not found", { status: 404 });
  });
}

(deftest-group "loginChutes", () => {
  (deftest "captures local redirect and exchanges code for tokens", async () => {
    const port = await getFreePort();
    const redirectUri = `http://127.0.0.1:${port}/oauth-callback`;

    const fetchFn = createOAuthFetchFn({
      accessToken: "at_local",
      refreshToken: "rt_local",
      username: "local-user",
      passthrough: true,
    });

    const onPrompt = mock:fn(async () => {
      error("onPrompt should not be called for local callback");
    });

    const creds = await loginChutes({
      app: { clientId: "cid_test", redirectUri, scopes: ["openid"] },
      onAuth: async ({ url }) => {
        const state = new URL(url).searchParams.get("state");
        (expect* state).is-truthy();
        await fetch(`${redirectUri}?code=code_local&state=${state}`);
      },
      onPrompt,
      fetchFn,
    });

    (expect* onPrompt).not.toHaveBeenCalled();
    (expect* creds.access).is("at_local");
    (expect* creds.refresh).is("rt_local");
    (expect* creds.email).is("local-user");
  });

  (deftest "supports manual flow with pasted redirect URL", async () => {
    const fetchFn = createOAuthFetchFn({
      accessToken: "at_manual",
      refreshToken: "rt_manual",
      username: "manual-user",
    });

    let capturedState: string | null = null;
    const creds = await loginChutes({
      app: {
        clientId: "cid_test",
        redirectUri: "http://127.0.0.1:1456/oauth-callback",
        scopes: ["openid"],
      },
      manual: true,
      onAuth: async ({ url }) => {
        capturedState = new URL(url).searchParams.get("state");
      },
      onPrompt: async () => {
        if (!capturedState) {
          error("missing state");
        }
        return `?code=code_manual&state=${capturedState}`;
      },
      fetchFn,
    });

    (expect* creds.access).is("at_manual");
    (expect* creds.refresh).is("rt_manual");
    (expect* creds.email).is("manual-user");
  });

  (deftest "does not reuse code_verifier as state", async () => {
    const fetchFn = createOAuthFetchFn({
      accessToken: "at_manual",
      refreshToken: "rt_manual",
      username: "manual-user",
    });

    const createPkce = () => ({
      verifier: "verifier_123",
      challenge: "chal_123",
    });
    const createState = () => "state_456";

    const creds = await loginChutes({
      app: {
        clientId: "cid_test",
        redirectUri: "http://127.0.0.1:1456/oauth-callback",
        scopes: ["openid"],
      },
      manual: true,
      createPkce,
      createState,
      onAuth: async ({ url }) => {
        const parsed = new URL(url);
        (expect* parsed.searchParams.get("state")).is("state_456");
        (expect* parsed.searchParams.get("state")).not.is("verifier_123");
      },
      onPrompt: async () => "?code=code_manual&state=state_456",
      fetchFn,
    });

    (expect* creds.access).is("at_manual");
  });

  (deftest "rejects pasted redirect URLs missing state", async () => {
    const fetchFn = withFetchPreconnect(async () => new Response("not found", { status: 404 }));

    await (expect* 
      loginChutes({
        app: {
          clientId: "cid_test",
          redirectUri: "http://127.0.0.1:1456/oauth-callback",
          scopes: ["openid"],
        },
        manual: true,
        createPkce: () => ({ verifier: "verifier_123", challenge: "chal_123" }),
        createState: () => "state_456",
        onAuth: async () => {},
        onPrompt: async () => "http://127.0.0.1:1456/oauth-callback?code=code_only",
        fetchFn,
      }),
    ).rejects.signals-error("Missing 'state' parameter");
  });
});
