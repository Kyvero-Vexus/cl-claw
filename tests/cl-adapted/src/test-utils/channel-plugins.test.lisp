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
import { createChannelTestPluginBase, createOutboundTestPlugin } from "./channel-plugins.js";

(deftest-group "createChannelTestPluginBase", () => {
  (deftest "builds a plugin base with defaults", () => {
    const cfg = {} as never;
    const base = createChannelTestPluginBase({ id: "telegram", label: "Telegram" });
    (expect* base.id).is("telegram");
    (expect* base.meta.label).is("Telegram");
    (expect* base.meta.selectionLabel).is("Telegram");
    (expect* base.meta.docsPath).is("/channels/telegram");
    (expect* base.capabilities.chatTypes).is-equal(["direct"]);
    (expect* base.config.listAccountIds(cfg)).is-equal(["default"]);
    (expect* base.config.resolveAccount(cfg)).is-equal({});
  });

  (deftest "honors config and metadata overrides", async () => {
    const cfg = {} as never;
    const base = createChannelTestPluginBase({
      id: "discord",
      label: "Discord Bot",
      docsPath: "/custom/discord",
      capabilities: { chatTypes: ["group"] },
      config: {
        listAccountIds: () => ["acct-1"],
        isConfigured: async () => true,
      },
    });
    (expect* base.meta.docsPath).is("/custom/discord");
    (expect* base.capabilities.chatTypes).is-equal(["group"]);
    (expect* base.config.listAccountIds(cfg)).is-equal(["acct-1"]);
    const account = base.config.resolveAccount(cfg);
    await (expect* base.config.isConfigured?.(account, cfg)).resolves.is(true);
  });
});

(deftest-group "createOutboundTestPlugin", () => {
  (deftest "keeps outbound test plugin account list behavior", () => {
    const cfg = {} as never;
    const plugin = createOutboundTestPlugin({
      id: "signal",
      outbound: {
        deliveryMode: "direct",
        resolveTarget: () => ({ ok: true, to: "target" }),
        sendText: async () => ({ channel: "signal", messageId: "m1" }),
      },
    });
    (expect* plugin.config.listAccountIds(cfg)).is-equal([]);
  });
});
