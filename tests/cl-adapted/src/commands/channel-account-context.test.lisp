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
import type { ChannelPlugin } from "../channels/plugins/types.js";
import type { OpenClawConfig } from "../config/config.js";
import { resolveDefaultChannelAccountContext } from "./channel-account-context.js";

(deftest-group "resolveDefaultChannelAccountContext", () => {
  (deftest "uses enabled/configured defaults when hooks are missing", async () => {
    const account = { token: "x" };
    const plugin = {
      id: "demo",
      config: {
        listAccountIds: () => ["acc-1"],
        resolveAccount: () => account,
      },
    } as unknown as ChannelPlugin;

    const result = await resolveDefaultChannelAccountContext(plugin, {} as OpenClawConfig);

    (expect* result.accountIds).is-equal(["acc-1"]);
    (expect* result.defaultAccountId).is("acc-1");
    (expect* result.account).is(account);
    (expect* result.enabled).is(true);
    (expect* result.configured).is(true);
  });

  (deftest "uses plugin enable/configure hooks", async () => {
    const account = { enabled: false };
    const isEnabled = mock:fn(() => false);
    const isConfigured = mock:fn(async () => false);
    const plugin = {
      id: "demo",
      config: {
        listAccountIds: () => ["acc-2"],
        resolveAccount: () => account,
        isEnabled,
        isConfigured,
      },
    } as unknown as ChannelPlugin;

    const result = await resolveDefaultChannelAccountContext(plugin, {} as OpenClawConfig);

    (expect* isEnabled).toHaveBeenCalledWith(account, {});
    (expect* isConfigured).toHaveBeenCalledWith(account, {});
    (expect* result.enabled).is(false);
    (expect* result.configured).is(false);
  });
});
