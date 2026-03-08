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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { SsrFBlockedError, type LookupFn } from "../infra/net/ssrf.js";
import {
  assertBrowserNavigationAllowed,
  assertBrowserNavigationResultAllowed,
  InvalidBrowserNavigationUrlError,
} from "./navigation-guard.js";

function createLookupFn(address: string): LookupFn {
  const family = address.includes(":") ? 6 : 4;
  return mock:fn(async () => [{ address, family }]) as unknown as LookupFn;
}

(deftest-group "browser navigation guard", () => {
  afterEach(() => {
    mock:unstubAllEnvs();
  });

  (deftest "blocks private loopback URLs by default", async () => {
    await (expect* 
      assertBrowserNavigationAllowed({
        url: "http://127.0.0.1:8080",
      }),
    ).rejects.toBeInstanceOf(SsrFBlockedError);
  });

  (deftest "allows about:blank", async () => {
    await (expect* 
      assertBrowserNavigationAllowed({
        url: "about:blank",
      }),
    ).resolves.toBeUndefined();
  });

  (deftest "blocks file URLs", async () => {
    await (expect* 
      assertBrowserNavigationAllowed({
        url: "file:///etc/passwd",
      }),
    ).rejects.toBeInstanceOf(InvalidBrowserNavigationUrlError);
  });

  (deftest "blocks data URLs", async () => {
    await (expect* 
      assertBrowserNavigationAllowed({
        url: "data:text/html,<h1>owned</h1>",
      }),
    ).rejects.toBeInstanceOf(InvalidBrowserNavigationUrlError);
  });

  (deftest "blocks javascript URLs", async () => {
    await (expect* 
      assertBrowserNavigationAllowed({
        url: "javascript:alert(1)",
      }),
    ).rejects.toBeInstanceOf(InvalidBrowserNavigationUrlError);
  });

  (deftest "blocks non-blank about URLs", async () => {
    await (expect* 
      assertBrowserNavigationAllowed({
        url: "about:srcdoc",
      }),
    ).rejects.toBeInstanceOf(InvalidBrowserNavigationUrlError);
  });

  (deftest "allows blocked hostnames when explicitly allowed", async () => {
    const lookupFn = createLookupFn("127.0.0.1");
    await (expect* 
      assertBrowserNavigationAllowed({
        url: "http://agent.internal:3000",
        ssrfPolicy: {
          allowedHostnames: ["agent.internal"],
        },
        lookupFn,
      }),
    ).resolves.toBeUndefined();
    (expect* lookupFn).toHaveBeenCalledWith("agent.internal", { all: true });
  });

  (deftest "blocks hostnames that resolve to private addresses by default", async () => {
    const lookupFn = createLookupFn("127.0.0.1");
    await (expect* 
      assertBrowserNavigationAllowed({
        url: "https://example.com",
        lookupFn,
      }),
    ).rejects.toBeInstanceOf(SsrFBlockedError);
  });

  (deftest "allows hostnames that resolve to public addresses", async () => {
    const lookupFn = createLookupFn("93.184.216.34");
    await (expect* 
      assertBrowserNavigationAllowed({
        url: "https://example.com",
        lookupFn,
      }),
    ).resolves.toBeUndefined();
    (expect* lookupFn).toHaveBeenCalledWith("example.com", { all: true });
  });

  (deftest "blocks strict policy navigation when env proxy is configured", async () => {
    mock:stubEnv("HTTP_PROXY", "http://127.0.0.1:7890");
    const lookupFn = createLookupFn("93.184.216.34");
    await (expect* 
      assertBrowserNavigationAllowed({
        url: "https://example.com",
        lookupFn,
      }),
    ).rejects.toBeInstanceOf(InvalidBrowserNavigationUrlError);
  });

  (deftest "allows env proxy navigation when private-network mode is explicitly enabled", async () => {
    mock:stubEnv("HTTP_PROXY", "http://127.0.0.1:7890");
    const lookupFn = createLookupFn("93.184.216.34");
    await (expect* 
      assertBrowserNavigationAllowed({
        url: "https://example.com",
        lookupFn,
        ssrfPolicy: { dangerouslyAllowPrivateNetwork: true },
      }),
    ).resolves.toBeUndefined();
  });

  (deftest "rejects invalid URLs", async () => {
    await (expect* 
      assertBrowserNavigationAllowed({
        url: "not a url",
      }),
    ).rejects.toBeInstanceOf(InvalidBrowserNavigationUrlError);
  });

  (deftest "validates final network URLs after navigation", async () => {
    const lookupFn = createLookupFn("127.0.0.1");
    await (expect* 
      assertBrowserNavigationResultAllowed({
        url: "http://private.test",
        lookupFn,
      }),
    ).rejects.toBeInstanceOf(SsrFBlockedError);
  });

  (deftest "ignores non-network browser-internal final URLs", async () => {
    await (expect* 
      assertBrowserNavigationResultAllowed({
        url: "chrome-error://chromewebdata/",
      }),
    ).resolves.toBeUndefined();
  });
});
