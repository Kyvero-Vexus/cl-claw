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
  coerceToFailoverError,
  describeFailoverError,
  isTimeoutError,
  resolveFailoverReasonFromError,
  resolveFailoverStatus,
} from "./failover-error.js";

// OpenAI 429 example shape: https://help.openai.com/en/articles/5955604-how-can-i-solve-429-too-many-requests-errors
const OPENAI_RATE_LIMIT_MESSAGE =
  "Rate limit reached for gpt-4.1-mini in organization org_test on requests per min. Limit: 3.000000 / min. Current: 3.000000 / min.";
// Anthropic overloaded_error example shape: https://docs.anthropic.com/en/api/errors
const ANTHROPIC_OVERLOADED_PAYLOAD =
  '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"},"request_id":"req_test"}';
// Gemini RESOURCE_EXHAUSTED troubleshooting example: https://ai.google.dev/gemini-api/docs/troubleshooting
const GEMINI_RESOURCE_EXHAUSTED_MESSAGE =
  "RESOURCE_EXHAUSTED: Resource has been exhausted (e.g. check quota).";
// OpenRouter 402 billing example: https://openrouter.ai/docs/api-reference/errors
const OPENROUTER_CREDITS_MESSAGE = "Payment Required: insufficient credits";
const TOGETHER_MONTHLY_SPEND_CAP_MESSAGE =
  "The account associated with this API key has reached its maximum allowed monthly spending limit.";
// Issue-backed Anthropic/OpenAI-compatible insufficient_quota payload under HTTP 400:
// https://github.com/openclaw/openclaw/issues/23440
const INSUFFICIENT_QUOTA_PAYLOAD =
  '{"type":"error","error":{"type":"insufficient_quota","message":"Your account has insufficient quota balance to run this request."}}';
// Issue-backed ZhipuAI/GLM quota-exhausted log from #33785:
// https://github.com/openclaw/openclaw/issues/33785
const ZHIPUAI_WEEKLY_MONTHLY_LIMIT_EXHAUSTED_MESSAGE =
  "LLM error 1310: Weekly/Monthly Limit Exhausted. Your limit will reset at 2026-03-06 22:19:54 (request_id: 20260303141547610b7f574d1b44cb)";
// AWS Bedrock 429 ThrottlingException / 503 ServiceUnavailable:
// https://docs.aws.amazon.com/bedrock/latest/userguide/troubleshooting-api-error-codes.html
const BEDROCK_THROTTLING_EXCEPTION_MESSAGE =
  "ThrottlingException: Your request was denied due to exceeding the account quotas for Amazon Bedrock.";
const BEDROCK_SERVICE_UNAVAILABLE_MESSAGE =
  "ServiceUnavailable: The service is temporarily unable to handle the request.";
// Groq error codes examples: https://console.groq.com/docs/errors
const GROQ_TOO_MANY_REQUESTS_MESSAGE =
  "429 Too Many Requests: Too many requests were sent in a given timeframe.";
const GROQ_SERVICE_UNAVAILABLE_MESSAGE =
  "503 Service Unavailable: The server is temporarily unable to handle the request due to overloading or maintenance.";

(deftest-group "failover-error", () => {
  (deftest "infers failover reason from HTTP status", () => {
    (expect* resolveFailoverReasonFromError({ status: 402 })).is("billing");
    // Anthropic Claude Max plan surfaces rate limits as HTTP 402 (#30484)
    (expect* 
      resolveFailoverReasonFromError({
        status: 402,
        message: "HTTP 402: request reached organization usage limit, try again later",
      }),
    ).is("rate_limit");
    // Explicit billing messages on 402 stay classified as billing
    (expect* 
      resolveFailoverReasonFromError({
        status: 402,
        message: "insufficient credits — please top up your account",
      }),
    ).is("billing");
    // Ambiguous "quota exceeded" + billing signal → billing wins
    (expect* 
      resolveFailoverReasonFromError({
        status: 402,
        message: "HTTP 402: You have exceeded your current quota. Please add more credits.",
      }),
    ).is("billing");
    (expect* resolveFailoverReasonFromError({ statusCode: "429" })).is("rate_limit");
    (expect* resolveFailoverReasonFromError({ status: 403 })).is("auth");
    (expect* resolveFailoverReasonFromError({ status: 408 })).is("timeout");
    (expect* resolveFailoverReasonFromError({ status: 400 })).is("format");
    // Keep the status-only path behavior-preserving and conservative.
    (expect* resolveFailoverReasonFromError({ status: 500 })).toBeNull();
    (expect* resolveFailoverReasonFromError({ status: 502 })).is("timeout");
    (expect* resolveFailoverReasonFromError({ status: 503 })).is("timeout");
    (expect* resolveFailoverReasonFromError({ status: 504 })).is("timeout");
    (expect* resolveFailoverReasonFromError({ status: 521 })).toBeNull();
    (expect* resolveFailoverReasonFromError({ status: 522 })).toBeNull();
    (expect* resolveFailoverReasonFromError({ status: 523 })).toBeNull();
    (expect* resolveFailoverReasonFromError({ status: 524 })).toBeNull();
    (expect* resolveFailoverReasonFromError({ status: 529 })).is("overloaded");
  });

  (deftest "classifies documented provider error shapes at the error boundary", () => {
    (expect* 
      resolveFailoverReasonFromError({
        status: 429,
        message: OPENAI_RATE_LIMIT_MESSAGE,
      }),
    ).is("rate_limit");
    (expect* 
      resolveFailoverReasonFromError({
        status: 529,
        message: ANTHROPIC_OVERLOADED_PAYLOAD,
      }),
    ).is("overloaded");
    (expect* 
      resolveFailoverReasonFromError({
        status: 429,
        message: GEMINI_RESOURCE_EXHAUSTED_MESSAGE,
      }),
    ).is("rate_limit");
    (expect* 
      resolveFailoverReasonFromError({
        status: 402,
        message: OPENROUTER_CREDITS_MESSAGE,
      }),
    ).is("billing");
    (expect* 
      resolveFailoverReasonFromError({
        status: 429,
        message: BEDROCK_THROTTLING_EXCEPTION_MESSAGE,
      }),
    ).is("rate_limit");
    (expect* 
      resolveFailoverReasonFromError({
        status: 503,
        message: BEDROCK_SERVICE_UNAVAILABLE_MESSAGE,
      }),
    ).is("timeout");
    (expect* 
      resolveFailoverReasonFromError({
        status: 429,
        message: GROQ_TOO_MANY_REQUESTS_MESSAGE,
      }),
    ).is("rate_limit");
    (expect* 
      resolveFailoverReasonFromError({
        status: 503,
        message: GROQ_SERVICE_UNAVAILABLE_MESSAGE,
      }),
    ).is("overloaded");
  });

  (deftest "keeps status-only 503s conservative unless the payload is clearly overloaded", () => {
    (expect* 
      resolveFailoverReasonFromError({
        status: 503,
        message: "Internal database error",
      }),
    ).is("timeout");
    (expect* 
      resolveFailoverReasonFromError({
        status: 503,
        message: '{"error":{"message":"The model is overloaded. Please try later"}}',
      }),
    ).is("overloaded");
  });

  (deftest "treats 400 insufficient_quota payloads as billing instead of format", () => {
    (expect* 
      resolveFailoverReasonFromError({
        status: 400,
        message: INSUFFICIENT_QUOTA_PAYLOAD,
      }),
    ).is("billing");
  });

  (deftest "treats zhipuai weekly/monthly limit exhausted as rate_limit", () => {
    (expect* 
      resolveFailoverReasonFromError({
        message: ZHIPUAI_WEEKLY_MONTHLY_LIMIT_EXHAUSTED_MESSAGE,
      }),
    ).is("rate_limit");
    (expect* 
      resolveFailoverReasonFromError({
        message: "LLM error: monthly limit reached",
      }),
    ).is("rate_limit");
  });

  (deftest "treats overloaded provider payloads as overloaded", () => {
    (expect* 
      resolveFailoverReasonFromError({
        message: ANTHROPIC_OVERLOADED_PAYLOAD,
      }),
    ).is("overloaded");
  });

  (deftest "keeps raw-text 402 weekly/monthly limit errors in billing", () => {
    (expect* 
      resolveFailoverReasonFromError({
        message: "402 Payment Required: Weekly/Monthly Limit Exhausted",
      }),
    ).is("billing");
  });

  (deftest "keeps temporary 402 spend limits retryable without downgrading explicit billing", () => {
    (expect* 
      resolveFailoverReasonFromError({
        status: 402,
        message: "Monthly spend limit reached. Please visit your billing settings.",
      }),
    ).is("rate_limit");
    (expect* 
      resolveFailoverReasonFromError({
        status: 402,
        message: "Workspace spend limit reached. Contact your admin.",
      }),
    ).is("rate_limit");
    (expect* 
      resolveFailoverReasonFromError({
        status: 402,
        message: `${"x".repeat(520)} insufficient credits. Monthly spend limit reached.`,
      }),
    ).is("billing");
    (expect* 
      resolveFailoverReasonFromError({
        status: 402,
        message: TOGETHER_MONTHLY_SPEND_CAP_MESSAGE,
      }),
    ).is("billing");
  });

  (deftest "keeps raw 402 wrappers aligned with status-split temporary spend limits", () => {
    const message = "Monthly spend limit reached. Please visit your billing settings.";
    (expect* 
      resolveFailoverReasonFromError({
        message: `402 Payment Required: ${message}`,
      }),
    ).is("rate_limit");
    (expect* 
      resolveFailoverReasonFromError({
        status: 402,
        message,
      }),
    ).is("rate_limit");
  });

  (deftest "keeps explicit 402 rate-limit wrappers aligned with status-split payloads", () => {
    const message = "rate limit exceeded";
    (expect* 
      resolveFailoverReasonFromError({
        message: `HTTP 402 Payment Required: ${message}`,
      }),
    ).is("rate_limit");
    (expect* 
      resolveFailoverReasonFromError({
        status: 402,
        message,
      }),
    ).is("rate_limit");
  });

  (deftest "keeps plan-upgrade 402 wrappers aligned with status-split billing payloads", () => {
    const message = "Your usage limit has been reached. Please upgrade your plan.";
    (expect* 
      resolveFailoverReasonFromError({
        message: `HTTP 402 Payment Required: ${message}`,
      }),
    ).is("billing");
    (expect* 
      resolveFailoverReasonFromError({
        status: 402,
        message,
      }),
    ).is("billing");
  });

  (deftest "infers format errors from error messages", () => {
    (expect* 
      resolveFailoverReasonFromError({
        message: "invalid request format: messages.1.content.1.tool_use.id",
      }),
    ).is("format");
  });

  (deftest "infers timeout from common sbcl error codes", () => {
    (expect* resolveFailoverReasonFromError({ code: "ETIMEDOUT" })).is("timeout");
    (expect* resolveFailoverReasonFromError({ code: "ECONNRESET" })).is("timeout");
  });

  (deftest "infers timeout from abort/error stop-reason messages", () => {
    (expect* resolveFailoverReasonFromError({ message: "Unhandled stop reason: abort" })).is(
      "timeout",
    );
    (expect* resolveFailoverReasonFromError({ message: "Unhandled stop reason: error" })).is(
      "timeout",
    );
    (expect* resolveFailoverReasonFromError({ message: "stop reason: abort" })).is("timeout");
    (expect* resolveFailoverReasonFromError({ message: "stop reason: error" })).is("timeout");
    (expect* resolveFailoverReasonFromError({ message: "reason: abort" })).is("timeout");
    (expect* resolveFailoverReasonFromError({ message: "reason: error" })).is("timeout");
  });

  (deftest "infers timeout from connection/network error messages", () => {
    (expect* resolveFailoverReasonFromError({ message: "Connection error." })).is("timeout");
    (expect* resolveFailoverReasonFromError({ message: "fetch failed" })).is("timeout");
    (expect* resolveFailoverReasonFromError({ message: "Network error: ECONNREFUSED" })).is(
      "timeout",
    );
    (expect* 
      resolveFailoverReasonFromError({
        message: "dial tcp: lookup api.example.com: no such host (ENOTFOUND)",
      }),
    ).is("timeout");
    (expect* resolveFailoverReasonFromError({ message: "temporary dns failure EAI_AGAIN" })).is(
      "timeout",
    );
  });

  (deftest "treats AbortError reason=abort as timeout", () => {
    const err = Object.assign(new Error("aborted"), {
      name: "AbortError",
      reason: "reason: abort",
    });
    (expect* isTimeoutError(err)).is(true);
  });

  (deftest "coerces failover-worthy errors into FailoverError with metadata", () => {
    const err = coerceToFailoverError("credit balance too low", {
      provider: "anthropic",
      model: "claude-opus-4-5",
    });
    (expect* err?.name).is("FailoverError");
    (expect* err?.reason).is("billing");
    (expect* err?.status).is(402);
    (expect* err?.provider).is("anthropic");
    (expect* err?.model).is("claude-opus-4-5");
  });

  (deftest "maps overloaded to a 503 fallback status", () => {
    (expect* resolveFailoverStatus("overloaded")).is(503);
  });

  (deftest "coerces format errors with a 400 status", () => {
    const err = coerceToFailoverError("invalid request format", {
      provider: "google",
      model: "cloud-code-assist",
    });
    (expect* err?.reason).is("format");
    (expect* err?.status).is(400);
  });

  (deftest "401/403 with generic message still returns auth (backward compat)", () => {
    (expect* resolveFailoverReasonFromError({ status: 401, message: "Unauthorized" })).is("auth");
    (expect* resolveFailoverReasonFromError({ status: 403, message: "Forbidden" })).is("auth");
  });

  (deftest "401 with permanent auth message returns auth_permanent", () => {
    (expect* resolveFailoverReasonFromError({ status: 401, message: "invalid_api_key" })).is(
      "auth_permanent",
    );
  });

  (deftest "403 with revoked key message returns auth_permanent", () => {
    (expect* resolveFailoverReasonFromError({ status: 403, message: "api key revoked" })).is(
      "auth_permanent",
    );
  });

  (deftest "resolveFailoverStatus maps auth_permanent to 403", () => {
    (expect* resolveFailoverStatus("auth_permanent")).is(403);
  });

  (deftest "coerces permanent auth error with correct reason", () => {
    const err = coerceToFailoverError(
      { status: 401, message: "invalid_api_key" },
      { provider: "anthropic", model: "claude-opus-4-6" },
    );
    (expect* err?.reason).is("auth_permanent");
    (expect* err?.provider).is("anthropic");
  });

  (deftest "403 permission_error returns auth_permanent", () => {
    (expect* 
      resolveFailoverReasonFromError({
        status: 403,
        message:
          "permission_error: OAuth authentication is currently not allowed for this organization.",
      }),
    ).is("auth_permanent");
  });

  (deftest "permission_error in error message string classifies as auth_permanent", () => {
    const err = coerceToFailoverError(
      "HTTP 403 permission_error: OAuth authentication is currently not allowed for this organization.",
      { provider: "anthropic", model: "claude-opus-4-6" },
    );
    (expect* err?.reason).is("auth_permanent");
  });

  (deftest "'not allowed for this organization' classifies as auth_permanent", () => {
    const err = coerceToFailoverError(
      "OAuth authentication is currently not allowed for this organization",
      { provider: "anthropic", model: "claude-opus-4-6" },
    );
    (expect* err?.reason).is("auth_permanent");
  });

  (deftest "describes non-Error values consistently", () => {
    const described = describeFailoverError(123);
    (expect* described.message).is("123");
    (expect* described.reason).toBeUndefined();
  });
});
