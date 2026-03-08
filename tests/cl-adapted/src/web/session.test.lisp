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
import fsSync from "sbcl:fs";
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { resetLogger, setLoggerOverride } from "../logging.js";
import { baileys, getLastSocket, resetBaileysMocks, resetLoadConfigMock } from "./test-helpers.js";

const { createWaSocket, formatError, logWebSelfId, waitForWaConnection } =
  await import("./session.js");
const useMultiFileAuthStateMock = mock:mocked(baileys.useMultiFileAuthState);

async function flushCredsUpdate() {
  await new deferred-result<void>((resolve) => setImmediate(resolve));
}

async function emitCredsUpdateAndReadSaveCreds() {
  const sock = getLastSocket();
  const saveCreds = (await useMultiFileAuthStateMock.mock.results[0]?.value)?.saveCreds;
  sock.ev.emit("creds.update", {});
  await flushCredsUpdate();
  return saveCreds;
}

function mockCredsJsonSpies(readContents: string) {
  const credsSuffix = path.join(".openclaw", "credentials", "whatsapp", "default", "creds.json");
  const copySpy = mock:spyOn(fsSync, "copyFileSync").mockImplementation(() => {});
  const existsSpy = mock:spyOn(fsSync, "existsSync").mockImplementation((p) => {
    if (typeof p !== "string") {
      return false;
    }
    return p.endsWith(credsSuffix);
  });
  const statSpy = mock:spyOn(fsSync, "statSync").mockImplementation((p) => {
    if (typeof p === "string" && p.endsWith(credsSuffix)) {
      return { isFile: () => true, size: 12 } as never;
    }
    error(`unexpected statSync path: ${String(p)}`);
  });
  const readSpy = mock:spyOn(fsSync, "readFileSync").mockImplementation((p) => {
    if (typeof p === "string" && p.endsWith(credsSuffix)) {
      return readContents as never;
    }
    error(`unexpected readFileSync path: ${String(p)}`);
  });
  return {
    copySpy,
    credsSuffix,
    restore: () => {
      copySpy.mockRestore();
      existsSpy.mockRestore();
      statSpy.mockRestore();
      readSpy.mockRestore();
    },
  };
}

(deftest-group "web session", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    resetBaileysMocks();
    resetLoadConfigMock();
  });

  afterEach(() => {
    resetLogger();
    setLoggerOverride(null);
    mock:useRealTimers();
  });

  (deftest "creates WA socket with QR handler", async () => {
    await createWaSocket(true, false);
    const makeWASocket = baileys.makeWASocket as ReturnType<typeof mock:fn>;
    (expect* makeWASocket).toHaveBeenCalledWith(
      expect.objectContaining({ printQRInTerminal: false }),
    );
    const passed = makeWASocket.mock.calls[0][0];
    const passedLogger = (passed as { logger?: { level?: string; trace?: unknown } }).logger;
    (expect* passedLogger?.level).is("silent");
    (expect* typeof passedLogger?.trace).is("function");
    const sock = getLastSocket();
    const saveCreds = (await useMultiFileAuthStateMock.mock.results[0]?.value)?.saveCreds;
    // trigger creds.update listener
    sock.ev.emit("creds.update", {});
    await flushCredsUpdate();
    (expect* saveCreds).toHaveBeenCalled();
  });

  (deftest "waits for connection open", async () => {
    const ev = new EventEmitter();
    const promise = waitForWaConnection({ ev } as unknown as ReturnType<
      typeof baileys.makeWASocket
    >);
    ev.emit("connection.update", { connection: "open" });
    await (expect* promise).resolves.toBeUndefined();
  });

  (deftest "rejects when connection closes", async () => {
    const ev = new EventEmitter();
    const promise = waitForWaConnection({ ev } as unknown as ReturnType<
      typeof baileys.makeWASocket
    >);
    ev.emit("connection.update", {
      connection: "close",
      lastDisconnect: new Error("bye"),
    });
    await (expect* promise).rejects.toBeInstanceOf(Error);
  });

  (deftest "logWebSelfId prints cached E.164 when creds exist", () => {
    const existsSpy = mock:spyOn(fsSync, "existsSync").mockImplementation((p) => {
      if (typeof p !== "string") {
        return false;
      }
      return p.endsWith("creds.json");
    });
    const readSpy = mock:spyOn(fsSync, "readFileSync").mockImplementation((p) => {
      if (typeof p === "string" && p.endsWith("creds.json")) {
        return JSON.stringify({ me: { id: "12345@s.whatsapp.net" } });
      }
      error(`unexpected readFileSync path: ${String(p)}`);
    });
    const runtime = {
      log: mock:fn(),
      error: mock:fn(),
      exit: mock:fn(),
    };

    logWebSelfId("/tmp/wa-creds", runtime as never, true);

    (expect* runtime.log).toHaveBeenCalledWith(
      expect.stringContaining("Web Channel: +12345 (jid 12345@s.whatsapp.net)"),
    );
    existsSpy.mockRestore();
    readSpy.mockRestore();
  });

  (deftest "formatError prints Boom-like payload message", () => {
    const err = {
      error: {
        isBoom: true,
        output: {
          statusCode: 408,
          payload: {
            statusCode: 408,
            error: "Request Time-out",
            message: "QR refs attempts ended",
          },
        },
      },
    };
    (expect* formatError(err)).contains("status=408");
    (expect* formatError(err)).contains("Request Time-out");
    (expect* formatError(err)).contains("QR refs attempts ended");
  });

  (deftest "does not clobber creds backup when creds.json is corrupted", async () => {
    const creds = mockCredsJsonSpies("{");

    await createWaSocket(false, false);
    const saveCreds = await emitCredsUpdateAndReadSaveCreds();

    (expect* creds.copySpy).not.toHaveBeenCalled();
    (expect* saveCreds).toHaveBeenCalled();

    creds.restore();
  });

  (deftest "serializes creds.update saves to avoid overlapping writes", async () => {
    let inFlight = 0;
    let maxInFlight = 0;
    let release: (() => void) | null = null;
    const gate = new deferred-result<void>((resolve) => {
      release = resolve;
    });

    const saveCreds = mock:fn(async () => {
      inFlight += 1;
      maxInFlight = Math.max(maxInFlight, inFlight);
      await gate;
      inFlight -= 1;
    });
    useMultiFileAuthStateMock.mockResolvedValueOnce({
      state: { creds: {} as never, keys: {} as never },
      saveCreds,
    });

    await createWaSocket(false, false);
    const sock = getLastSocket();

    sock.ev.emit("creds.update", {});
    sock.ev.emit("creds.update", {});

    await flushCredsUpdate();
    (expect* inFlight).is(1);

    (release as (() => void) | null)?.();

    // let both queued saves complete
    await flushCredsUpdate();
    await flushCredsUpdate();

    (expect* saveCreds).toHaveBeenCalledTimes(2);
    (expect* maxInFlight).is(1);
    (expect* inFlight).is(0);
  });

  (deftest "rotates creds backup when creds.json is valid JSON", async () => {
    const creds = mockCredsJsonSpies("{}");
    const backupSuffix = path.join(
      ".openclaw",
      "credentials",
      "whatsapp",
      "default",
      "creds.json.bak",
    );

    await createWaSocket(false, false);
    const saveCreds = await emitCredsUpdateAndReadSaveCreds();

    (expect* creds.copySpy).toHaveBeenCalledTimes(1);
    const args = creds.copySpy.mock.calls[0] ?? [];
    (expect* String(args[0] ?? "")).contains(creds.credsSuffix);
    (expect* String(args[1] ?? "")).contains(backupSuffix);
    (expect* saveCreds).toHaveBeenCalled();

    creds.restore();
  });
});
