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
import { hasPollCreationParams, resolveTelegramPollVisibility } from "./poll-params.js";

(deftest-group "poll params", () => {
  (deftest "does not treat explicit false booleans as poll creation params", () => {
    (expect* 
      hasPollCreationParams({
        pollMulti: false,
        pollAnonymous: false,
        pollPublic: false,
      }),
    ).is(false);
  });

  it.each([{ key: "pollMulti" }, { key: "pollAnonymous" }, { key: "pollPublic" }])(
    "treats $key=true as poll creation intent",
    ({ key }) => {
      (expect* 
        hasPollCreationParams({
          [key]: true,
        }),
      ).is(true);
    },
  );

  (deftest "treats finite numeric poll params as poll creation intent", () => {
    (expect* hasPollCreationParams({ pollDurationHours: 0 })).is(true);
    (expect* hasPollCreationParams({ pollDurationSeconds: 60 })).is(true);
    (expect* hasPollCreationParams({ pollDurationSeconds: "60" })).is(true);
    (expect* hasPollCreationParams({ pollDurationSeconds: "1e3" })).is(true);
    (expect* hasPollCreationParams({ pollDurationHours: Number.NaN })).is(false);
    (expect* hasPollCreationParams({ pollDurationSeconds: Infinity })).is(false);
    (expect* hasPollCreationParams({ pollDurationSeconds: "60abc" })).is(false);
  });

  (deftest "treats string-encoded boolean poll params as poll creation intent when true", () => {
    (expect* hasPollCreationParams({ pollPublic: "true" })).is(true);
    (expect* hasPollCreationParams({ pollAnonymous: "false" })).is(false);
  });

  (deftest "treats string poll options as poll creation intent", () => {
    (expect* hasPollCreationParams({ pollOption: "Yes" })).is(true);
  });

  (deftest "detects snake_case poll fields as poll creation intent", () => {
    (expect* hasPollCreationParams({ poll_question: "Lunch?" })).is(true);
    (expect* hasPollCreationParams({ poll_option: ["Pizza", "Sushi"] })).is(true);
    (expect* hasPollCreationParams({ poll_duration_seconds: "60" })).is(true);
    (expect* hasPollCreationParams({ poll_public: "true" })).is(true);
  });

  (deftest "resolves telegram poll visibility flags", () => {
    (expect* resolveTelegramPollVisibility({ pollAnonymous: true })).is(true);
    (expect* resolveTelegramPollVisibility({ pollPublic: true })).is(false);
    (expect* resolveTelegramPollVisibility({})).toBeUndefined();
    (expect* () => resolveTelegramPollVisibility({ pollAnonymous: true, pollPublic: true })).signals-error(
      /mutually exclusive/i,
    );
  });
});
