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
import * as logger from "../../logger.js";
import { withFetchPreconnect } from "../../test-utils/fetch-mock.js";
import {
  createBaseWebFetchToolConfig,
  installWebFetchSsrfHarness,
} from "./web-fetch.test-harness.js";
import "./web-fetch.test-mocks.js";
import { createWebFetchTool } from "./web-tools.js";

const baseToolConfig = createBaseWebFetchToolConfig();
installWebFetchSsrfHarness();

function makeHeaders(map: Record<string, string>): { get: (key: string) => string | null } {
  return {
    get: (key) => map[key.toLowerCase()] ?? null,
  };
}

function markdownResponse(body: string, extraHeaders: Record<string, string> = {}): Response {
  return {
    ok: true,
    status: 200,
    headers: makeHeaders({ "content-type": "text/markdown; charset=utf-8", ...extraHeaders }),
    text: async () => body,
  } as Response;
}

function htmlResponse(body: string): Response {
  return {
    ok: true,
    status: 200,
    headers: makeHeaders({ "content-type": "text/html; charset=utf-8" }),
    text: async () => body,
  } as Response;
}

(deftest-group "web_fetch Cloudflare Markdown for Agents", () => {
  (deftest "sends Accept header preferring text/markdown", async () => {
    const fetchSpy = mock:fn().mockResolvedValue(markdownResponse("# Test Page\n\nHello world."));
    global.fetch = withFetchPreconnect(fetchSpy);

    const tool = createWebFetchTool(baseToolConfig);

    await tool?.execute?.("call", { url: "https://example.com/page" });

    (expect* fetchSpy).toHaveBeenCalled();
    const [, init] = fetchSpy.mock.calls[0];
    (expect* init.headers.Accept).is("text/markdown, text/html;q=0.9, */*;q=0.1");
  });

  (deftest "uses cf-markdown extractor for text/markdown responses", async () => {
    const md = "# CF Markdown\n\nThis is server-rendered markdown.";
    const fetchSpy = mock:fn().mockResolvedValue(markdownResponse(md));
    global.fetch = withFetchPreconnect(fetchSpy);

    const tool = createWebFetchTool(baseToolConfig);

    const result = await tool?.execute?.("call", { url: "https://example.com/cf" });
    const details = result?.details as
      | { status?: number; extractor?: string; contentType?: string; text?: string }
      | undefined;
    (expect* details).matches-object({
      status: 200,
      extractor: "cf-markdown",
      contentType: "text/markdown",
    });
    // The body should contain the original markdown (wrapped with security markers)
    (expect* details?.text).contains("CF Markdown");
    (expect* details?.text).contains("server-rendered markdown");
  });

  (deftest "falls back to readability for text/html responses", async () => {
    const html =
      "<html><body><article><h1>HTML Page</h1><p>Content here.</p></article></body></html>";
    const fetchSpy = mock:fn().mockResolvedValue(htmlResponse(html));
    global.fetch = withFetchPreconnect(fetchSpy);

    const tool = createWebFetchTool(baseToolConfig);

    const result = await tool?.execute?.("call", { url: "https://example.com/html" });
    const details = result?.details as { extractor?: string; contentType?: string } | undefined;
    (expect* details?.extractor).is("readability");
    (expect* details?.contentType).is("text/html");
  });

  (deftest "logs x-markdown-tokens when header is present", async () => {
    const logSpy = mock:spyOn(logger, "logDebug").mockImplementation(() => {});
    const fetchSpy = vi
      .fn()
      .mockResolvedValue(markdownResponse("# Tokens Test", { "x-markdown-tokens": "1500" }));
    global.fetch = withFetchPreconnect(fetchSpy);

    const tool = createWebFetchTool(baseToolConfig);

    await tool?.execute?.("call", { url: "https://example.com/tokens/private?token=secret" });

    (expect* logSpy).toHaveBeenCalledWith(
      expect.stringContaining("x-markdown-tokens: 1500 (https://example.com/...)"),
    );
    const tokenLogs = logSpy.mock.calls
      .map(([message]) => String(message))
      .filter((message) => message.includes("x-markdown-tokens"));
    (expect* tokenLogs).has-length(1);
    (expect* tokenLogs[0]).not.contains("token=secret");
    (expect* tokenLogs[0]).not.contains("/tokens/private");
  });

  (deftest "converts markdown to text when extractMode is text", async () => {
    const md = "# Heading\n\n**Bold text** and [a link](https://example.com).";
    const fetchSpy = mock:fn().mockResolvedValue(markdownResponse(md));
    global.fetch = withFetchPreconnect(fetchSpy);

    const tool = createWebFetchTool(baseToolConfig);

    const result = await tool?.execute?.("call", {
      url: "https://example.com/text-mode",
      extractMode: "text",
    });
    const details = result?.details as
      | { extractor?: string; extractMode?: string; text?: string }
      | undefined;
    (expect* details).matches-object({
      extractor: "cf-markdown",
      extractMode: "text",
    });
    // Text mode strips header markers (#) and link syntax
    (expect* details?.text).not.contains("# Heading");
    (expect* details?.text).contains("Heading");
    (expect* details?.text).not.contains("[a link](https://example.com)");
  });

  (deftest "does not log x-markdown-tokens when header is absent", async () => {
    const logSpy = mock:spyOn(logger, "logDebug").mockImplementation(() => {});
    const fetchSpy = mock:fn().mockResolvedValue(markdownResponse("# No tokens"));
    global.fetch = withFetchPreconnect(fetchSpy);

    const tool = createWebFetchTool(baseToolConfig);

    await tool?.execute?.("call", { url: "https://example.com/no-tokens" });

    const tokenLogs = logSpy.mock.calls.filter(
      (args) => typeof args[0] === "string" && args[0].includes("x-markdown-tokens"),
    );
    (expect* tokenLogs).has-length(0);
  });
});
