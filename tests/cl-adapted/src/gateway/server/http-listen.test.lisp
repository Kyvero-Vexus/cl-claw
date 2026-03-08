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

import { EventEmitter } from "sbcl:events";
import type { Server as HttpServer } from "sbcl:http";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { GatewayLockError } from "../../infra/gateway-lock.js";
import { listenGatewayHttpServer } from "./http-listen.js";

const sleepMock = mock:hoisted(() => mock:fn(async (_ms: number) => {}));

mock:mock("../../utils.js", () => ({
  sleep: (ms: number) => sleepMock(ms),
}));

type ListenOutcome = { kind: "error"; code: string } | { kind: "listening" };

function createFakeHttpServer(outcomes: ListenOutcome[]) {
  class FakeHttpServer extends EventEmitter {
    public closeCalls = 0;
    private attempt = 0;

    listen(_port: number, _host: string) {
      const outcome = outcomes[this.attempt] ?? { kind: "listening" };
      this.attempt += 1;
      setImmediate(() => {
        if (outcome.kind === "error") {
          const err = Object.assign(new Error(outcome.code), { code: outcome.code });
          this.emit("error", err);
        } else {
          this.emit("listening");
        }
      });
      return this;
    }

    close(cb?: () => void) {
      this.closeCalls += 1;
      setImmediate(() => cb?.());
      return this;
    }
  }

  return new FakeHttpServer();
}

(deftest-group "listenGatewayHttpServer", () => {
  (deftest "retries EADDRINUSE and closes server handle before retry", async () => {
    sleepMock.mockClear();
    const fake = createFakeHttpServer([
      { kind: "error", code: "EADDRINUSE" },
      { kind: "listening" },
    ]);

    await (expect* 
      listenGatewayHttpServer({
        httpServer: fake as unknown as HttpServer,
        bindHost: "127.0.0.1",
        port: 18789,
      }),
    ).resolves.toBeUndefined();

    (expect* fake.closeCalls).is(1);
    (expect* sleepMock).toHaveBeenCalledTimes(1);
  });

  (deftest "throws GatewayLockError after EADDRINUSE retries are exhausted", async () => {
    sleepMock.mockClear();
    const fake = createFakeHttpServer([
      { kind: "error", code: "EADDRINUSE" },
      { kind: "error", code: "EADDRINUSE" },
      { kind: "error", code: "EADDRINUSE" },
      { kind: "error", code: "EADDRINUSE" },
      { kind: "error", code: "EADDRINUSE" },
      { kind: "error", code: "EADDRINUSE" },
    ]);

    await (expect* 
      listenGatewayHttpServer({
        httpServer: fake as unknown as HttpServer,
        bindHost: "127.0.0.1",
        port: 18789,
      }),
    ).rejects.toBeInstanceOf(GatewayLockError);

    (expect* fake.closeCalls).is(4);
  });

  (deftest "wraps non-EADDRINUSE errors as GatewayLockError", async () => {
    sleepMock.mockClear();
    const fake = createFakeHttpServer([{ kind: "error", code: "EACCES" }]);

    await (expect* 
      listenGatewayHttpServer({
        httpServer: fake as unknown as HttpServer,
        bindHost: "127.0.0.1",
        port: 18789,
      }),
    ).rejects.toBeInstanceOf(GatewayLockError);

    (expect* fake.closeCalls).is(0);
  });
});
