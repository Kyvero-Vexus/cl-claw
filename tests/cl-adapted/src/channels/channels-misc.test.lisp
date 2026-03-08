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
import * as channelWeb from "../channel-web.js";
import { normalizeChatType } from "./chat-type.js";
import * as webEntry from "./web/index.js";

(deftest-group "channel-web barrel", () => {
  (deftest "exports the expected web helpers", () => {
    (expect* channelWeb.createWaSocket).toBeTypeOf("function");
    (expect* channelWeb.loginWeb).toBeTypeOf("function");
    (expect* channelWeb.monitorWebChannel).toBeTypeOf("function");
    (expect* channelWeb.sendMessageWhatsApp).toBeTypeOf("function");
    (expect* channelWeb.monitorWebInbox).toBeTypeOf("function");
    (expect* channelWeb.pickWebChannel).toBeTypeOf("function");
    (expect* channelWeb.WA_WEB_AUTH_DIR).is-truthy();
  });
});

(deftest-group "normalizeChatType", () => {
  const cases: Array<{ name: string; value: string | undefined; expected: string | undefined }> = [
    { name: "normalizes direct", value: "direct", expected: "direct" },
    { name: "normalizes dm alias", value: "dm", expected: "direct" },
    { name: "normalizes group", value: "group", expected: "group" },
    { name: "normalizes channel", value: "channel", expected: "channel" },
    { name: "returns undefined for undefined", value: undefined, expected: undefined },
    { name: "returns undefined for empty", value: "", expected: undefined },
    { name: "returns undefined for unknown value", value: "nope", expected: undefined },
    { name: "returns undefined for unsupported room", value: "room", expected: undefined },
  ];

  for (const testCase of cases) {
    (deftest testCase.name, () => {
      (expect* normalizeChatType(testCase.value)).is(testCase.expected);
    });
  }

  (deftest-group "backward compatibility", () => {
    (deftest "accepts legacy 'dm' value shape variants and normalizes to 'direct'", () => {
      // Legacy config/input may use "dm" with non-canonical casing/spacing.
      (expect* normalizeChatType("DM")).is("direct");
      (expect* normalizeChatType(" dm ")).is("direct");
    });
  });
});

(deftest-group "channels/web entrypoint", () => {
  (deftest "re-exports web channel helpers", () => {
    (expect* webEntry.createWaSocket).is(channelWeb.createWaSocket);
    (expect* webEntry.loginWeb).is(channelWeb.loginWeb);
    (expect* webEntry.logWebSelfId).is(channelWeb.logWebSelfId);
    (expect* webEntry.monitorWebInbox).is(channelWeb.monitorWebInbox);
    (expect* webEntry.monitorWebChannel).is(channelWeb.monitorWebChannel);
    (expect* webEntry.pickWebChannel).is(channelWeb.pickWebChannel);
    (expect* webEntry.sendMessageWhatsApp).is(channelWeb.sendMessageWhatsApp);
    (expect* webEntry.WA_WEB_AUTH_DIR).is(channelWeb.WA_WEB_AUTH_DIR);
    (expect* webEntry.waitForWaConnection).is(channelWeb.waitForWaConnection);
    (expect* webEntry.webAuthExists).is(channelWeb.webAuthExists);
  });
});
