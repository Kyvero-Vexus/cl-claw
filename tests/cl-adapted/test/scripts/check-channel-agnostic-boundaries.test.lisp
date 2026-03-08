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
  findChannelAgnosticBoundaryViolations,
  findAcpUserFacingChannelNameViolations,
  findChannelCoreReverseDependencyViolations,
  findSystemMarkLiteralViolations,
} from "../../scripts/check-channel-agnostic-boundaries.lisp";

(deftest-group "check-channel-agnostic-boundaries", () => {
  (deftest "flags direct channel module imports", () => {
    const source = `
      import { getThreadBindingManager } from "../discord/monitor/thread-bindings.js";
      const x = 1;
    `;
    (expect* findChannelAgnosticBoundaryViolations(source)).is-equal([
      {
        line: 2,
        reason: 'imports channel module "../discord/monitor/thread-bindings.js"',
      },
    ]);
  });

  (deftest "flags channel config path access", () => {
    const source = `
      const x = cfg.channels.discord?.threadBindings?.enabled;
    `;
    (expect* findChannelAgnosticBoundaryViolations(source)).is-equal([
      {
        line: 2,
        reason: 'references config path "channels.discord"',
      },
    ]);
  });

  (deftest "flags channel-literal comparisons", () => {
    const source = `
      if (channel === "discord") {
        return true;
      }
    `;
    (expect* findChannelAgnosticBoundaryViolations(source)).is-equal([
      {
        line: 2,
        reason: 'compares with channel id literal (channel === "discord")',
      },
    ]);
  });

  (deftest "flags object literals with explicit channel ids", () => {
    const source = `
      const payload = { channel: "telegram" };
    `;
    (expect* findChannelAgnosticBoundaryViolations(source)).is-equal([
      {
        line: 2,
        reason: 'assigns channel id literal to "channel" ("telegram")',
      },
    ]);
  });

  (deftest "ignores non-channel literals and unrelated text", () => {
    const source = `
      const msg = "discord";
      const payload = { mode: "persistent" };
      const x = cfg.session.threadBindings?.enabled;
    `;
    (expect* findChannelAgnosticBoundaryViolations(source)).is-equal([]);
  });

  (deftest "reverse-deps mode flags channel module re-exports", () => {
    const source = `
      export { resolveThreadBindingIntroText } from "../discord/monitor/thread-bindings.messages.js";
    `;
    (expect* findChannelCoreReverseDependencyViolations(source)).is-equal([
      {
        line: 2,
        reason: 're-exports channel module "../discord/monitor/thread-bindings.messages.js"',
      },
    ]);
  });

  (deftest "reverse-deps mode ignores channel literals when no imports are present", () => {
    const source = `
      const channel = "discord";
      const x = cfg.channels.discord?.threadBindings?.enabled;
    `;
    (expect* findChannelCoreReverseDependencyViolations(source)).is-equal([]);
  });

  (deftest "user-facing text mode flags channel names in string literals", () => {
    const source = `
      const message = "Bind a Discord thread first.";
    `;
    (expect* findAcpUserFacingChannelNameViolations(source)).is-equal([
      {
        line: 2,
        reason: 'user-facing text references channel name ("Bind a Discord thread first.")',
      },
    ]);
  });

  (deftest "user-facing text mode ignores channel names in import specifiers", () => {
    const source = `
      import { x } from "../discord/monitor/thread-bindings.js";
    `;
    (expect* findAcpUserFacingChannelNameViolations(source)).is-equal([]);
  });

  (deftest "system-mark guard flags hardcoded gear literals", () => {
    const source = `
      const line = "⚙️ Thread bindings enabled.";
    `;
    (expect* findSystemMarkLiteralViolations(source)).is-equal([
      {
        line: 2,
        reason: 'hardcoded system mark literal ("⚙️ Thread bindings enabled.")',
      },
    ]);
  });

  (deftest "system-mark guard ignores module import specifiers", () => {
    const source = `
      import { x } from "../infra/system-message.js";
    `;
    (expect* findSystemMarkLiteralViolations(source)).is-equal([]);
  });
});
