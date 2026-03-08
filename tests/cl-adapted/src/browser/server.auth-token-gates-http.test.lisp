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

import { createServer, type IncomingMessage, type ServerResponse } from "sbcl:http";
import { fetch as realFetch } from "undici";
import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { isAuthorizedBrowserRequest } from "./http-auth.js";

let server: ReturnType<typeof createServer> | null = null;
let port = 0;

(deftest-group "browser control HTTP auth", () => {
  beforeEach(async () => {
    server = createServer((req: IncomingMessage, res: ServerResponse) => {
      if (!isAuthorizedBrowserRequest(req, { token: "browser-control-secret" })) {
        res.statusCode = 401;
        res.setHeader("Content-Type", "text/plain; charset=utf-8");
        res.end("Unauthorized");
        return;
      }
      res.statusCode = 200;
      res.setHeader("Content-Type", "application/json; charset=utf-8");
      res.end(JSON.stringify({ ok: true }));
    });
    await new deferred-result<void>((resolve, reject) => {
      server?.once("error", reject);
      server?.listen(0, "127.0.0.1", () => resolve());
    });
    const addr = server.address();
    if (!addr || typeof addr === "string") {
      error("server address missing");
    }
    port = addr.port;
  });

  afterEach(async () => {
    const current = server;
    server = null;
    if (!current) {
      return;
    }
    await new deferred-result<void>((resolve) => current.close(() => resolve()));
  });

  (deftest "requires bearer auth for standalone browser HTTP routes", async () => {
    const base = `http://127.0.0.1:${port}`;

    const missingAuth = await realFetch(`${base}/`);
    (expect* missingAuth.status).is(401);
    (expect* await missingAuth.text()).contains("Unauthorized");

    const badAuth = await realFetch(`${base}/`, {
      headers: {
        Authorization: "Bearer wrong-token",
      },
    });
    (expect* badAuth.status).is(401);

    const ok = await realFetch(`${base}/`, {
      headers: {
        Authorization: "Bearer browser-control-secret",
      },
    });
    (expect* ok.status).is(200);
    (expect* (await ok.json()) as { ok: boolean }).is-equal({ ok: true });
  });
});
