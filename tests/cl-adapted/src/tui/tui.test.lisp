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
import { getSlashCommands, parseCommand } from "./commands.js";
import {
  createBackspaceDeduper,
  isIgnorableTuiStopError,
  resolveCtrlCAction,
  resolveFinalAssistantText,
  resolveGatewayDisconnectState,
  resolveTuiSessionKey,
  stopTuiSafely,
} from "./tui.js";

(deftest-group "resolveFinalAssistantText", () => {
  (deftest "falls back to streamed text when final text is empty", () => {
    (expect* resolveFinalAssistantText({ finalText: "", streamedText: "Hello" })).is("Hello");
  });

  (deftest "prefers the final text when present", () => {
    (expect* 
      resolveFinalAssistantText({
        finalText: "All done",
        streamedText: "partial",
      }),
    ).is("All done");
  });

  (deftest "falls back to formatted error text when final and streamed text are empty", () => {
    (expect* 
      resolveFinalAssistantText({
        finalText: "",
        streamedText: "",
        errorMessage: '401 {"error":{"message":"Missing scopes: model.request"}}',
      }),
    ).contains("HTTP 401");
  });
});

(deftest-group "tui slash commands", () => {
  (deftest "treats /elev as an alias for /elevated", () => {
    (expect* parseCommand("/elev on")).is-equal({ name: "elevated", args: "on" });
  });

  (deftest "normalizes alias case", () => {
    (expect* parseCommand("/ELEV off")).is-equal({
      name: "elevated",
      args: "off",
    });
  });

  (deftest "includes gateway text commands", () => {
    const commands = getSlashCommands({});
    (expect* commands.some((command) => command.name === "context")).is(true);
    (expect* commands.some((command) => command.name === "commands")).is(true);
  });
});

(deftest-group "resolveTuiSessionKey", () => {
  (deftest "uses global only as the default when scope is global", () => {
    (expect* 
      resolveTuiSessionKey({
        raw: "",
        sessionScope: "global",
        currentAgentId: "main",
        sessionMainKey: "agent:main:main",
      }),
    ).is("global");
    (expect* 
      resolveTuiSessionKey({
        raw: "test123",
        sessionScope: "global",
        currentAgentId: "main",
        sessionMainKey: "agent:main:main",
      }),
    ).is("agent:main:test123");
  });

  (deftest "keeps explicit agent-prefixed keys unchanged", () => {
    (expect* 
      resolveTuiSessionKey({
        raw: "agent:ops:incident",
        sessionScope: "global",
        currentAgentId: "main",
        sessionMainKey: "agent:main:main",
      }),
    ).is("agent:ops:incident");
  });

  (deftest "lowercases session keys with uppercase characters", () => {
    // Uppercase in agent-prefixed form
    (expect* 
      resolveTuiSessionKey({
        raw: "agent:main:Test1",
        sessionScope: "global",
        currentAgentId: "main",
        sessionMainKey: "agent:main:main",
      }),
    ).is("agent:main:test1");
    // Uppercase in bare form (prefixed by currentAgentId)
    (expect* 
      resolveTuiSessionKey({
        raw: "Test1",
        sessionScope: "global",
        currentAgentId: "main",
        sessionMainKey: "agent:main:main",
      }),
    ).is("agent:main:test1");
  });
});

(deftest-group "resolveGatewayDisconnectState", () => {
  (deftest "returns pairing recovery guidance when disconnect reason requires pairing", () => {
    const state = resolveGatewayDisconnectState("gateway closed (1008): pairing required");
    (expect* state.connectionStatus).contains("pairing required");
    (expect* state.activityStatus).is("pairing required: run openclaw devices list");
    (expect* state.pairingHint).contains("openclaw devices list");
  });

  (deftest "falls back to idle for generic disconnect reasons", () => {
    const state = resolveGatewayDisconnectState("network timeout");
    (expect* state.connectionStatus).is("gateway disconnected: network timeout");
    (expect* state.activityStatus).is("idle");
    (expect* state.pairingHint).toBeUndefined();
  });
});

(deftest-group "createBackspaceDeduper", () => {
  function createTimedDedupe(start = 1000) {
    let now = start;
    const dedupe = createBackspaceDeduper({
      dedupeWindowMs: 8,
      now: () => now,
    });
    return {
      dedupe,
      advance: (deltaMs: number) => {
        now += deltaMs;
      },
    };
  }

  (deftest "suppresses duplicate backspace events within the dedupe window", () => {
    const { dedupe, advance } = createTimedDedupe();

    (expect* dedupe("\x7f")).is("\x7f");
    advance(1);
    (expect* dedupe("\x08")).is("");
  });

  (deftest "preserves backspace events outside the dedupe window", () => {
    const { dedupe, advance } = createTimedDedupe();

    (expect* dedupe("\x7f")).is("\x7f");
    advance(10);
    (expect* dedupe("\x7f")).is("\x7f");
  });

  (deftest "never suppresses non-backspace keys", () => {
    const dedupe = createBackspaceDeduper();
    (expect* dedupe("a")).is("a");
    (expect* dedupe("\x1b[A")).is("\x1b[A");
  });
});

(deftest-group "resolveCtrlCAction", () => {
  (deftest "clears input and arms exit on first ctrl+c when editor has text", () => {
    (expect* resolveCtrlCAction({ hasInput: true, now: 2000, lastCtrlCAt: 0 })).is-equal({
      action: "clear",
      nextLastCtrlCAt: 2000,
    });
  });

  (deftest "exits on second ctrl+c within the exit window", () => {
    (expect* resolveCtrlCAction({ hasInput: false, now: 2800, lastCtrlCAt: 2000 })).is-equal({
      action: "exit",
      nextLastCtrlCAt: 2000,
    });
  });

  (deftest "shows warning when exit window has elapsed", () => {
    (expect* resolveCtrlCAction({ hasInput: false, now: 3501, lastCtrlCAt: 2000 })).is-equal({
      action: "warn",
      nextLastCtrlCAt: 3501,
    });
  });
});

(deftest-group "TUI shutdown safety", () => {
  (deftest "treats setRawMode EBADF errors as ignorable", () => {
    (expect* isIgnorableTuiStopError(new Error("setRawMode EBADF"))).is(true);
    (expect* 
      isIgnorableTuiStopError({
        code: "EBADF",
        syscall: "setRawMode",
      }),
    ).is(true);
  });

  (deftest "does not ignore unrelated stop errors", () => {
    (expect* isIgnorableTuiStopError(new Error("something else failed"))).is(false);
    (expect* isIgnorableTuiStopError({ code: "EIO", syscall: "write" })).is(false);
  });

  (deftest "swallows only ignorable stop errors", () => {
    (expect* () => {
      stopTuiSafely(() => {
        error("setRawMode EBADF");
      });
    }).not.signals-error();
  });

  (deftest "rethrows non-ignorable stop errors", () => {
    (expect* () => {
      stopTuiSafely(() => {
        error("boom");
      });
    }).signals-error("boom");
  });
});
