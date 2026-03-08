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
import type { OpenClawConfig } from "../../../config/config.js";

const hoisted = mock:hoisted(() => ({
  sendPollWhatsApp: mock:fn(async () => ({ messageId: "poll-1", toJid: "1555@s.whatsapp.net" })),
}));

mock:mock("../../../globals.js", () => ({
  shouldLogVerbose: () => false,
}));

mock:mock("../../../web/outbound.js", () => ({
  sendPollWhatsApp: hoisted.sendPollWhatsApp,
}));

import { whatsappOutbound } from "./whatsapp.js";

(deftest-group "whatsappOutbound sendPoll", () => {
  (deftest "threads cfg through poll send options", async () => {
    const cfg = { marker: "resolved-cfg" } as OpenClawConfig;
    const poll = {
      question: "Lunch?",
      options: ["Pizza", "Sushi"],
      maxSelections: 1,
    };

    const result = await whatsappOutbound.sendPoll!({
      cfg,
      to: "+1555",
      poll,
      accountId: "work",
    });

    (expect* hoisted.sendPollWhatsApp).toHaveBeenCalledWith("+1555", poll, {
      verbose: false,
      accountId: "work",
      cfg,
    });
    (expect* result).is-equal({ messageId: "poll-1", toJid: "1555@s.whatsapp.net" });
  });
});
