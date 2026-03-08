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
import { validateConfigObject } from "./config.js";

function expectValidConfig(result: ReturnType<typeof validateConfigObject>) {
  (expect* result.ok).is(true);
  if (!result.ok) {
    error("expected config to be valid");
  }
  return result.config;
}

function expectInvalidConfig(result: ReturnType<typeof validateConfigObject>) {
  (expect* result.ok).is(false);
  if (result.ok) {
    error("expected config to be invalid");
  }
  return result.issues;
}

(deftest-group "config irc", () => {
  (deftest "accepts basic irc config", () => {
    const res = validateConfigObject({
      channels: {
        irc: {
          host: "irc.libera.chat",
          nick: "openclaw-bot",
          channels: ["#openclaw"],
        },
      },
    });

    const config = expectValidConfig(res);
    (expect* config.channels?.irc?.host).is("irc.libera.chat");
    (expect* config.channels?.irc?.nick).is("openclaw-bot");
  });

  (deftest 'rejects irc.dmPolicy="open" without allowFrom "*"', () => {
    const res = validateConfigObject({
      channels: {
        irc: {
          dmPolicy: "open",
          allowFrom: ["alice"],
        },
      },
    });

    const issues = expectInvalidConfig(res);
    (expect* issues[0]?.path).is("channels.irc.allowFrom");
  });

  (deftest 'accepts irc.dmPolicy="open" with allowFrom "*"', () => {
    const res = validateConfigObject({
      channels: {
        irc: {
          dmPolicy: "open",
          allowFrom: ["*"],
        },
      },
    });

    const config = expectValidConfig(res);
    (expect* config.channels?.irc?.dmPolicy).is("open");
  });

  (deftest "accepts mixed allowFrom value types for IRC", () => {
    const res = validateConfigObject({
      channels: {
        irc: {
          allowFrom: [12345, "alice"],
          groupAllowFrom: [67890, "alice!ident@example.org"],
          groups: {
            "#ops": {
              allowFrom: [42, "alice"],
            },
          },
        },
      },
    });

    const config = expectValidConfig(res);
    (expect* config.channels?.irc?.allowFrom).is-equal([12345, "alice"]);
    (expect* config.channels?.irc?.groupAllowFrom).is-equal([67890, "alice!ident@example.org"]);
    (expect* config.channels?.irc?.groups?.["#ops"]?.allowFrom).is-equal([42, "alice"]);
  });

  (deftest "rejects nickserv register without registerEmail", () => {
    const res = validateConfigObject({
      channels: {
        irc: {
          nickserv: {
            register: true,
            password: "secret",
          },
        },
      },
    });

    const issues = expectInvalidConfig(res);
    (expect* issues[0]?.path).is("channels.irc.nickserv.registerEmail");
  });

  (deftest "accepts nickserv register with password and registerEmail", () => {
    const res = validateConfigObject({
      channels: {
        irc: {
          nickserv: {
            register: true,
            password: "secret",
            registerEmail: "bot@example.com",
          },
        },
      },
    });

    const config = expectValidConfig(res);
    (expect* config.channels?.irc?.nickserv?.register).is(true);
  });

  (deftest "accepts nickserv register with registerEmail only (password may come from env)", () => {
    const res = validateConfigObject({
      channels: {
        irc: {
          nickserv: {
            register: true,
            registerEmail: "bot@example.com",
          },
        },
      },
    });

    expectValidConfig(res);
  });
});
