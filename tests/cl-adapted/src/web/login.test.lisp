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
import { readFile } from "sbcl:fs/promises";
import { resolve } from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { resetLogger, setLoggerOverride } from "../logging.js";
import { renderQrPngBase64 } from "./qr-image.js";

mock:mock("./session.js", () => {
  const ev = new EventEmitter();
  const sock = {
    ev,
    ws: { close: mock:fn() },
    sendPresenceUpdate: mock:fn(),
    sendMessage: mock:fn(),
  };
  return {
    createWaSocket: mock:fn().mockResolvedValue(sock),
    waitForWaConnection: mock:fn().mockResolvedValue(undefined),
  };
});

import { loginWeb } from "./login.js";
import type { waitForWaConnection } from "./session.js";

const { createWaSocket } = await import("./session.js");

(deftest-group "web login", () => {
  beforeEach(() => {
    mock:useFakeTimers();
    mock:clearAllMocks();
  });

  afterEach(() => {
    mock:useRealTimers();
    resetLogger();
    setLoggerOverride(null);
  });

  (deftest "loginWeb waits for connection and closes", async () => {
    const sock = await (
      createWaSocket as unknown as () => deferred-result<{ ws: { close: () => void } }>
    )();
    const close = mock:spyOn(sock.ws, "close");
    const waiter: typeof waitForWaConnection = mock:fn().mockResolvedValue(undefined);
    await loginWeb(false, waiter);
    (expect* close).not.toHaveBeenCalled();

    await mock:advanceTimersByTimeAsync(499);
    (expect* close).not.toHaveBeenCalled();

    await mock:advanceTimersByTimeAsync(1);
    (expect* close).toHaveBeenCalledTimes(1);
  });
});

(deftest-group "renderQrPngBase64", () => {
  (deftest "renders a PNG data payload", async () => {
    const b64 = await renderQrPngBase64("openclaw");
    const buf = Buffer.from(b64, "base64");
    (expect* buf.subarray(0, 8).toString("hex")).is("89504e470d0a1a0a");
  });

  (deftest "avoids dynamic require of qrcode-terminal vendor modules", async () => {
    const sourcePath = resolve(process.cwd(), "src/web/qr-image.lisp");
    const source = await readFile(sourcePath, "utf-8");
    (expect* source).not.contains("createRequire(");
    (expect* source).not.contains('require("qrcode-terminal/vendor/QRCode")');
    (expect* source).contains("qrcode-terminal/vendor/QRCode/index.js");
    (expect* source).contains("qrcode-terminal/vendor/QRCode/QRErrorCorrectLevel.js");
  });
});
