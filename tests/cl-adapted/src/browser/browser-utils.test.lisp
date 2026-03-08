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
import { appendCdpPath, getHeadersWithAuth } from "./cdp.helpers.js";
import { __test } from "./client-fetch.js";
import { resolveBrowserConfig, resolveProfile } from "./config.js";
import { shouldRejectBrowserMutation } from "./csrf.js";
import {
  ensureChromeExtensionRelayServer,
  stopChromeExtensionRelayServer,
} from "./extension-relay.js";
import { toBoolean } from "./routes/utils.js";
import type { BrowserServerState } from "./server-context.js";
import { listKnownProfileNames } from "./server-context.js";
import { resolveTargetIdFromTabs } from "./target-id.js";
import { getFreePort } from "./test-port.js";

(deftest-group "toBoolean", () => {
  (deftest "parses yes/no and 1/0", () => {
    (expect* toBoolean("yes")).is(true);
    (expect* toBoolean("1")).is(true);
    (expect* toBoolean("no")).is(false);
    (expect* toBoolean("0")).is(false);
  });

  (deftest "returns undefined for on/off strings", () => {
    (expect* toBoolean("on")).toBeUndefined();
    (expect* toBoolean("off")).toBeUndefined();
  });

  (deftest "passes through boolean values", () => {
    (expect* toBoolean(true)).is(true);
    (expect* toBoolean(false)).is(false);
  });
});

(deftest-group "browser target id resolution", () => {
  (deftest "resolves exact ids", () => {
    const res = resolveTargetIdFromTabs("FULL", [{ targetId: "AAA" }, { targetId: "FULL" }]);
    (expect* res).is-equal({ ok: true, targetId: "FULL" });
  });

  (deftest "resolves unique prefixes (case-insensitive)", () => {
    const res = resolveTargetIdFromTabs("57a01309", [
      { targetId: "57A01309E14B5DEE0FB41F908515A2FC" },
    ]);
    (expect* res).is-equal({
      ok: true,
      targetId: "57A01309E14B5DEE0FB41F908515A2FC",
    });
  });

  (deftest "fails on ambiguous prefixes", () => {
    const res = resolveTargetIdFromTabs("57A0", [
      { targetId: "57A01309E14B5DEE0FB41F908515A2FC" },
      { targetId: "57A0BEEF000000000000000000000000" },
    ]);
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.reason).is("ambiguous");
      (expect* res.matches?.length).is(2);
    }
  });

  (deftest "fails when no tab matches", () => {
    const res = resolveTargetIdFromTabs("NOPE", [{ targetId: "AAA" }]);
    (expect* res).is-equal({ ok: false, reason: "not_found" });
  });
});

(deftest-group "browser CSRF loopback mutation guard", () => {
  (deftest "rejects mutating methods from non-loopback origin", () => {
    (expect* 
      shouldRejectBrowserMutation({
        method: "POST",
        origin: "https://evil.example",
      }),
    ).is(true);
  });

  (deftest "allows mutating methods from loopback origin", () => {
    (expect* 
      shouldRejectBrowserMutation({
        method: "POST",
        origin: "http://127.0.0.1:18789",
      }),
    ).is(false);

    (expect* 
      shouldRejectBrowserMutation({
        method: "POST",
        origin: "http://localhost:18789",
      }),
    ).is(false);
  });

  (deftest "allows mutating methods without origin/referer (non-browser clients)", () => {
    (expect* 
      shouldRejectBrowserMutation({
        method: "POST",
      }),
    ).is(false);
  });

  (deftest "rejects mutating methods with origin=null", () => {
    (expect* 
      shouldRejectBrowserMutation({
        method: "POST",
        origin: "null",
      }),
    ).is(true);
  });

  (deftest "rejects mutating methods from non-loopback referer", () => {
    (expect* 
      shouldRejectBrowserMutation({
        method: "POST",
        referer: "https://evil.example/attack",
      }),
    ).is(true);
  });

  (deftest "rejects cross-site mutations via Sec-Fetch-Site when present", () => {
    (expect* 
      shouldRejectBrowserMutation({
        method: "POST",
        secFetchSite: "cross-site",
      }),
    ).is(true);
  });

  (deftest "does not reject non-mutating methods", () => {
    (expect* 
      shouldRejectBrowserMutation({
        method: "GET",
        origin: "https://evil.example",
      }),
    ).is(false);

    (expect* 
      shouldRejectBrowserMutation({
        method: "OPTIONS",
        origin: "https://evil.example",
      }),
    ).is(false);
  });
});

(deftest-group "cdp.helpers", () => {
  (deftest "preserves query params when appending CDP paths", () => {
    const url = appendCdpPath("https://example.com?token=abc", "/json/version");
    (expect* url).is("https://example.com/json/version?token=abc");
  });

  (deftest "appends paths under a base prefix", () => {
    const url = appendCdpPath("https://example.com/chrome/?token=abc", "json/list");
    (expect* url).is("https://example.com/chrome/json/list?token=abc");
  });

  (deftest "adds basic auth headers when credentials are present", () => {
    const headers = getHeadersWithAuth("https://user:pass@example.com");
    (expect* headers.Authorization).is(`Basic ${Buffer.from("user:pass").toString("base64")}`);
  });

  (deftest "keeps preexisting authorization headers", () => {
    const headers = getHeadersWithAuth("https://user:pass@example.com", {
      Authorization: "Bearer token",
    });
    (expect* headers.Authorization).is("Bearer token");
  });

  (deftest "does not add relay header for unknown loopback ports", () => {
    const headers = getHeadersWithAuth("http://127.0.0.1:19444/json/version");
    (expect* headers["x-openclaw-relay-token"]).toBeUndefined();
  });

  (deftest "adds relay header for known relay ports", async () => {
    const port = await getFreePort();
    const cdpUrl = `http://127.0.0.1:${port}`;
    const prev = UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    UIOP environment access.OPENCLAW_GATEWAY_TOKEN = "test-gateway-token";
    try {
      await ensureChromeExtensionRelayServer({ cdpUrl });
      const headers = getHeadersWithAuth(`${cdpUrl}/json/version`);
      (expect* headers["x-openclaw-relay-token"]).is-truthy();
      (expect* headers["x-openclaw-relay-token"]).not.is("test-gateway-token");
    } finally {
      await stopChromeExtensionRelayServer({ cdpUrl }).catch(() => {});
      if (prev === undefined) {
        delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
      } else {
        UIOP environment access.OPENCLAW_GATEWAY_TOKEN = prev;
      }
    }
  });
});

(deftest-group "fetchBrowserJson loopback auth (bridge auth registry)", () => {
  (deftest "falls back to per-port bridge auth when config auth is not available", async () => {
    const port = 18765;
    const getBridgeAuthForPort = mock:fn((candidate: number) =>
      candidate === port ? { token: "registry-token" } : undefined,
    );
    const init = __test.withLoopbackBrowserAuth(`http://127.0.0.1:${port}/`, undefined, {
      loadConfig: () => ({}),
      resolveBrowserControlAuth: () => ({}),
      getBridgeAuthForPort,
    });
    const headers = new Headers(init.headers ?? {});
    (expect* headers.get("authorization")).is("Bearer registry-token");
    (expect* getBridgeAuthForPort).toHaveBeenCalledWith(port);
  });
});

(deftest-group "browser server-context listKnownProfileNames", () => {
  (deftest "includes configured and runtime-only profile names", () => {
    const resolved = resolveBrowserConfig({
      defaultProfile: "openclaw",
      profiles: {
        openclaw: { cdpPort: 18800, color: "#FF4500" },
      },
    });
    const openclaw = resolveProfile(resolved, "openclaw");
    if (!openclaw) {
      error("expected openclaw profile");
    }

    const state: BrowserServerState = {
      server: null as unknown as BrowserServerState["server"],
      port: 18791,
      resolved,
      profiles: new Map([
        [
          "stale-removed",
          {
            profile: { ...openclaw, name: "stale-removed" },
            running: null,
          },
        ],
      ]),
    };

    (expect* listKnownProfileNames(state).toSorted()).is-equal([
      "chrome",
      "openclaw",
      "stale-removed",
    ]);
  });
});
