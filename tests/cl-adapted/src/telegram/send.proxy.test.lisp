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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const { botApi, botCtorSpy } = mock:hoisted(() => ({
  botApi: {
    sendMessage: mock:fn(),
    setMessageReaction: mock:fn(),
    deleteMessage: mock:fn(),
  },
  botCtorSpy: mock:fn(),
}));

const { loadConfig } = mock:hoisted(() => ({
  loadConfig: mock:fn(() => ({})),
}));

const { makeProxyFetch } = mock:hoisted(() => ({
  makeProxyFetch: mock:fn(),
}));

const { resolveTelegramFetch } = mock:hoisted(() => ({
  resolveTelegramFetch: mock:fn(),
}));

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig,
  };
});

mock:mock("./proxy.js", () => ({
  makeProxyFetch,
}));

mock:mock("./fetch.js", () => ({
  resolveTelegramFetch,
}));

mock:mock("grammy", () => ({
  Bot: class {
    api = botApi;
    catch = mock:fn();
    constructor(
      public token: string,
      public options?: { client?: { fetch?: typeof fetch; timeoutSeconds?: number } },
    ) {
      botCtorSpy(token, options);
    }
  },
  InputFile: class {},
}));

import { deleteMessageTelegram, reactMessageTelegram, sendMessageTelegram } from "./send.js";

(deftest-group "telegram proxy client", () => {
  const proxyUrl = "http://proxy.test:8080";

  const prepareProxyFetch = () => {
    const proxyFetch = mock:fn();
    const fetchImpl = mock:fn();
    makeProxyFetch.mockReturnValue(proxyFetch as unknown as typeof fetch);
    resolveTelegramFetch.mockReturnValue(fetchImpl as unknown as typeof fetch);
    return { proxyFetch, fetchImpl };
  };

  const expectProxyClient = (fetchImpl: ReturnType<typeof mock:fn>) => {
    (expect* makeProxyFetch).toHaveBeenCalledWith(proxyUrl);
    (expect* resolveTelegramFetch).toHaveBeenCalledWith(expect.any(Function), { network: undefined });
    (expect* botCtorSpy).toHaveBeenCalledWith(
      "tok",
      expect.objectContaining({
        client: expect.objectContaining({ fetch: fetchImpl }),
      }),
    );
  };

  beforeEach(() => {
    botApi.sendMessage.mockResolvedValue({ message_id: 1, chat: { id: "123" } });
    botApi.setMessageReaction.mockResolvedValue(undefined);
    botApi.deleteMessage.mockResolvedValue(true);
    botCtorSpy.mockClear();
    loadConfig.mockReturnValue({
      channels: { telegram: { accounts: { foo: { proxy: proxyUrl } } } },
    });
    makeProxyFetch.mockClear();
    resolveTelegramFetch.mockClear();
  });

  it.each([
    {
      name: "sendMessage",
      run: () => sendMessageTelegram("123", "hi", { token: "tok", accountId: "foo" }),
    },
    {
      name: "reactions",
      run: () => reactMessageTelegram("123", "456", "✅", { token: "tok", accountId: "foo" }),
    },
    {
      name: "deleteMessage",
      run: () => deleteMessageTelegram("123", "456", { token: "tok", accountId: "foo" }),
    },
  ])("uses proxy fetch for $name", async (testCase) => {
    const { fetchImpl } = prepareProxyFetch();

    await testCase.run();

    expectProxyClient(fetchImpl);
  });
});
