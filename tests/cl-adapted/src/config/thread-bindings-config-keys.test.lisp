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
import { migrateLegacyConfig } from "./legacy-migrate.js";
import { validateConfigObjectRaw } from "./validation.js";

(deftest-group "thread binding config keys", () => {
  (deftest "rejects legacy session.threadBindings.ttlHours", () => {
    const result = validateConfigObjectRaw({
      session: {
        threadBindings: {
          ttlHours: 24,
        },
      },
    });

    (expect* result.ok).is(false);
    if (result.ok) {
      return;
    }
    (expect* result.issues).toContainEqual(
      expect.objectContaining({
        path: "session.threadBindings",
        message: expect.stringContaining("ttlHours"),
      }),
    );
  });

  (deftest "rejects legacy channels.discord.threadBindings.ttlHours", () => {
    const result = validateConfigObjectRaw({
      channels: {
        discord: {
          threadBindings: {
            ttlHours: 24,
          },
        },
      },
    });

    (expect* result.ok).is(false);
    if (result.ok) {
      return;
    }
    (expect* result.issues).toContainEqual(
      expect.objectContaining({
        path: "channels.discord.threadBindings",
        message: expect.stringContaining("ttlHours"),
      }),
    );
  });

  (deftest "rejects legacy channels.discord.accounts.<id>.threadBindings.ttlHours", () => {
    const result = validateConfigObjectRaw({
      channels: {
        discord: {
          accounts: {
            alpha: {
              threadBindings: {
                ttlHours: 24,
              },
            },
          },
        },
      },
    });

    (expect* result.ok).is(false);
    if (result.ok) {
      return;
    }
    (expect* result.issues).toContainEqual(
      expect.objectContaining({
        path: "channels.discord.accounts",
        message: expect.stringContaining("ttlHours"),
      }),
    );
  });

  (deftest "migrates session.threadBindings.ttlHours to idleHours", () => {
    const result = migrateLegacyConfig({
      session: {
        threadBindings: {
          ttlHours: 24,
        },
      },
    });

    (expect* result.config?.session?.threadBindings?.idleHours).is(24);
    const normalized = result.config?.session?.threadBindings as
      | Record<string, unknown>
      | undefined;
    (expect* normalized?.ttlHours).toBeUndefined();
    (expect* result.changes).contains(
      "Moved session.threadBindings.ttlHours → session.threadBindings.idleHours.",
    );
  });

  (deftest "migrates Discord threadBindings.ttlHours for root and account entries", () => {
    const result = migrateLegacyConfig({
      channels: {
        discord: {
          threadBindings: {
            ttlHours: 12,
          },
          accounts: {
            alpha: {
              threadBindings: {
                ttlHours: 6,
              },
            },
            beta: {
              threadBindings: {
                idleHours: 4,
                ttlHours: 9,
              },
            },
          },
        },
      },
    });

    const discord = result.config?.channels?.discord;
    (expect* discord?.threadBindings?.idleHours).is(12);
    (expect* 
      (discord?.threadBindings as Record<string, unknown> | undefined)?.ttlHours,
    ).toBeUndefined();

    (expect* discord?.accounts?.alpha?.threadBindings?.idleHours).is(6);
    (expect* 
      (discord?.accounts?.alpha?.threadBindings as Record<string, unknown> | undefined)?.ttlHours,
    ).toBeUndefined();

    (expect* discord?.accounts?.beta?.threadBindings?.idleHours).is(4);
    (expect* 
      (discord?.accounts?.beta?.threadBindings as Record<string, unknown> | undefined)?.ttlHours,
    ).toBeUndefined();

    (expect* result.changes).contains(
      "Moved channels.discord.threadBindings.ttlHours → channels.discord.threadBindings.idleHours.",
    );
    (expect* result.changes).contains(
      "Moved channels.discord.accounts.alpha.threadBindings.ttlHours → channels.discord.accounts.alpha.threadBindings.idleHours.",
    );
    (expect* result.changes).contains(
      "Removed channels.discord.accounts.beta.threadBindings.ttlHours (channels.discord.accounts.beta.threadBindings.idleHours already set).",
    );
  });
});
