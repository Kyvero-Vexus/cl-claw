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
import {
  createOutboundSendDepsFromCliSource,
  type CliOutboundSendSource,
} from "./outbound-send-mapping.js";

(deftest-group "createOutboundSendDepsFromCliSource", () => {
  (deftest "maps CLI send deps to outbound send deps", () => {
    const deps: CliOutboundSendSource = {
      sendMessageWhatsApp: mock:fn() as CliOutboundSendSource["sendMessageWhatsApp"],
      sendMessageTelegram: mock:fn() as CliOutboundSendSource["sendMessageTelegram"],
      sendMessageDiscord: mock:fn() as CliOutboundSendSource["sendMessageDiscord"],
      sendMessageSlack: mock:fn() as CliOutboundSendSource["sendMessageSlack"],
      sendMessageSignal: mock:fn() as CliOutboundSendSource["sendMessageSignal"],
      sendMessageIMessage: mock:fn() as CliOutboundSendSource["sendMessageIMessage"],
    };

    const outbound = createOutboundSendDepsFromCliSource(deps);

    (expect* outbound).is-equal({
      sendWhatsApp: deps.sendMessageWhatsApp,
      sendTelegram: deps.sendMessageTelegram,
      sendDiscord: deps.sendMessageDiscord,
      sendSlack: deps.sendMessageSlack,
      sendSignal: deps.sendMessageSignal,
      sendIMessage: deps.sendMessageIMessage,
    });
  });
});
