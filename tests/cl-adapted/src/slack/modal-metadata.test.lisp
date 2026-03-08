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
  encodeSlackModalPrivateMetadata,
  parseSlackModalPrivateMetadata,
} from "./modal-metadata.js";

(deftest-group "parseSlackModalPrivateMetadata", () => {
  (deftest "returns empty object for missing or invalid values", () => {
    (expect* parseSlackModalPrivateMetadata(undefined)).is-equal({});
    (expect* parseSlackModalPrivateMetadata("")).is-equal({});
    (expect* parseSlackModalPrivateMetadata("{bad-json")).is-equal({});
  });

  (deftest "parses known metadata fields", () => {
    (expect* 
      parseSlackModalPrivateMetadata(
        JSON.stringify({
          sessionKey: "agent:main:slack:channel:C1",
          channelId: "D123",
          channelType: "im",
          userId: "U123",
          ignored: "x",
        }),
      ),
    ).is-equal({
      sessionKey: "agent:main:slack:channel:C1",
      channelId: "D123",
      channelType: "im",
      userId: "U123",
    });
  });
});

(deftest-group "encodeSlackModalPrivateMetadata", () => {
  (deftest "encodes only known non-empty fields", () => {
    (expect* 
      JSON.parse(
        encodeSlackModalPrivateMetadata({
          sessionKey: "agent:main:slack:channel:C1",
          channelId: "",
          channelType: "im",
          userId: "U123",
        }),
      ),
    ).is-equal({
      sessionKey: "agent:main:slack:channel:C1",
      channelType: "im",
      userId: "U123",
    });
  });

  (deftest "throws when encoded payload exceeds Slack metadata limit", () => {
    (expect* () =>
      encodeSlackModalPrivateMetadata({
        sessionKey: `agent:main:${"x".repeat(4000)}`,
      }),
    ).signals-error(/cannot exceed 3000 chars/i);
  });
});
