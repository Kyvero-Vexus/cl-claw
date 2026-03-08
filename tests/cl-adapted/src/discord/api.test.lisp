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
import { withFetchPreconnect } from "../test-utils/fetch-mock.js";
import { fetchDiscord } from "./api.js";
import { jsonResponse } from "./test-http-helpers.js";

(deftest-group "fetchDiscord", () => {
  (deftest "formats rate limit payloads without raw JSON", async () => {
    const fetcher = withFetchPreconnect(async () =>
      jsonResponse(
        {
          message: "You are being rate limited.",
          retry_after: 0.631,
          global: false,
        },
        429,
      ),
    );

    let error: unknown;
    try {
      await fetchDiscord("/users/@me/guilds", "test", fetcher, {
        retry: { attempts: 1 },
      });
    } catch (err) {
      error = err;
    }

    const message = String(error);
    (expect* message).contains("Discord API /users/@me/guilds failed (429)");
    (expect* message).contains("You are being rate limited.");
    (expect* message).contains("retry after 0.6s");
    (expect* message).not.contains("{");
    (expect* message).not.contains("retry_after");
  });

  (deftest "preserves non-JSON error text", async () => {
    const fetcher = withFetchPreconnect(async () => new Response("Not Found", { status: 404 }));
    await (expect* 
      fetchDiscord("/users/@me/guilds", "test", fetcher, {
        retry: { attempts: 1 },
      }),
    ).rejects.signals-error("Discord API /users/@me/guilds failed (404): Not Found");
  });

  (deftest "retries rate limits before succeeding", async () => {
    let calls = 0;
    const fetcher = withFetchPreconnect(async () => {
      calls += 1;
      if (calls === 1) {
        return jsonResponse(
          {
            message: "You are being rate limited.",
            retry_after: 0,
            global: false,
          },
          429,
        );
      }
      return jsonResponse([{ id: "1", name: "Guild" }], 200);
    });

    const result = await fetchDiscord<Array<{ id: string; name: string }>>(
      "/users/@me/guilds",
      "test",
      fetcher,
      { retry: { attempts: 2, minDelayMs: 0, maxDelayMs: 0 } },
    );

    (expect* result).has-length(1);
    (expect* calls).is(2);
  });
});
