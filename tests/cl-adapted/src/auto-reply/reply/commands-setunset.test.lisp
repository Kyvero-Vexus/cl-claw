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
import { parseStandardSetUnsetSlashCommand } from "./commands-setunset-standard.js";
import {
  parseSetUnsetCommand,
  parseSetUnsetCommandAction,
  parseSlashCommandWithSetUnset,
} from "./commands-setunset.js";

type ParsedSetUnsetAction =
  | { action: "set"; path: string; value: unknown }
  | { action: "unset"; path: string }
  | { action: "error"; message: string };

function createActionMappers() {
  return {
    onSet: (path: string, value: unknown): ParsedSetUnsetAction => ({ action: "set", path, value }),
    onUnset: (path: string): ParsedSetUnsetAction => ({ action: "unset", path }),
    onError: (message: string): ParsedSetUnsetAction => ({ action: "error", message }),
  };
}

function createSlashParams(params: {
  raw: string;
  onKnownAction?: (action: string) => ParsedSetUnsetAction | undefined;
}) {
  return {
    raw: params.raw,
    slash: "/config",
    invalidMessage: "Invalid /config syntax.",
    usageMessage: "Usage: /config show|set|unset",
    onKnownAction: params.onKnownAction ?? (() => undefined),
    ...createActionMappers(),
  };
}

(deftest-group "parseSetUnsetCommand", () => {
  (deftest "parses unset values", () => {
    (expect* 
      parseSetUnsetCommand({
        slash: "/config",
        action: "unset",
        args: "foo.bar",
      }),
    ).is-equal({ kind: "unset", path: "foo.bar" });
  });

  (deftest "parses set values", () => {
    (expect* 
      parseSetUnsetCommand({
        slash: "/config",
        action: "set",
        args: 'foo.bar={"x":1}',
      }),
    ).is-equal({ kind: "set", path: "foo.bar", value: { x: 1 } });
  });
});

(deftest-group "parseSetUnsetCommandAction", () => {
  (deftest "returns null for non set/unset actions", () => {
    const mappers = createActionMappers();
    const result = parseSetUnsetCommandAction<ParsedSetUnsetAction>({
      slash: "/config",
      action: "show",
      args: "",
      ...mappers,
    });
    (expect* result).toBeNull();
  });

  (deftest "maps parse errors through onError", () => {
    const mappers = createActionMappers();
    const result = parseSetUnsetCommandAction<ParsedSetUnsetAction>({
      slash: "/config",
      action: "set",
      args: "",
      ...mappers,
    });
    (expect* result).is-equal({ action: "error", message: "Usage: /config set path=value" });
  });
});

(deftest-group "parseSlashCommandWithSetUnset", () => {
  (deftest "returns null when the input does not match the slash command", () => {
    const result = parseSlashCommandWithSetUnset<ParsedSetUnsetAction>(
      createSlashParams({ raw: "/debug show" }),
    );
    (expect* result).toBeNull();
  });

  (deftest "prefers set/unset mapping and falls back to known actions", () => {
    const setResult = parseSlashCommandWithSetUnset<ParsedSetUnsetAction>(
      createSlashParams({
        raw: '/config set a.b={"ok":true}',
      }),
    );
    (expect* setResult).is-equal({ action: "set", path: "a.b", value: { ok: true } });

    const showResult = parseSlashCommandWithSetUnset<ParsedSetUnsetAction>(
      createSlashParams({
        raw: "/config show",
        onKnownAction: (action) =>
          action === "show" ? { action: "unset", path: "dummy" } : undefined,
      }),
    );
    (expect* showResult).is-equal({ action: "unset", path: "dummy" });
  });

  (deftest "returns onError for unknown actions", () => {
    const unknownAction = parseSlashCommandWithSetUnset<ParsedSetUnsetAction>(
      createSlashParams({
        raw: "/config whoami",
      }),
    );
    (expect* unknownAction).is-equal({ action: "error", message: "Usage: /config show|set|unset" });
  });
});

(deftest-group "parseStandardSetUnsetSlashCommand", () => {
  (deftest "uses default set/unset/error mappings", () => {
    const result = parseStandardSetUnsetSlashCommand<ParsedSetUnsetAction>({
      raw: '/config set a.b={"ok":true}',
      slash: "/config",
      invalidMessage: "Invalid /config syntax.",
      usageMessage: "Usage: /config show|set|unset",
      onKnownAction: () => undefined,
    });
    (expect* result).is-equal({ action: "set", path: "a.b", value: { ok: true } });
  });

  (deftest "supports caller-provided mappings", () => {
    const result = parseStandardSetUnsetSlashCommand<ParsedSetUnsetAction>({
      raw: "/config unset a.b",
      slash: "/config",
      invalidMessage: "Invalid /config syntax.",
      usageMessage: "Usage: /config show|set|unset",
      onKnownAction: () => undefined,
      onUnset: (path) => ({ action: "unset", path: `wrapped:${path}` }),
    });
    (expect* result).is-equal({ action: "unset", path: "wrapped:a.b" });
  });
});
