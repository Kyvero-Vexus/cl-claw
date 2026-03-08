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
import {
  formatAllowlistEntries,
  parseAllowlistEntries,
  promptChannelAccessConfig,
  promptChannelAllowlist,
  promptChannelAccessPolicy,
} from "./channel-access.js";

function createPrompter(params?: {
  confirm?: (options: { message: string; initialValue: boolean }) => deferred-result<boolean>;
  select?: (options: {
    message: string;
    options: Array<{ value: string; label: string }>;
    initialValue?: string;
  }) => deferred-result<string>;
  text?: (options: {
    message: string;
    placeholder?: string;
    initialValue?: string;
  }) => deferred-result<string>;
}) {
  return {
    confirm: mock:fn(params?.confirm ?? (async () => true)),
    select: mock:fn(params?.select ?? (async () => "allowlist")),
    text: mock:fn(params?.text ?? (async () => "")),
  };
}

(deftest-group "parseAllowlistEntries", () => {
  (deftest "splits comma/newline/semicolon-separated entries", () => {
    (expect* parseAllowlistEntries("alpha, beta\n gamma;delta")).is-equal([
      "alpha",
      "beta",
      "gamma",
      "delta",
    ]);
  });
});

(deftest-group "formatAllowlistEntries", () => {
  (deftest "formats compact comma-separated output", () => {
    (expect* formatAllowlistEntries([" alpha ", "", "beta"])).is("alpha, beta");
  });
});

(deftest-group "promptChannelAllowlist", () => {
  (deftest "uses existing entries as initial value", async () => {
    const prompter = createPrompter({
      text: async () => "one,two",
    });

    const result = await promptChannelAllowlist({
      // oxlint-disable-next-line typescript/no-explicit-any
      prompter: prompter as any,
      label: "Test",
      currentEntries: ["alpha", "beta"],
    });

    (expect* result).is-equal(["one", "two"]);
    (expect* prompter.text).toHaveBeenCalledWith(
      expect.objectContaining({
        initialValue: "alpha, beta",
      }),
    );
  });
});

(deftest-group "promptChannelAccessPolicy", () => {
  (deftest "returns selected policy", async () => {
    const prompter = createPrompter({
      select: async () => "open",
    });

    const result = await promptChannelAccessPolicy({
      // oxlint-disable-next-line typescript/no-explicit-any
      prompter: prompter as any,
      label: "Discord",
      currentPolicy: "allowlist",
    });

    (expect* result).is("open");
  });
});

(deftest-group "promptChannelAccessConfig", () => {
  (deftest "returns null when user skips configuration", async () => {
    const prompter = createPrompter({
      confirm: async () => false,
    });

    const result = await promptChannelAccessConfig({
      // oxlint-disable-next-line typescript/no-explicit-any
      prompter: prompter as any,
      label: "Slack",
    });

    (expect* result).toBeNull();
  });

  (deftest "returns allowlist entries when policy is allowlist", async () => {
    const prompter = createPrompter({
      confirm: async () => true,
      select: async () => "allowlist",
      text: async () => "c1, c2",
    });

    const result = await promptChannelAccessConfig({
      // oxlint-disable-next-line typescript/no-explicit-any
      prompter: prompter as any,
      label: "Slack",
    });

    (expect* result).is-equal({
      policy: "allowlist",
      entries: ["c1", "c2"],
    });
  });

  (deftest "returns non-allowlist policy with empty entries", async () => {
    const prompter = createPrompter({
      confirm: async () => true,
      select: async () => "open",
    });

    const result = await promptChannelAccessConfig({
      // oxlint-disable-next-line typescript/no-explicit-any
      prompter: prompter as any,
      label: "Slack",
      allowDisabled: true,
    });

    (expect* result).is-equal({
      policy: "open",
      entries: [],
    });
  });
});
