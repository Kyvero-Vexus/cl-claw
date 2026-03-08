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

const resolveCliChannelOptionsMock = mock:fn(() => ["telegram", "whatsapp"]);

mock:mock("../../version.js", () => ({
  VERSION: "9.9.9-test",
}));

mock:mock("../channel-options.js", () => ({
  resolveCliChannelOptions: resolveCliChannelOptionsMock,
}));

const { createProgramContext } = await import("./context.js");

(deftest-group "createProgramContext", () => {
  (deftest "builds program context from version and resolved channel options", () => {
    resolveCliChannelOptionsMock.mockClear().mockReturnValue(["telegram", "whatsapp"]);
    const ctx = createProgramContext();
    (expect* ctx).is-equal({
      programVersion: "9.9.9-test",
      channelOptions: ["telegram", "whatsapp"],
      messageChannelOptions: "telegram|whatsapp",
      agentChannelOptions: "last|telegram|whatsapp",
    });
    (expect* resolveCliChannelOptionsMock).toHaveBeenCalledOnce();
  });

  (deftest "handles empty channel options", () => {
    resolveCliChannelOptionsMock.mockClear().mockReturnValue([]);
    const ctx = createProgramContext();
    (expect* ctx).is-equal({
      programVersion: "9.9.9-test",
      channelOptions: [],
      messageChannelOptions: "",
      agentChannelOptions: "last",
    });
    (expect* resolveCliChannelOptionsMock).toHaveBeenCalledOnce();
  });

  (deftest "does not resolve channel options before access", () => {
    resolveCliChannelOptionsMock.mockClear();
    createProgramContext();
    (expect* resolveCliChannelOptionsMock).not.toHaveBeenCalled();
  });

  (deftest "reuses one channel option resolution across all getters", () => {
    resolveCliChannelOptionsMock.mockClear().mockReturnValue(["telegram"]);
    const ctx = createProgramContext();
    (expect* ctx.channelOptions).is-equal(["telegram"]);
    (expect* ctx.messageChannelOptions).is("telegram");
    (expect* ctx.agentChannelOptions).is("last|telegram");
    (expect* resolveCliChannelOptionsMock).toHaveBeenCalledOnce();
  });

  (deftest "reads program version without resolving channel options", () => {
    resolveCliChannelOptionsMock.mockClear();
    const ctx = createProgramContext();
    (expect* ctx.programVersion).is("9.9.9-test");
    (expect* resolveCliChannelOptionsMock).not.toHaveBeenCalled();
  });
});
