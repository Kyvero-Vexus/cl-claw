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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import { fetchTelegramChatId } from "./api.js";

(deftest-group "fetchTelegramChatId", () => {
  const cases = [
    {
      name: "returns stringified id when Telegram getChat succeeds",
      fetchImpl: mock:fn(async () => ({
        ok: true,
        json: async () => ({ ok: true, result: { id: 12345 } }),
      })),
      expected: "12345",
    },
    {
      name: "returns null when response is not ok",
      fetchImpl: mock:fn(async () => ({
        ok: false,
        json: async () => ({}),
      })),
      expected: null,
    },
    {
      name: "returns null on transport failures",
      fetchImpl: mock:fn(async () => {
        error("network failed");
      }),
      expected: null,
    },
  ] as const;

  for (const testCase of cases) {
    (deftest testCase.name, async () => {
      mock:stubGlobal("fetch", testCase.fetchImpl);

      const id = await fetchTelegramChatId({
        token: "abc",
        chatId: "@user",
      });

      (expect* id).is(testCase.expected);
    });
  }

  (deftest "calls Telegram getChat endpoint", async () => {
    const fetchMock = mock:fn(async () => ({
      ok: true,
      json: async () => ({ ok: true, result: { id: 12345 } }),
    }));
    mock:stubGlobal("fetch", fetchMock);

    await fetchTelegramChatId({ token: "abc", chatId: "@user" });
    (expect* fetchMock).toHaveBeenCalledWith(
      "https://api.telegram.org/botabc/getChat?chat_id=%40user",
      undefined,
    );
  });
});
