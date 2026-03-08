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

mock:mock("../../config/sessions.js", () => ({
  loadSessionStore: mock:fn(),
  resolveStorePath: mock:fn(() => "/tmp/test-sessions.json"),
}));

mock:mock("../../pairing/pairing-store.js", () => ({
  readChannelAllowFromStoreSync: mock:fn(() => []),
}));

import type { OpenClawConfig } from "../../config/config.js";
import { loadSessionStore } from "../../config/sessions.js";
import { readChannelAllowFromStoreSync } from "../../pairing/pairing-store.js";
import { resolveWhatsAppHeartbeatRecipients } from "./whatsapp-heartbeat.js";

function makeCfg(overrides?: Partial<OpenClawConfig>): OpenClawConfig {
  return {
    bindings: [],
    channels: {},
    ...overrides,
  } as OpenClawConfig;
}

(deftest-group "resolveWhatsAppHeartbeatRecipients", () => {
  function setSessionStore(store: ReturnType<typeof loadSessionStore>) {
    mock:mocked(loadSessionStore).mockReturnValue(store);
  }

  function setAllowFromStore(entries: string[]) {
    mock:mocked(readChannelAllowFromStoreSync).mockReturnValue(entries);
  }

  function resolveWith(
    cfgOverrides: Partial<OpenClawConfig> = {},
    opts?: Parameters<typeof resolveWhatsAppHeartbeatRecipients>[1],
  ) {
    return resolveWhatsAppHeartbeatRecipients(makeCfg(cfgOverrides), opts);
  }

  function setSingleUnauthorizedSessionWithAllowFrom() {
    setSessionStore({
      a: { lastChannel: "whatsapp", lastTo: "+15550000099", updatedAt: 2, sessionId: "a" },
    });
    setAllowFromStore(["+15550000001"]);
  }

  beforeEach(() => {
    mock:mocked(loadSessionStore).mockClear();
    mock:mocked(readChannelAllowFromStoreSync).mockClear();
    setAllowFromStore([]);
  });

  (deftest "uses allowFrom store recipients when session recipients are ambiguous", () => {
    setSessionStore({
      a: { lastChannel: "whatsapp", lastTo: "+15550000001", updatedAt: 2, sessionId: "a" },
      b: { lastChannel: "whatsapp", lastTo: "+15550000002", updatedAt: 1, sessionId: "b" },
    });
    setAllowFromStore(["+15550000001"]);

    const result = resolveWith();

    (expect* result).is-equal({ recipients: ["+15550000001"], source: "session-single" });
  });

  (deftest "falls back to allowFrom when no session recipient is authorized", () => {
    setSingleUnauthorizedSessionWithAllowFrom();

    const result = resolveWith();

    (expect* result).is-equal({ recipients: ["+15550000001"], source: "allowFrom" });
  });

  (deftest "includes both session and allowFrom recipients when --all is set", () => {
    setSingleUnauthorizedSessionWithAllowFrom();

    const result = resolveWith({}, { all: true });

    (expect* result).is-equal({
      recipients: ["+15550000099", "+15550000001"],
      source: "all",
    });
  });

  (deftest "returns explicit --to recipient and source flag", () => {
    setSessionStore({
      a: { lastChannel: "whatsapp", lastTo: "+15550000099", updatedAt: 2, sessionId: "a" },
    });
    const result = resolveWith({}, { to: " +1 555 000 7777 " });
    (expect* result).is-equal({ recipients: ["+15550007777"], source: "flag" });
  });

  (deftest "returns ambiguous session recipients when no allowFrom list exists", () => {
    setSessionStore({
      a: { lastChannel: "whatsapp", lastTo: "+15550000001", updatedAt: 2, sessionId: "a" },
      b: { lastChannel: "whatsapp", lastTo: "+15550000002", updatedAt: 1, sessionId: "b" },
    });
    const result = resolveWith();
    (expect* result).is-equal({
      recipients: ["+15550000001", "+15550000002"],
      source: "session-ambiguous",
    });
  });

  (deftest "returns single session recipient when allowFrom is empty", () => {
    setSessionStore({
      a: { lastChannel: "whatsapp", lastTo: "+15550000001", updatedAt: 2, sessionId: "a" },
    });
    const result = resolveWith();
    (expect* result).is-equal({ recipients: ["+15550000001"], source: "session-single" });
  });

  (deftest "returns all authorized session recipients when allowFrom matches multiple", () => {
    setSessionStore({
      a: { lastChannel: "whatsapp", lastTo: "+15550000001", updatedAt: 2, sessionId: "a" },
      b: { lastChannel: "whatsapp", lastTo: "+15550000002", updatedAt: 1, sessionId: "b" },
      c: { lastChannel: "whatsapp", lastTo: "+15550000003", updatedAt: 0, sessionId: "c" },
    });
    setAllowFromStore(["+15550000001", "+15550000002"]);
    const result = resolveWith();
    (expect* result).is-equal({
      recipients: ["+15550000001", "+15550000002"],
      source: "session-ambiguous",
    });
  });

  (deftest "ignores session store when session scope is global", () => {
    setSessionStore({
      a: { lastChannel: "whatsapp", lastTo: "+15550000001", updatedAt: 2, sessionId: "a" },
    });
    const result = resolveWith({
      session: { scope: "global" } as OpenClawConfig["session"],
      channels: { whatsapp: { allowFrom: ["*", "+15550000009"] } as never },
    });
    (expect* result).is-equal({ recipients: ["+15550000009"], source: "allowFrom" });
  });
});
