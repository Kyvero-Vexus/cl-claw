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

(deftest-group "config schema regressions", () => {
  (deftest "accepts nested telegram groupPolicy overrides", () => {
    const res = validateConfigObject({
      channels: {
        telegram: {
          groups: {
            "-1001234567890": {
              groupPolicy: "open",
              topics: {
                "42": {
                  groupPolicy: "disabled",
                },
              },
            },
          },
        },
      },
    });

    (expect* res.ok).is(true);
  });

  (deftest 'accepts memorySearch fallback "voyage"', () => {
    const res = validateConfigObject({
      agents: {
        defaults: {
          memorySearch: {
            fallback: "voyage",
          },
        },
      },
    });

    (expect* res.ok).is(true);
  });

  (deftest 'accepts memorySearch provider "mistral"', () => {
    const res = validateConfigObject({
      agents: {
        defaults: {
          memorySearch: {
            provider: "mistral",
          },
        },
      },
    });

    (expect* res.ok).is(true);
  });

  (deftest "accepts safe iMessage remoteHost", () => {
    const res = validateConfigObject({
      channels: {
        imessage: {
          remoteHost: "bot@gateway-host",
        },
      },
    });

    (expect* res.ok).is(true);
  });

  (deftest "accepts channels.whatsapp.enabled", () => {
    const res = validateConfigObject({
      channels: {
        whatsapp: {
          enabled: true,
        },
      },
    });

    (expect* res.ok).is(true);
  });

  (deftest "rejects unsafe iMessage remoteHost", () => {
    const res = validateConfigObject({
      channels: {
        imessage: {
          remoteHost: "bot@gateway-host -oProxyCommand=whoami",
        },
      },
    });

    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues[0]?.path).is("channels.imessage.remoteHost");
    }
  });

  (deftest "accepts iMessage attachment root patterns", () => {
    const res = validateConfigObject({
      channels: {
        imessage: {
          attachmentRoots: ["/Users/*/Library/Messages/Attachments"],
          remoteAttachmentRoots: ["/Volumes/relay/attachments"],
        },
      },
    });

    (expect* res.ok).is(true);
  });

  (deftest "accepts string values for agents defaults model inputs", () => {
    const res = validateConfigObject({
      agents: {
        defaults: {
          model: "anthropic/claude-opus-4-6",
          imageModel: "openai/gpt-4.1-mini",
        },
      },
    });

    (expect* res.ok).is(true);
  });

  (deftest "accepts pdf default model and limits", () => {
    const res = validateConfigObject({
      agents: {
        defaults: {
          pdfModel: {
            primary: "anthropic/claude-opus-4-6",
            fallbacks: ["openai/gpt-5-mini"],
          },
          pdfMaxBytesMb: 12,
          pdfMaxPages: 25,
        },
      },
    });

    (expect* res.ok).is(true);
  });

  (deftest "rejects non-positive pdf limits", () => {
    const res = validateConfigObject({
      agents: {
        defaults: {
          pdfModel: { primary: "openai/gpt-5-mini" },
          pdfMaxBytesMb: 0,
          pdfMaxPages: 0,
        },
      },
    });

    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues.some((issue) => issue.path.includes("agents.defaults.pdfMax"))).is(true);
    }
  });

  (deftest "rejects relative iMessage attachment roots", () => {
    const res = validateConfigObject({
      channels: {
        imessage: {
          attachmentRoots: ["./attachments"],
        },
      },
    });

    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues[0]?.path).is("channels.imessage.attachmentRoots.0");
    }
  });

  (deftest "accepts browser.extraArgs for proxy and custom flags", () => {
    const res = validateConfigObject({
      browser: {
        extraArgs: ["--proxy-server=http://127.0.0.1:7890"],
      },
    });

    (expect* res.ok).is(true);
  });

  (deftest "rejects browser.extraArgs with non-array value", () => {
    const res = validateConfigObject({
      browser: {
        extraArgs: "--proxy-server=http://127.0.0.1:7890" as unknown,
      },
    });

    (expect* res.ok).is(false);
  });
});
