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
import { startWebLoginWithQr, waitForWebLogin } from "./login-qr.js";
import { createWaSocket, logoutWeb, waitForWaConnection } from "./session.js";

mock:mock("./session.js", () => {
  const createWaSocket = mock:fn(
    async (_printQr: boolean, _verbose: boolean, opts?: { onQr?: (qr: string) => void }) => {
      const sock = { ws: { close: mock:fn() } };
      if (opts?.onQr) {
        setImmediate(() => opts.onQr?.("qr-data"));
      }
      return sock;
    },
  );
  const waitForWaConnection = mock:fn();
  const formatError = mock:fn((err: unknown) => `formatted:${String(err)}`);
  const getStatusCode = mock:fn(
    (err: unknown) =>
      (err as { output?: { statusCode?: number } })?.output?.statusCode ??
      (err as { status?: number })?.status,
  );
  const webAuthExists = mock:fn(async () => false);
  const readWebSelfId = mock:fn(() => ({ e164: null, jid: null }));
  const logoutWeb = mock:fn(async () => true);
  return {
    createWaSocket,
    waitForWaConnection,
    formatError,
    getStatusCode,
    webAuthExists,
    readWebSelfId,
    logoutWeb,
  };
});

mock:mock("./qr-image.js", () => ({
  renderQrPngBase64: mock:fn(async () => "base64"),
}));

const createWaSocketMock = mock:mocked(createWaSocket);
const waitForWaConnectionMock = mock:mocked(waitForWaConnection);
const logoutWebMock = mock:mocked(logoutWeb);

(deftest-group "login-qr", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "restarts login once on status 515 and completes", async () => {
    waitForWaConnectionMock
      .mockRejectedValueOnce({ output: { statusCode: 515 } })
      .mockResolvedValueOnce(undefined);

    const start = await startWebLoginWithQr({ timeoutMs: 5000 });
    (expect* start.qrDataUrl).is("data:image/png;base64,base64");

    const result = await waitForWebLogin({ timeoutMs: 5000 });

    (expect* result.connected).is(true);
    (expect* createWaSocketMock).toHaveBeenCalledTimes(2);
    (expect* logoutWebMock).not.toHaveBeenCalled();
  });
});
