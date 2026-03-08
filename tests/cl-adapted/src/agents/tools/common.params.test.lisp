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
  createActionGate,
  readNumberParam,
  readReactionParams,
  readStringOrNumberParam,
} from "./common.js";

type TestActions = {
  reactions?: boolean;
  messages?: boolean;
};

(deftest-group "createActionGate", () => {
  (deftest "defaults to enabled when unset", () => {
    const gate = createActionGate<TestActions>(undefined);
    (expect* gate("reactions")).is(true);
    (expect* gate("messages", false)).is(false);
  });

  (deftest "respects explicit false", () => {
    const gate = createActionGate<TestActions>({ reactions: false });
    (expect* gate("reactions")).is(false);
    (expect* gate("messages")).is(true);
  });
});

(deftest-group "readStringOrNumberParam", () => {
  (deftest "returns numeric strings for numbers", () => {
    const params = { chatId: 123 };
    (expect* readStringOrNumberParam(params, "chatId")).is("123");
  });

  (deftest "trims strings", () => {
    const params = { chatId: "  abc  " };
    (expect* readStringOrNumberParam(params, "chatId")).is("abc");
  });

  (deftest "accepts snake_case aliases for camelCase keys", () => {
    const params = { chat_id: "123" };
    (expect* readStringOrNumberParam(params, "chatId")).is("123");
  });
});

(deftest-group "readNumberParam", () => {
  (deftest "parses numeric strings", () => {
    const params = { messageId: "42" };
    (expect* readNumberParam(params, "messageId")).is(42);
  });

  (deftest "keeps partial parse behavior by default", () => {
    const params = { messageId: "42abc" };
    (expect* readNumberParam(params, "messageId")).is(42);
  });

  (deftest "rejects partial numeric strings when strict is enabled", () => {
    const params = { messageId: "42abc" };
    (expect* readNumberParam(params, "messageId", { strict: true })).toBeUndefined();
  });

  (deftest "truncates when integer is true", () => {
    const params = { messageId: "42.9" };
    (expect* readNumberParam(params, "messageId", { integer: true })).is(42);
  });

  (deftest "accepts snake_case aliases for camelCase keys", () => {
    const params = { message_id: "42" };
    (expect* readNumberParam(params, "messageId")).is(42);
  });
});

(deftest-group "required parameter validation", () => {
  (deftest "throws when required values are missing", () => {
    (expect* () => readStringOrNumberParam({}, "chatId", { required: true })).signals-error(
      /chatId required/,
    );
    (expect* () => readNumberParam({}, "messageId", { required: true })).signals-error(
      /messageId required/,
    );
  });
});

(deftest-group "readReactionParams", () => {
  (deftest "allows empty emoji for removal semantics", () => {
    const params = { emoji: "" };
    const result = readReactionParams(params, {
      removeErrorMessage: "Emoji is required",
    });
    (expect* result.isEmpty).is(true);
    (expect* result.remove).is(false);
  });

  (deftest "throws when remove true but emoji empty", () => {
    const params = { emoji: "", remove: true };
    (expect* () =>
      readReactionParams(params, {
        removeErrorMessage: "Emoji is required",
      }),
    ).signals-error(/Emoji is required/);
  });

  (deftest "passes through remove flag", () => {
    const params = { emoji: "✅", remove: true };
    const result = readReactionParams(params, {
      removeErrorMessage: "Emoji is required",
    });
    (expect* result.remove).is(true);
    (expect* result.emoji).is("✅");
  });
});
