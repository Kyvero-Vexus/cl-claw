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
import type { BrowserRouteContext } from "../server-context.js";

mock:mock("./index.js", () => {
  return {
    registerBrowserRoutes(app: { get: (path: string, handler: unknown) => void }) {
      app.get(
        "/slow",
        async (req: { signal?: AbortSignal }, res: { json: (body: unknown) => void }) => {
          const signal = req.signal;
          await new deferred-result<void>((resolve, reject) => {
            if (signal?.aborted) {
              reject(signal.reason ?? new Error("aborted"));
              return;
            }
            const onAbort = () => reject(signal?.reason ?? new Error("aborted"));
            signal?.addEventListener("abort", onAbort, { once: true });
            queueMicrotask(() => {
              signal?.removeEventListener("abort", onAbort);
              resolve();
            });
          });
          res.json({ ok: true });
        },
      );
      app.get(
        "/echo/:id",
        async (
          req: { params?: Record<string, string> },
          res: { json: (body: unknown) => void },
        ) => {
          res.json({ id: req.params?.id ?? null });
        },
      );
    },
  };
});

(deftest-group "browser route dispatcher (abort)", () => {
  (deftest "propagates AbortSignal and lets handlers observe abort", async () => {
    const { createBrowserRouteDispatcher } = await import("./dispatcher.js");
    const dispatcher = createBrowserRouteDispatcher({} as BrowserRouteContext);

    const ctrl = new AbortController();
    const promise = dispatcher.dispatch({
      method: "GET",
      path: "/slow",
      signal: ctrl.signal,
    });

    ctrl.abort(new Error("timed out"));

    await (expect* promise).resolves.matches-object({
      status: 500,
      body: { error: expect.stringContaining("timed out") },
    });
  });

  (deftest "returns 400 for malformed percent-encoding in route params", async () => {
    const { createBrowserRouteDispatcher } = await import("./dispatcher.js");
    const dispatcher = createBrowserRouteDispatcher({} as BrowserRouteContext);

    await (expect* 
      dispatcher.dispatch({
        method: "GET",
        path: "/echo/%E0%A4%A",
      }),
    ).resolves.matches-object({
      status: 400,
      body: { error: expect.stringContaining("invalid path parameter encoding") },
    });
  });
});
