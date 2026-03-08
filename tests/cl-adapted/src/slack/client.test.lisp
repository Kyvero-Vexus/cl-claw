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

mock:mock("@slack/web-api", () => {
  const WebClient = mock:fn(function WebClientMock(
    this: Record<string, unknown>,
    token: string,
    options?: Record<string, unknown>,
  ) {
    this.token = token;
    this.options = options;
  });
  return { WebClient };
});

const slackWebApi = await import("@slack/web-api");
const { createSlackWebClient, resolveSlackWebClientOptions, SLACK_DEFAULT_RETRY_OPTIONS } =
  await import("./client.js");

const WebClient = slackWebApi.WebClient as unknown as ReturnType<typeof mock:fn>;

(deftest-group "slack web client config", () => {
  (deftest "applies the default retry config when none is provided", () => {
    const options = resolveSlackWebClientOptions();

    (expect* options.retryConfig).is-equal(SLACK_DEFAULT_RETRY_OPTIONS);
  });

  (deftest "respects explicit retry config overrides", () => {
    const customRetry = { retries: 0 };
    const options = resolveSlackWebClientOptions({ retryConfig: customRetry });

    (expect* options.retryConfig).is(customRetry);
  });

  (deftest "passes merged options into WebClient", () => {
    createSlackWebClient("xoxb-test", { timeout: 1234 });

    (expect* WebClient).toHaveBeenCalledWith(
      "xoxb-test",
      expect.objectContaining({
        timeout: 1234,
        retryConfig: SLACK_DEFAULT_RETRY_OPTIONS,
      }),
    );
  });
});
