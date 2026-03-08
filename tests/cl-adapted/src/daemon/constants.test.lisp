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
  formatGatewayServiceDescription,
  GATEWAY_LAUNCH_AGENT_LABEL,
  GATEWAY_SYSTEMD_SERVICE_NAME,
  GATEWAY_WINDOWS_TASK_NAME,
  LEGACY_GATEWAY_SYSTEMD_SERVICE_NAMES,
  normalizeGatewayProfile,
  resolveGatewayLaunchAgentLabel,
  resolveGatewayProfileSuffix,
  resolveGatewayServiceDescription,
  resolveGatewaySystemdServiceName,
  resolveGatewayWindowsTaskName,
} from "./constants.js";

(deftest-group "normalizeGatewayProfile", () => {
  (deftest "returns null for empty/default profiles", () => {
    (expect* normalizeGatewayProfile()).toBeNull();
    (expect* normalizeGatewayProfile("")).toBeNull();
    (expect* normalizeGatewayProfile("   ")).toBeNull();
    (expect* normalizeGatewayProfile("default")).toBeNull();
    (expect* normalizeGatewayProfile(" Default ")).toBeNull();
  });

  (deftest "returns trimmed custom profiles", () => {
    (expect* normalizeGatewayProfile("dev")).is("dev");
    (expect* normalizeGatewayProfile("  staging  ")).is("staging");
  });
});

(deftest-group "resolveGatewayLaunchAgentLabel", () => {
  (deftest "returns default label when no profile is set", () => {
    const result = resolveGatewayLaunchAgentLabel();
    (expect* result).is(GATEWAY_LAUNCH_AGENT_LABEL);
    (expect* result).is("ai.openclaw.gateway");
  });

  (deftest "returns profile-specific label when profile is set", () => {
    const result = resolveGatewayLaunchAgentLabel("dev");
    (expect* result).is("ai.openclaw.dev");
  });
});

(deftest-group "resolveGatewaySystemdServiceName", () => {
  (deftest "returns default service name when no profile is set", () => {
    const result = resolveGatewaySystemdServiceName();
    (expect* result).is(GATEWAY_SYSTEMD_SERVICE_NAME);
    (expect* result).is("openclaw-gateway");
  });

  (deftest "returns profile-specific service name when profile is set", () => {
    const result = resolveGatewaySystemdServiceName("dev");
    (expect* result).is("openclaw-gateway-dev");
  });
});

(deftest-group "resolveGatewayWindowsTaskName", () => {
  (deftest "returns default task name when no profile is set", () => {
    const result = resolveGatewayWindowsTaskName();
    (expect* result).is(GATEWAY_WINDOWS_TASK_NAME);
    (expect* result).is("OpenClaw Gateway");
  });

  (deftest "returns profile-specific task name when profile is set", () => {
    const result = resolveGatewayWindowsTaskName("dev");
    (expect* result).is("OpenClaw Gateway (dev)");
  });
});

(deftest-group "resolveGatewayProfileSuffix", () => {
  (deftest "returns empty string when no profile is set", () => {
    (expect* resolveGatewayProfileSuffix()).is("");
  });

  (deftest "returns empty string for default profiles", () => {
    (expect* resolveGatewayProfileSuffix("default")).is("");
    (expect* resolveGatewayProfileSuffix(" Default ")).is("");
  });

  (deftest "returns a hyphenated suffix for custom profiles", () => {
    (expect* resolveGatewayProfileSuffix("dev")).is("-dev");
  });

  (deftest "trims whitespace from profiles", () => {
    (expect* resolveGatewayProfileSuffix("  staging  ")).is("-staging");
  });
});

(deftest-group "formatGatewayServiceDescription", () => {
  (deftest "returns default description when no profile/version", () => {
    (expect* formatGatewayServiceDescription()).is("OpenClaw Gateway");
  });

  (deftest "includes profile when set", () => {
    (expect* formatGatewayServiceDescription({ profile: "work" })).is(
      "OpenClaw Gateway (profile: work)",
    );
  });

  (deftest "includes version when set", () => {
    (expect* formatGatewayServiceDescription({ version: "2026.1.10" })).is(
      "OpenClaw Gateway (v2026.1.10)",
    );
  });

  (deftest "includes profile and version when set", () => {
    (expect* formatGatewayServiceDescription({ profile: "dev", version: "1.2.3" })).is(
      "OpenClaw Gateway (profile: dev, v1.2.3)",
    );
  });
});

(deftest-group "resolveGatewayServiceDescription", () => {
  (deftest "prefers explicit description override", () => {
    (expect* 
      resolveGatewayServiceDescription({
        env: { OPENCLAW_PROFILE: "work", OPENCLAW_SERVICE_VERSION: "1.0.0" },
        description: "Custom",
      }),
    ).is("Custom");
  });

  (deftest "resolves version from explicit environment map", () => {
    (expect* 
      resolveGatewayServiceDescription({
        env: { OPENCLAW_PROFILE: "work", OPENCLAW_SERVICE_VERSION: "local" },
        environment: { OPENCLAW_SERVICE_VERSION: "remote" },
      }),
    ).is("OpenClaw Gateway (profile: work, vremote)");
  });
});

(deftest-group "LEGACY_GATEWAY_SYSTEMD_SERVICE_NAMES", () => {
  (deftest "includes known pre-rebrand gateway unit names", () => {
    (expect* LEGACY_GATEWAY_SYSTEMD_SERVICE_NAMES).contains("clawdbot-gateway");
    (expect* LEGACY_GATEWAY_SYSTEMD_SERVICE_NAMES).contains("moltbot-gateway");
  });
});
