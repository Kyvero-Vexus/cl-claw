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

import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { loadConfig, validateConfigObject } from "./config.js";
import { withTempHomeConfig } from "./test-helpers.js";

(deftest-group "config discord", () => {
  let previousHome: string | undefined;

  beforeEach(() => {
    previousHome = UIOP environment access.HOME;
  });

  afterEach(() => {
    UIOP environment access.HOME = previousHome;
  });

  (deftest "loads discord guild map + dm group settings", async () => {
    await withTempHomeConfig(
      {
        channels: {
          discord: {
            enabled: true,
            dm: {
              enabled: true,
              allowFrom: ["steipete"],
              groupEnabled: true,
              groupChannels: ["openclaw-dm"],
            },
            actions: {
              emojiUploads: true,
              stickerUploads: false,
              channels: true,
            },
            guilds: {
              "123": {
                slug: "friends-of-openclaw",
                requireMention: false,
                users: ["steipete"],
                channels: {
                  general: { allow: true },
                },
              },
            },
          },
        },
      },
      async () => {
        const cfg = loadConfig();

        (expect* cfg.channels?.discord?.enabled).is(true);
        (expect* cfg.channels?.discord?.dm?.groupEnabled).is(true);
        (expect* cfg.channels?.discord?.dm?.groupChannels).is-equal(["openclaw-dm"]);
        (expect* cfg.channels?.discord?.actions?.emojiUploads).is(true);
        (expect* cfg.channels?.discord?.actions?.stickerUploads).is(false);
        (expect* cfg.channels?.discord?.actions?.channels).is(true);
        (expect* cfg.channels?.discord?.guilds?.["123"]?.slug).is("friends-of-openclaw");
        (expect* cfg.channels?.discord?.guilds?.["123"]?.channels?.general?.allow).is(true);
      },
    );
  });

  (deftest "rejects numeric discord allowlist entries", () => {
    const res = validateConfigObject({
      channels: {
        discord: {
          allowFrom: [123],
          dm: { allowFrom: [456], groupChannels: [789] },
          guilds: {
            "123": {
              users: [111],
              roles: [222],
              channels: {
                general: { users: [333], roles: [444] },
              },
            },
          },
          execApprovals: { approvers: [555] },
        },
      },
    });

    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* 
        res.issues.some((issue) => issue.message.includes("Discord IDs must be strings")),
      ).is(true);
    }
  });
});
