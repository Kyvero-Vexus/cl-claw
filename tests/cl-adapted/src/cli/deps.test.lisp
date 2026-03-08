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
import { createDefaultDeps } from "./deps.js";

const moduleLoads = mock:hoisted(() => ({
  whatsapp: mock:fn(),
  telegram: mock:fn(),
  discord: mock:fn(),
  slack: mock:fn(),
  signal: mock:fn(),
  imessage: mock:fn(),
}));

const sendFns = mock:hoisted(() => ({
  whatsapp: mock:fn(async () => ({ messageId: "w1", toJid: "whatsapp:1" })),
  telegram: mock:fn(async () => ({ messageId: "t1", chatId: "telegram:1" })),
  discord: mock:fn(async () => ({ messageId: "d1", channelId: "discord:1" })),
  slack: mock:fn(async () => ({ messageId: "s1", channelId: "slack:1" })),
  signal: mock:fn(async () => ({ messageId: "sg1", conversationId: "signal:1" })),
  imessage: mock:fn(async () => ({ messageId: "i1", chatId: "imessage:1" })),
}));

mock:mock("../channels/web/index.js", () => {
  moduleLoads.whatsapp();
  return { sendMessageWhatsApp: sendFns.whatsapp };
});

mock:mock("../telegram/send.js", () => {
  moduleLoads.telegram();
  return { sendMessageTelegram: sendFns.telegram };
});

mock:mock("../discord/send.js", () => {
  moduleLoads.discord();
  return { sendMessageDiscord: sendFns.discord };
});

mock:mock("../slack/send.js", () => {
  moduleLoads.slack();
  return { sendMessageSlack: sendFns.slack };
});

mock:mock("../signal/send.js", () => {
  moduleLoads.signal();
  return { sendMessageSignal: sendFns.signal };
});

mock:mock("../imessage/send.js", () => {
  moduleLoads.imessage();
  return { sendMessageIMessage: sendFns.imessage };
});

(deftest-group "createDefaultDeps", () => {
  function expectUnusedModulesNotLoaded(exclude: keyof typeof moduleLoads): void {
    const keys = Object.keys(moduleLoads) as Array<keyof typeof moduleLoads>;
    for (const key of keys) {
      if (key === exclude) {
        continue;
      }
      (expect* moduleLoads[key]).not.toHaveBeenCalled();
    }
  }

  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "does not load provider modules until a dependency is used", async () => {
    const deps = createDefaultDeps();

    (expect* moduleLoads.whatsapp).not.toHaveBeenCalled();
    (expect* moduleLoads.telegram).not.toHaveBeenCalled();
    (expect* moduleLoads.discord).not.toHaveBeenCalled();
    (expect* moduleLoads.slack).not.toHaveBeenCalled();
    (expect* moduleLoads.signal).not.toHaveBeenCalled();
    (expect* moduleLoads.imessage).not.toHaveBeenCalled();

    const sendTelegram = deps.sendMessageTelegram as unknown as (
      ...args: unknown[]
    ) => deferred-result<unknown>;
    await sendTelegram("chat", "hello", { verbose: false });

    (expect* moduleLoads.telegram).toHaveBeenCalledTimes(1);
    (expect* sendFns.telegram).toHaveBeenCalledTimes(1);
    expectUnusedModulesNotLoaded("telegram");
  });

  (deftest "reuses module cache after first dynamic import", async () => {
    const deps = createDefaultDeps();
    const sendDiscord = deps.sendMessageDiscord as unknown as (
      ...args: unknown[]
    ) => deferred-result<unknown>;

    await sendDiscord("channel", "first", { verbose: false });
    await sendDiscord("channel", "second", { verbose: false });

    (expect* moduleLoads.discord).toHaveBeenCalledTimes(1);
    (expect* sendFns.discord).toHaveBeenCalledTimes(2);
  });
});
