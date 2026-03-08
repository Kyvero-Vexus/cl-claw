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
import {
  buildAuthHealthSummary,
  DEFAULT_OAUTH_WARN_MS,
  formatRemainingShort,
} from "./auth-health.js";

(deftest-group "buildAuthHealthSummary", () => {
  const now = 1_700_000_000_000;
  const profileStatuses = (summary: ReturnType<typeof buildAuthHealthSummary>) =>
    Object.fromEntries(summary.profiles.map((profile) => [profile.profileId, profile.status]));
  const profileReasonCodes = (summary: ReturnType<typeof buildAuthHealthSummary>) =>
    Object.fromEntries(summary.profiles.map((profile) => [profile.profileId, profile.reasonCode]));

  afterEach(() => {
    mock:restoreAllMocks();
  });

  (deftest "classifies OAuth and API key profiles", () => {
    mock:spyOn(Date, "now").mockReturnValue(now);
    const store = {
      version: 1,
      profiles: {
        "anthropic:ok": {
          type: "oauth" as const,
          provider: "anthropic",
          access: "access",
          refresh: "refresh",
          expires: now + DEFAULT_OAUTH_WARN_MS + 60_000,
        },
        "anthropic:expiring": {
          type: "oauth" as const,
          provider: "anthropic",
          access: "access",
          refresh: "refresh",
          expires: now + 10_000,
        },
        "anthropic:expired": {
          type: "oauth" as const,
          provider: "anthropic",
          access: "access",
          refresh: "refresh",
          expires: now - 10_000,
        },
        "anthropic:api": {
          type: "api_key" as const,
          provider: "anthropic",
          key: "sk-ant-api",
        },
      },
    };

    const summary = buildAuthHealthSummary({
      store,
      warnAfterMs: DEFAULT_OAUTH_WARN_MS,
    });

    const statuses = profileStatuses(summary);

    (expect* statuses["anthropic:ok"]).is("ok");
    // OAuth credentials with refresh tokens are auto-renewable, so they report "ok"
    (expect* statuses["anthropic:expiring"]).is("ok");
    (expect* statuses["anthropic:expired"]).is("ok");
    (expect* statuses["anthropic:api"]).is("static");

    const provider = summary.providers.find((entry) => entry.provider === "anthropic");
    (expect* provider?.status).is("ok");
  });

  (deftest "reports expired for OAuth without a refresh token", () => {
    mock:spyOn(Date, "now").mockReturnValue(now);
    const store = {
      version: 1,
      profiles: {
        "google:no-refresh": {
          type: "oauth" as const,
          provider: "google-antigravity",
          access: "access",
          refresh: "",
          expires: now - 10_000,
        },
      },
    };

    const summary = buildAuthHealthSummary({
      store,
      warnAfterMs: DEFAULT_OAUTH_WARN_MS,
    });

    const statuses = profileStatuses(summary);

    (expect* statuses["google:no-refresh"]).is("expired");
  });

  (deftest "marks token profiles with invalid expires as missing with reason code", () => {
    mock:spyOn(Date, "now").mockReturnValue(now);
    const store = {
      version: 1,
      profiles: {
        "github-copilot:invalid-expires": {
          type: "token" as const,
          provider: "github-copilot",
          token: "gh-token",
          expires: 0,
        },
      },
    };

    const summary = buildAuthHealthSummary({
      store,
      warnAfterMs: DEFAULT_OAUTH_WARN_MS,
    });
    const statuses = profileStatuses(summary);
    const reasonCodes = profileReasonCodes(summary);

    (expect* statuses["github-copilot:invalid-expires"]).is("missing");
    (expect* reasonCodes["github-copilot:invalid-expires"]).is("invalid_expires");
  });
});

(deftest-group "formatRemainingShort", () => {
  (deftest "supports an explicit under-minute label override", () => {
    (expect* formatRemainingShort(20_000)).is("1m");
    (expect* formatRemainingShort(20_000, { underMinuteLabel: "soon" })).is("soon");
  });
});
