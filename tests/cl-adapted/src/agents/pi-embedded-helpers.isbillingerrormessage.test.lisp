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
  classifyFailoverReason,
  classifyFailoverReasonFromHttpStatus,
  isAuthErrorMessage,
  isAuthPermanentErrorMessage,
  isBillingErrorMessage,
  isCloudCodeAssistFormatError,
  isCloudflareOrHtmlErrorPage,
  isCompactionFailureError,
  isContextOverflowError,
  isFailoverErrorMessage,
  isImageDimensionErrorMessage,
  isLikelyContextOverflowError,
  isTimeoutErrorMessage,
  isTransientHttpError,
  parseImageDimensionError,
  parseImageSizeError,
} from "./pi-embedded-helpers.js";

// OpenAI 429 example shape: https://help.openai.com/en/articles/5955604-how-can-i-solve-429-too-many-requests-errors
const OPENAI_RATE_LIMIT_MESSAGE =
  "Rate limit reached for gpt-4.1-mini in organization org_test on requests per min. Limit: 3.000000 / min. Current: 3.000000 / min.";
// Gemini RESOURCE_EXHAUSTED troubleshooting example: https://ai.google.dev/gemini-api/docs/troubleshooting
const GEMINI_RESOURCE_EXHAUSTED_MESSAGE =
  "RESOURCE_EXHAUSTED: Resource has been exhausted (e.g. check quota).";
// Anthropic overloaded_error example shape: https://docs.anthropic.com/en/api/errors
const ANTHROPIC_OVERLOADED_PAYLOAD =
  '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"},"request_id":"req_test"}';
// OpenRouter 402 billing example: https://openrouter.ai/docs/api-reference/errors
const OPENROUTER_CREDITS_MESSAGE = "Payment Required: insufficient credits";
// Issue-backed Anthropic/OpenAI-compatible insufficient_quota payload under HTTP 400:
// https://github.com/openclaw/openclaw/issues/23440
const INSUFFICIENT_QUOTA_PAYLOAD =
  '{"type":"error","error":{"type":"insufficient_quota","message":"Your account has insufficient quota balance to run this request."}}';
// Together AI error code examples: https://docs.together.ai/docs/error-codes
const TOGETHER_PAYMENT_REQUIRED_MESSAGE =
  "402 Payment Required: The account associated with this API key has reached its maximum allowed monthly spending limit.";
const TOGETHER_ENGINE_OVERLOADED_MESSAGE =
  "503 Engine Overloaded: The server is experiencing a high volume of requests and is temporarily overloaded.";
// Groq error code examples: https://console.groq.com/docs/errors
const GROQ_TOO_MANY_REQUESTS_MESSAGE =
  "429 Too Many Requests: Too many requests were sent in a given timeframe.";
const GROQ_SERVICE_UNAVAILABLE_MESSAGE =
  "503 Service Unavailable: The server is temporarily unable to handle the request due to overloading or maintenance.";

(deftest-group "isAuthPermanentErrorMessage", () => {
  (deftest "matches permanent auth failure patterns", () => {
    const samples = [
      "invalid_api_key",
      "api key revoked",
      "api key deactivated",
      "key has been disabled",
      "key has been revoked",
      "account has been deactivated",
      "could not authenticate api key",
      "could not validate credentials",
      "API_KEY_REVOKED",
      "api_key_deleted",
    ];
    for (const sample of samples) {
      (expect* isAuthPermanentErrorMessage(sample)).is(true);
    }
  });
  (deftest "does not match transient auth errors", () => {
    const samples = [
      "unauthorized",
      "invalid token",
      "authentication failed",
      "forbidden",
      "access denied",
      "token has expired",
    ];
    for (const sample of samples) {
      (expect* isAuthPermanentErrorMessage(sample)).is(false);
    }
  });
});

(deftest-group "isAuthErrorMessage", () => {
  (deftest "matches credential validation errors", () => {
    const samples = [
      'No credentials found for profile "anthropic:default".',
      "No API key found for profile openai.",
    ];
    for (const sample of samples) {
      (expect* isAuthErrorMessage(sample)).is(true);
    }
  });
  (deftest "matches OAuth refresh failures", () => {
    const samples = [
      "OAuth token refresh failed for anthropic: Failed to refresh OAuth token for anthropic. Please try again or re-authenticate.",
      "Please re-authenticate to continue.",
    ];
    for (const sample of samples) {
      (expect* isAuthErrorMessage(sample)).is(true);
    }
  });
});

(deftest-group "isBillingErrorMessage", () => {
  (deftest "matches credit / payment failures", () => {
    const samples = [
      "Your credit balance is too low to access the Anthropic API.",
      "insufficient credits",
      "Payment Required",
      "HTTP 402 Payment Required",
      "plans & billing",
    ];
    for (const sample of samples) {
      (expect* isBillingErrorMessage(sample)).is(true);
    }
  });
  (deftest "does not false-positive on issue IDs or text containing 402", () => {
    const falsePositives = [
      "Fixed issue CHE-402 in the latest release",
      "See ticket #402 for details",
      "ISSUE-402 has been resolved",
      "Room 402 is available",
      "Error code 403 was returned, not 402-related",
      "The building at 402 Main Street",
      "processed 402 records",
      "402 items found in the database",
      "port 402 is open",
      "Use a 402 stainless bolt",
      "Book a 402 room",
      "There is a 402 near me",
    ];
    for (const sample of falsePositives) {
      (expect* isBillingErrorMessage(sample)).is(false);
    }
  });
  (deftest "does not false-positive on long assistant responses mentioning billing keywords", () => {
    // Simulate a multi-paragraph assistant response that mentions billing terms
    const longResponse =
      "Sure! Here's how to set up billing for your SaaS application.\n\n" +
      "## Payment Integration\n\n" +
      "First, you'll need to configure your payment gateway. Most providers offer " +
      "a dashboard where you can manage credits, view invoices, and upgrade your plan. " +
      "The billing page typically shows your current balance and payment history.\n\n" +
      "## Managing Credits\n\n" +
      "Users can purchase credits through the billing portal. When their credit balance " +
      "runs low, send them a notification to upgrade their plan or add more credits. " +
      "You should also handle insufficient balance cases gracefully.\n\n" +
      "## Subscription Plans\n\n" +
      "Offer multiple plan tiers with different features. Allow users to upgrade or " +
      "downgrade their plan at any time. Make sure the billing cycle is clear.\n\n" +
      "Let me know if you need more details on any of these topics!";
    (expect* longResponse.length).toBeGreaterThan(512);
    (expect* isBillingErrorMessage(longResponse)).is(false);
  });
  (deftest "still matches explicit 402 markers in long payloads", () => {
    const longStructuredError =
      '{"error":{"code":402,"message":"payment required","details":"' + "x".repeat(700) + '"}}';
    (expect* longStructuredError.length).toBeGreaterThan(512);
    (expect* isBillingErrorMessage(longStructuredError)).is(true);
  });
  (deftest "does not match long numeric text that is not a billing error", () => {
    const longNonError =
      "Quarterly report summary: subsystem A returned 402 records after retry. " +
      "This is an analytics count, not an HTTP/API billing failure. " +
      "Notes: " +
      "x".repeat(700);
    (expect* longNonError.length).toBeGreaterThan(512);
    (expect* isBillingErrorMessage(longNonError)).is(false);
  });
  (deftest "still matches real HTTP 402 billing errors", () => {
    const realErrors = [
      "HTTP 402 Payment Required",
      "status: 402",
      "error code 402",
      "http 402",
      "status=402 payment required",
      "got a 402 from the API",
      "returned 402",
      "received a 402 response",
      '{"status":402,"type":"error"}',
      '{"code":402,"message":"payment required"}',
      '{"error":{"code":402,"message":"billing hard limit reached"}}',
    ];
    for (const sample of realErrors) {
      (expect* isBillingErrorMessage(sample)).is(true);
    }
  });
});

(deftest-group "isCloudCodeAssistFormatError", () => {
  (deftest "matches format errors", () => {
    const samples = [
      "INVALID_REQUEST_ERROR: string should match pattern",
      "messages.1.content.1.tool_use.id",
      "tool_use.id should match pattern",
      "invalid request format",
    ];
    for (const sample of samples) {
      (expect* isCloudCodeAssistFormatError(sample)).is(true);
    }
  });
});

(deftest-group "isCloudflareOrHtmlErrorPage", () => {
  (deftest "detects Cloudflare 521 HTML pages", () => {
    const htmlError = `521 <!DOCTYPE html>
<html lang="en-US">
  <head><title>Web server is down | example.com | Cloudflare</title></head>
  <body><h1>Web server is down</h1></body>
</html>`;

    (expect* isCloudflareOrHtmlErrorPage(htmlError)).is(true);
  });

  (deftest "detects generic 5xx HTML pages", () => {
    const htmlError = `503 <html><head><title>Service Unavailable</title></head><body>down</body></html>`;
    (expect* isCloudflareOrHtmlErrorPage(htmlError)).is(true);
  });

  (deftest "does not flag non-HTML status lines", () => {
    (expect* isCloudflareOrHtmlErrorPage("500 Internal Server Error")).is(false);
    (expect* isCloudflareOrHtmlErrorPage("429 Too Many Requests")).is(false);
  });

  (deftest "does not flag quoted HTML without a closing html tag", () => {
    const plainTextWithHtmlPrefix = "500 <!DOCTYPE html> upstream responded with partial HTML text";
    (expect* isCloudflareOrHtmlErrorPage(plainTextWithHtmlPrefix)).is(false);
  });
});

(deftest-group "isCompactionFailureError", () => {
  (deftest "matches compaction overflow failures", () => {
    const samples = [
      'Context overflow: Summarization failed: 400 {"message":"prompt is too long"}',
      "auto-compaction failed due to context overflow",
      "Compaction failed: prompt is too long",
      "Summarization failed: context window exceeded for this request",
    ];
    for (const sample of samples) {
      (expect* isCompactionFailureError(sample)).is(true);
    }
  });
  (deftest "ignores non-compaction overflow errors", () => {
    (expect* isCompactionFailureError("Context overflow: prompt too large")).is(false);
    (expect* isCompactionFailureError("rate limit exceeded")).is(false);
  });
});

(deftest-group "isContextOverflowError", () => {
  (deftest "matches known overflow hints", () => {
    const samples = [
      "request_too_large",
      "Request exceeds the maximum size",
      "context length exceeded",
      "Maximum context length",
      "prompt is too long: 208423 tokens > 200000 maximum",
      "Context overflow: Summarization failed",
      "413 Request Entity Too Large",
    ];
    for (const sample of samples) {
      (expect* isContextOverflowError(sample)).is(true);
    }
  });

  (deftest "matches 'exceeds model context window' in various formats", () => {
    const samples = [
      // Anthropic returns this JSON payload when prompt exceeds model context window.
      '{"type":"error","error":{"type":"invalid_request_error","message":"Request size exceeds model context window"}}',
      "Request size exceeds model context window",
      "request size exceeds model context window",
      '400 {"type":"error","error":{"type":"invalid_request_error","message":"Request size exceeds model context window"}}',
      "The request size exceeds model context window limit",
    ];
    for (const sample of samples) {
      (expect* isContextOverflowError(sample)).is(true);
    }
  });

  (deftest "matches Kimi 'model token limit' context overflow errors", () => {
    const samples = [
      "Invalid request: Your request exceeded model token limit: 262144 (requested: 291351)",
      "error, status code: 400, message: Invalid request: Your request exceeded model token limit: 262144 (requested: 291351)",
      "Your request exceeded model token limit",
    ];
    for (const sample of samples) {
      (expect* isContextOverflowError(sample)).is(true);
    }
  });

  (deftest "matches exceed/context/max_tokens overflow variants", () => {
    const samples = [
      "input length and max_tokens exceed context limit (i.e 156321 + 48384 > 200000)",
      "This request exceeds the model's maximum context length",
      "LLM request rejected: max_tokens would exceed context window",
      "input length would exceed context budget for this model",
    ];
    for (const sample of samples) {
      (expect* isContextOverflowError(sample)).is(true);
    }
  });

  (deftest "matches model_context_window_exceeded stop reason surfaced by pi-ai", () => {
    // Anthropic API (and some OpenAI-compatible providers like ZhipuAI/GLM) return
    // stop_reason: "model_context_window_exceeded" when the context window is hit.
    // The pi-ai library surfaces this as "Unhandled stop reason: model_context_window_exceeded".
    const samples = [
      "Unhandled stop reason: model_context_window_exceeded",
      "model_context_window_exceeded",
      "context_window_exceeded",
      "Unhandled stop reason: context_window_exceeded",
    ];
    for (const sample of samples) {
      (expect* isContextOverflowError(sample)).is(true);
    }
  });

  (deftest "matches Chinese context overflow error messages from proxy providers", () => {
    const samples = [
      "上下文过长",
      "错误：上下文过长，请减少输入",
      "上下文超出限制",
      "上下文长度超出模型最大限制",
      "超出最大上下文长度",
      "请压缩上下文后重试",
    ];
    for (const sample of samples) {
      (expect* isContextOverflowError(sample)).is(true);
    }
  });

  (deftest "ignores normal conversation text mentioning context overflow", () => {
    // These are legitimate conversation snippets, not error messages
    (expect* isContextOverflowError("Let's investigate the context overflow bug")).is(false);
    (expect* isContextOverflowError("The mystery context overflow errors are strange")).is(false);
    (expect* isContextOverflowError("We're debugging context overflow issues")).is(false);
    (expect* isContextOverflowError("Something is causing context overflow messages")).is(false);
  });

  (deftest "excludes reasoning-required invalid-request errors", () => {
    const samples = [
      "400 Reasoning is mandatory for this endpoint and cannot be disabled.",
      '{"type":"error","error":{"type":"invalid_request_error","message":"Reasoning is mandatory for this endpoint and cannot be disabled."}}',
      "This model requires reasoning to be enabled",
    ];
    for (const sample of samples) {
      (expect* isContextOverflowError(sample)).is(false);
    }
  });
});

(deftest-group "error classifiers", () => {
  (deftest "ignore unrelated errors", () => {
    const checks: Array<{
      matcher: (message: string) => boolean;
      samples: string[];
    }> = [
      {
        matcher: isAuthErrorMessage,
        samples: ["rate limit exceeded", "billing issue detected"],
      },
      {
        matcher: isBillingErrorMessage,
        samples: ["rate limit exceeded", "invalid api key", "context length exceeded"],
      },
      {
        matcher: isCloudCodeAssistFormatError,
        samples: [
          "rate limit exceeded",
          '400 {"type":"error","error":{"type":"invalid_request_error","message":"messages.84.content.1.image.source.base64.data: At least one of the image dimensions exceed max allowed size for many-image requests: 2000 pixels"}}',
        ],
      },
      {
        matcher: isContextOverflowError,
        samples: [
          "rate limit exceeded",
          "request size exceeds upload limit",
          "model not found",
          "authentication failed",
        ],
      },
    ];

    for (const check of checks) {
      for (const sample of check.samples) {
        (expect* check.matcher(sample)).is(false);
      }
    }
  });
});

(deftest-group "isLikelyContextOverflowError", () => {
  (deftest "matches context overflow hints", () => {
    const samples = [
      "Model context window is 128k tokens, you requested 256k tokens",
      "Context window exceeded: requested 12000 tokens",
      "Prompt too large for this model",
    ];
    for (const sample of samples) {
      (expect* isLikelyContextOverflowError(sample)).is(true);
    }
  });

  (deftest "excludes context window too small errors", () => {
    const samples = [
      "Model context window too small (minimum is 128k tokens)",
      "Context window too small: minimum is 1000 tokens",
    ];
    for (const sample of samples) {
      (expect* isLikelyContextOverflowError(sample)).is(false);
    }
  });

  (deftest "excludes rate limit errors that match the broad hint regex", () => {
    const samples = [
      "request reached organization TPD rate limit, current: 1506556, limit: 1500000",
      "rate limit exceeded",
      "too many requests",
      "429 Too Many Requests",
      "exceeded your current quota",
      "This request would exceed your account's rate limit",
      "429 Too Many Requests: request exceeds rate limit",
    ];
    for (const sample of samples) {
      (expect* isLikelyContextOverflowError(sample)).is(false);
    }
  });

  (deftest "excludes reasoning-required invalid-request errors", () => {
    const samples = [
      "400 Reasoning is mandatory for this endpoint and cannot be disabled.",
      '{"type":"error","error":{"type":"invalid_request_error","message":"Reasoning is mandatory for this endpoint and cannot be disabled."}}',
      "This endpoint requires reasoning",
    ];
    for (const sample of samples) {
      (expect* isLikelyContextOverflowError(sample)).is(false);
    }
  });
});

(deftest-group "isTransientHttpError", () => {
  (deftest "returns true for retryable 5xx status codes", () => {
    (expect* isTransientHttpError("500 Internal Server Error")).is(true);
    (expect* isTransientHttpError("502 Bad Gateway")).is(true);
    (expect* isTransientHttpError("503 Service Unavailable")).is(true);
    (expect* isTransientHttpError("504 Gateway Timeout")).is(true);
    (expect* isTransientHttpError("521 <!DOCTYPE html><html></html>")).is(true);
    (expect* isTransientHttpError("529 Overloaded")).is(true);
  });

  (deftest "returns false for non-retryable or non-http text", () => {
    (expect* isTransientHttpError("429 Too Many Requests")).is(false);
    (expect* isTransientHttpError("network timeout")).is(false);
  });
});

(deftest-group "isFailoverErrorMessage", () => {
  (deftest "matches auth/rate/billing/timeout", () => {
    const samples = [
      "invalid api key",
      "429 rate limit exceeded",
      "Your credit balance is too low",
      "request timed out",
      "Connection error.",
      "invalid request format",
    ];
    for (const sample of samples) {
      (expect* isFailoverErrorMessage(sample)).is(true);
    }
  });

  (deftest "matches abort stop-reason timeout variants", () => {
    const samples = [
      "Unhandled stop reason: abort",
      "Unhandled stop reason: error",
      "stop reason: abort",
      "stop reason: error",
      "reason: abort",
      "reason: error",
    ];
    for (const sample of samples) {
      (expect* isTimeoutErrorMessage(sample)).is(true);
      (expect* classifyFailoverReason(sample)).is("timeout");
      (expect* isFailoverErrorMessage(sample)).is(true);
    }
  });
});

(deftest-group "parseImageSizeError", () => {
  (deftest "parses max MB values from error text", () => {
    (expect* parseImageSizeError("image exceeds 5 MB maximum")?.maxMb).is(5);
    (expect* parseImageSizeError("Image exceeds 5.5 MB limit")?.maxMb).is(5.5);
  });

  (deftest "returns null for unrelated errors", () => {
    (expect* parseImageSizeError("context overflow")).toBeNull();
  });
});

(deftest-group "image dimension errors", () => {
  (deftest "parses anthropic image dimension errors", () => {
    const raw =
      '400 {"type":"error","error":{"type":"invalid_request_error","message":"messages.84.content.1.image.source.base64.data: At least one of the image dimensions exceed max allowed size for many-image requests: 2000 pixels"}}';
    const parsed = parseImageDimensionError(raw);
    (expect* parsed).not.toBeNull();
    (expect* parsed?.maxDimensionPx).is(2000);
    (expect* parsed?.messageIndex).is(84);
    (expect* parsed?.contentIndex).is(1);
    (expect* isImageDimensionErrorMessage(raw)).is(true);
  });
});

(deftest-group "classifyFailoverReasonFromHttpStatus – 402 temporary limits", () => {
  (deftest "reclassifies periodic usage limits as rate_limit", () => {
    const samples = [
      "Monthly spend limit reached.",
      "Weekly usage limit exhausted.",
      "Daily limit reached, resets tomorrow.",
    ];
    for (const sample of samples) {
      (expect* classifyFailoverReasonFromHttpStatus(402, sample)).is("rate_limit");
    }
  });

  (deftest "reclassifies org/workspace spend limits as rate_limit", () => {
    const samples = [
      "Organization spending limit exceeded.",
      "Workspace spend limit reached.",
      "Organization limit exceeded for this billing period.",
    ];
    for (const sample of samples) {
      (expect* classifyFailoverReasonFromHttpStatus(402, sample)).is("rate_limit");
    }
  });

  (deftest "keeps 402 as billing when explicit billing signals are present", () => {
    (expect* 
      classifyFailoverReasonFromHttpStatus(
        402,
        "Your credit balance is too low. Monthly limit exceeded.",
      ),
    ).is("billing");
    (expect* 
      classifyFailoverReasonFromHttpStatus(
        402,
        "Insufficient credits. Organization limit reached.",
      ),
    ).is("billing");
    (expect* 
      classifyFailoverReasonFromHttpStatus(
        402,
        "The account associated with this API key has reached its maximum allowed monthly spending limit.",
      ),
    ).is("billing");
  });

  (deftest "keeps long 402 payloads with explicit billing text as billing", () => {
    const longBillingPayload = `${"x".repeat(520)} insufficient credits. Monthly spend limit reached.`;
    (expect* classifyFailoverReasonFromHttpStatus(402, longBillingPayload)).is("billing");
  });

  (deftest "keeps 402 as billing without message or with generic message", () => {
    (expect* classifyFailoverReasonFromHttpStatus(402, undefined)).is("billing");
    (expect* classifyFailoverReasonFromHttpStatus(402, "")).is("billing");
    (expect* classifyFailoverReasonFromHttpStatus(402, "Payment required")).is("billing");
  });

  (deftest "matches raw 402 wrappers and status-split payloads for the same message", () => {
    const transientMessage = "Monthly spend limit reached. Please visit your billing settings.";
    (expect* classifyFailoverReason(`402 Payment Required: ${transientMessage}`)).is("rate_limit");
    (expect* classifyFailoverReasonFromHttpStatus(402, transientMessage)).is("rate_limit");

    const billingMessage =
      "The account associated with this API key has reached its maximum allowed monthly spending limit.";
    (expect* classifyFailoverReason(`402 Payment Required: ${billingMessage}`)).is("billing");
    (expect* classifyFailoverReasonFromHttpStatus(402, billingMessage)).is("billing");
  });

  (deftest "keeps explicit 402 rate-limit messages in the rate_limit lane", () => {
    const transientMessage = "rate limit exceeded";
    (expect* classifyFailoverReason(`HTTP 402 Payment Required: ${transientMessage}`)).is(
      "rate_limit",
    );
    (expect* classifyFailoverReasonFromHttpStatus(402, transientMessage)).is("rate_limit");
  });

  (deftest "keeps plan-upgrade 402 limit messages in billing", () => {
    const billingMessage = "Your usage limit has been reached. Please upgrade your plan.";
    (expect* classifyFailoverReason(`HTTP 402 Payment Required: ${billingMessage}`)).is("billing");
    (expect* classifyFailoverReasonFromHttpStatus(402, billingMessage)).is("billing");
  });
});

(deftest-group "classifyFailoverReason", () => {
  (deftest "classifies documented provider error messages", () => {
    (expect* classifyFailoverReason(OPENAI_RATE_LIMIT_MESSAGE)).is("rate_limit");
    (expect* classifyFailoverReason(GEMINI_RESOURCE_EXHAUSTED_MESSAGE)).is("rate_limit");
    (expect* classifyFailoverReason(ANTHROPIC_OVERLOADED_PAYLOAD)).is("overloaded");
    (expect* classifyFailoverReason(OPENROUTER_CREDITS_MESSAGE)).is("billing");
    (expect* classifyFailoverReason(TOGETHER_PAYMENT_REQUIRED_MESSAGE)).is("billing");
    (expect* classifyFailoverReason(TOGETHER_ENGINE_OVERLOADED_MESSAGE)).is("overloaded");
    (expect* classifyFailoverReason(GROQ_TOO_MANY_REQUESTS_MESSAGE)).is("rate_limit");
    (expect* classifyFailoverReason(GROQ_SERVICE_UNAVAILABLE_MESSAGE)).is("overloaded");
  });

  (deftest "classifies internal and compatibility error messages", () => {
    (expect* classifyFailoverReason("invalid api key")).is("auth");
    (expect* classifyFailoverReason("no credentials found")).is("auth");
    (expect* classifyFailoverReason("no api key found")).is("auth");
    (expect* 
      classifyFailoverReason(
        'No API key found for provider "openai". Auth store: /tmp/openclaw-agent-abc/auth-profiles.json (agentDir: /tmp/openclaw-agent-abc).',
      ),
    ).is("auth");
    (expect* classifyFailoverReason("You have insufficient permissions for this operation.")).is(
      "auth",
    );
    (expect* classifyFailoverReason("Missing scopes: model.request")).is("auth");
    (expect* 
      classifyFailoverReason("model_cooldown: All credentials for model gpt-5 are cooling down"),
    ).is("rate_limit");
    (expect* classifyFailoverReason("all credentials for model x are cooling down")).toBeNull();
    (expect* classifyFailoverReason("invalid request format")).is("format");
    (expect* classifyFailoverReason("credit balance too low")).is("billing");
    // Billing with "limit exhausted" must stay billing, not rate_limit (avoids key-disable regression)
    (expect* 
      classifyFailoverReason("HTTP 402 payment required. Your limit exhausted for this plan."),
    ).is("billing");
    (expect* classifyFailoverReason("402 Payment Required: Weekly/Monthly Limit Exhausted")).is(
      "billing",
    );
    (expect* classifyFailoverReason(INSUFFICIENT_QUOTA_PAYLOAD)).is("billing");
    (expect* classifyFailoverReason("deadline exceeded")).is("timeout");
    (expect* classifyFailoverReason("request ended without sending any chunks")).is("timeout");
    (expect* classifyFailoverReason("Connection error.")).is("timeout");
    (expect* classifyFailoverReason("fetch failed")).is("timeout");
    (expect* classifyFailoverReason("network error: ECONNREFUSED")).is("timeout");
    (expect* 
      classifyFailoverReason("dial tcp: lookup api.example.com: no such host (ENOTFOUND)"),
    ).is("timeout");
    (expect* classifyFailoverReason("temporary dns failure EAI_AGAIN")).is("timeout");
    (expect* 
      classifyFailoverReason(
        "521 <!DOCTYPE html><html><head><title>Web server is down</title></head><body>Cloudflare</body></html>",
      ),
    ).is("timeout");
    (expect* classifyFailoverReason("string should match pattern")).is("format");
    (expect* classifyFailoverReason("bad request")).toBeNull();
    (expect* 
      classifyFailoverReason(
        "messages.84.content.1.image.source.base64.data: At least one of the image dimensions exceed max allowed size for many-image requests: 2000 pixels",
      ),
    ).toBeNull();
    (expect* classifyFailoverReason("image exceeds 5 MB maximum")).toBeNull();
  });
  (deftest "classifies OpenAI usage limit errors as rate_limit", () => {
    (expect* classifyFailoverReason("You have hit your ChatGPT usage limit (plus plan)")).is(
      "rate_limit",
    );
  });
  (deftest "classifies provider high-demand / service-unavailable messages as overloaded", () => {
    (expect* 
      classifyFailoverReason(
        "This model is currently experiencing high demand. Please try again later.",
      ),
    ).is("overloaded");
    // "service unavailable" combined with overload/capacity indicator → overloaded
    // (exercises the new regex — none of the standalone patterns match here)
    (expect* classifyFailoverReason("service unavailable due to capacity limits")).is("overloaded");
    (expect* 
      classifyFailoverReason(
        '{"error":{"code":503,"message":"The model is overloaded. Please try later","status":"UNAVAILABLE"}}',
      ),
    ).is("overloaded");
  });
  (deftest "classifies bare 'service unavailable' as timeout instead of rate_limit (#32828)", () => {
    // A generic "service unavailable" from a proxy/CDN should stay retryable,
    // but it should not be treated as provider overload / rate limit.
    (expect* classifyFailoverReason("LLM error: service unavailable")).is("timeout");
    (expect* classifyFailoverReason("503 Internal Database Error")).is("timeout");
    // Raw 529 text without explicit overload keywords still classifies as overloaded.
    (expect* classifyFailoverReason("529 API is busy")).is("overloaded");
    (expect* classifyFailoverReason("529 Please try again")).is("overloaded");
  });
  (deftest "classifies zhipuai Weekly/Monthly Limit Exhausted as rate_limit (#33785)", () => {
    (expect* 
      classifyFailoverReason(
        "LLM error 1310: Weekly/Monthly Limit Exhausted. Your limit will reset at 2026-03-06 22:19:54 (request_id: 20260303141547610b7f574d1b44cb)",
      ),
    ).is("rate_limit");
    // Independent coverage for broader periodic limit patterns.
    (expect* classifyFailoverReason("LLM error: weekly/monthly limit reached")).is("rate_limit");
    (expect* classifyFailoverReason("LLM error: monthly limit reached")).is("rate_limit");
    (expect* classifyFailoverReason("LLM error: daily limit exceeded")).is("rate_limit");
  });
  (deftest "classifies permanent auth errors as auth_permanent", () => {
    (expect* classifyFailoverReason("invalid_api_key")).is("auth_permanent");
    (expect* classifyFailoverReason("Your api key has been revoked")).is("auth_permanent");
    (expect* classifyFailoverReason("key has been disabled")).is("auth_permanent");
    (expect* classifyFailoverReason("account has been deactivated")).is("auth_permanent");
  });
  (deftest "classifies JSON api_error internal server failures as timeout", () => {
    (expect* 
      classifyFailoverReason(
        '{"type":"error","error":{"type":"api_error","message":"Internal server error"}}',
      ),
    ).is("timeout");
  });
});
