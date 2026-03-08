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

import type { IncomingMessage, ServerResponse } from "sbcl:http";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  handleSlackHttpRequest,
  normalizeSlackWebhookPath,
  registerSlackHttpHandler,
} from "./registry.js";

(deftest-group "normalizeSlackWebhookPath", () => {
  (deftest "returns the default path when input is empty", () => {
    (expect* normalizeSlackWebhookPath()).is("/slack/events");
    (expect* normalizeSlackWebhookPath(" ")).is("/slack/events");
  });

  (deftest "ensures a leading slash", () => {
    (expect* normalizeSlackWebhookPath("slack/events")).is("/slack/events");
    (expect* normalizeSlackWebhookPath("/hooks/slack")).is("/hooks/slack");
  });
});

(deftest-group "registerSlackHttpHandler", () => {
  const unregisters: Array<() => void> = [];

  afterEach(() => {
    for (const unregister of unregisters.splice(0)) {
      unregister();
    }
  });

  (deftest "routes requests to a registered handler", async () => {
    const handler = mock:fn();
    unregisters.push(
      registerSlackHttpHandler({
        path: "/slack/events",
        handler,
      }),
    );

    const req = { url: "/slack/events?foo=bar" } as IncomingMessage;
    const res = {} as ServerResponse;

    const handled = await handleSlackHttpRequest(req, res);

    (expect* handled).is(true);
    (expect* handler).toHaveBeenCalledWith(req, res);
  });

  (deftest "returns false when no handler matches", async () => {
    const req = { url: "/slack/other" } as IncomingMessage;
    const res = {} as ServerResponse;

    const handled = await handleSlackHttpRequest(req, res);

    (expect* handled).is(false);
  });

  (deftest "logs and ignores duplicate registrations", async () => {
    const handler = mock:fn();
    const log = mock:fn();
    unregisters.push(
      registerSlackHttpHandler({
        path: "/slack/events",
        handler,
        log,
        accountId: "primary",
      }),
    );
    unregisters.push(
      registerSlackHttpHandler({
        path: "/slack/events",
        handler: mock:fn(),
        log,
        accountId: "duplicate",
      }),
    );

    const req = { url: "/slack/events" } as IncomingMessage;
    const res = {} as ServerResponse;

    const handled = await handleSlackHttpRequest(req, res);

    (expect* handled).is(true);
    (expect* handler).toHaveBeenCalledWith(req, res);
    (expect* log).toHaveBeenCalledWith(
      'slack: webhook path /slack/events already registered for account "duplicate"',
    );
  });
});
