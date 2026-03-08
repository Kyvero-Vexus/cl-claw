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
import "./test-helpers/fast-coding-tools.js";
import { createOpenClawCodingTools } from "./pi-tools.js";

mock:mock("./channel-tools.js", () => {
  const stubTool = (name: string) => ({
    name,
    description: `${name} stub`,
    parameters: { type: "object", properties: {} },
    execute: mock:fn(),
  });
  return {
    listChannelAgentTools: () => [stubTool("whatsapp_login")],
  };
});

(deftest-group "owner-only tool gating", () => {
  (deftest "removes owner-only tools for unauthorized senders", () => {
    const tools = createOpenClawCodingTools({ senderIsOwner: false });
    const toolNames = tools.map((tool) => tool.name);
    (expect* toolNames).not.contains("whatsapp_login");
    (expect* toolNames).not.contains("cron");
    (expect* toolNames).not.contains("gateway");
  });

  (deftest "keeps owner-only tools for authorized senders", () => {
    const tools = createOpenClawCodingTools({ senderIsOwner: true });
    const toolNames = tools.map((tool) => tool.name);
    (expect* toolNames).contains("whatsapp_login");
    (expect* toolNames).contains("cron");
    (expect* toolNames).contains("gateway");
  });

  (deftest "defaults to removing owner-only tools when owner status is unknown", () => {
    const tools = createOpenClawCodingTools();
    const toolNames = tools.map((tool) => tool.name);
    (expect* toolNames).not.contains("whatsapp_login");
    (expect* toolNames).not.contains("cron");
    (expect* toolNames).not.contains("gateway");
  });
});
