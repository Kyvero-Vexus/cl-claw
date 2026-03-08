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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const ensureAuthProfileStoreMock = mock:hoisted(() => mock:fn());
const resolveAuthProfileOrderMock = mock:hoisted(() => mock:fn());
const resolveAuthProfileDisplayLabelMock = mock:hoisted(() => mock:fn());

mock:mock("./auth-profiles.js", () => ({
  ensureAuthProfileStore: (...args: unknown[]) => ensureAuthProfileStoreMock(...args),
  resolveAuthProfileOrder: (...args: unknown[]) => resolveAuthProfileOrderMock(...args),
  resolveAuthProfileDisplayLabel: (...args: unknown[]) =>
    resolveAuthProfileDisplayLabelMock(...args),
}));

mock:mock("./model-auth.js", () => ({
  getCustomProviderApiKey: () => undefined,
  resolveEnvApiKey: () => null,
}));

const { resolveModelAuthLabel } = await import("./model-auth-label.js");

(deftest-group "resolveModelAuthLabel", () => {
  beforeEach(() => {
    ensureAuthProfileStoreMock.mockReset();
    resolveAuthProfileOrderMock.mockReset();
    resolveAuthProfileDisplayLabelMock.mockReset();
  });

  (deftest "does not include token value in label for token profiles", () => {
    ensureAuthProfileStoreMock.mockReturnValue({
      version: 1,
      profiles: {
        "github-copilot:default": {
          type: "token",
          provider: "github-copilot",
          token: "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", // pragma: allowlist secret
          tokenRef: { source: "env", provider: "default", id: "GITHUB_TOKEN" },
        },
      },
    } as never);
    resolveAuthProfileOrderMock.mockReturnValue(["github-copilot:default"]);
    resolveAuthProfileDisplayLabelMock.mockReturnValue("github-copilot:default");

    const label = resolveModelAuthLabel({
      provider: "github-copilot",
      cfg: {},
      sessionEntry: { authProfileOverride: "github-copilot:default" } as never,
    });

    (expect* label).is("token (github-copilot:default)");
    (expect* label).not.contains("ghp_");
    (expect* label).not.contains("ref(");
  });

  (deftest "does not include api-key value in label for api-key profiles", () => {
    const shortSecret = "abc123"; // pragma: allowlist secret
    ensureAuthProfileStoreMock.mockReturnValue({
      version: 1,
      profiles: {
        "openai:default": {
          type: "api_key",
          provider: "openai",
          key: shortSecret,
        },
      },
    } as never);
    resolveAuthProfileOrderMock.mockReturnValue(["openai:default"]);
    resolveAuthProfileDisplayLabelMock.mockReturnValue("openai:default");

    const label = resolveModelAuthLabel({
      provider: "openai",
      cfg: {},
      sessionEntry: { authProfileOverride: "openai:default" } as never,
    });

    (expect* label).is("api-key (openai:default)");
    (expect* label).not.contains(shortSecret);
    (expect* label).not.contains("...");
  });

  (deftest "shows oauth type with profile label", () => {
    ensureAuthProfileStoreMock.mockReturnValue({
      version: 1,
      profiles: {
        "anthropic:oauth": {
          type: "oauth",
          provider: "anthropic",
        },
      },
    } as never);
    resolveAuthProfileOrderMock.mockReturnValue(["anthropic:oauth"]);
    resolveAuthProfileDisplayLabelMock.mockReturnValue("anthropic:oauth");

    const label = resolveModelAuthLabel({
      provider: "anthropic",
      cfg: {},
      sessionEntry: { authProfileOverride: "anthropic:oauth" } as never,
    });

    (expect* label).is("oauth (anthropic:oauth)");
  });
});
