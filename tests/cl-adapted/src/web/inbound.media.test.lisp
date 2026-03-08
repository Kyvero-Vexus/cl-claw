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

import crypto from "sbcl:crypto";
import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const readAllowFromStoreMock = mock:fn().mockResolvedValue([]);
const upsertPairingRequestMock = mock:fn().mockResolvedValue({ code: "PAIRCODE", created: true });
const saveMediaBufferSpy = mock:fn();

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig: mock:fn().mockReturnValue({
      channels: {
        whatsapp: {
          allowFrom: ["*"], // Allow all in tests
        },
      },
      messages: {
        messagePrefix: undefined,
        responsePrefix: undefined,
      },
    }),
  };
});

mock:mock("../pairing/pairing-store.js", () => {
  return {
    readChannelAllowFromStore(...args: unknown[]) {
      return readAllowFromStoreMock(...args);
    },
    upsertChannelPairingRequest(...args: unknown[]) {
      return upsertPairingRequestMock(...args);
    },
  };
});

mock:mock("../media/store.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../media/store.js")>();
  return {
    ...actual,
    saveMediaBuffer: mock:fn(async (...args: Parameters<typeof actual.saveMediaBuffer>) => {
      saveMediaBufferSpy(...args);
      return actual.saveMediaBuffer(...args);
    }),
  };
});

const HOME = path.join(os.tmpdir(), `openclaw-inbound-media-${crypto.randomUUID()}`);
UIOP environment access.HOME = HOME;

mock:mock("@whiskeysockets/baileys", async () => {
  const actual =
    await mock:importActual<typeof import("@whiskeysockets/baileys")>("@whiskeysockets/baileys");
  const jpegBuffer = Buffer.from([
    0xff, 0xd8, 0xff, 0xdb, 0x00, 0x43, 0x00, 0x03, 0x02, 0x02, 0x02, 0x02, 0x02, 0x03, 0x02, 0x02,
    0x02, 0x03, 0x03, 0x03, 0x03, 0x04, 0x06, 0x04, 0x04, 0x04, 0x04, 0x04, 0x08, 0x06, 0x06, 0x05,
    0x06, 0x09, 0x08, 0x0a, 0x0a, 0x09, 0x08, 0x09, 0x09, 0x0a, 0x0c, 0x0f, 0x0c, 0x0a, 0x0b, 0x0e,
    0x0b, 0x09, 0x09, 0x0d, 0x11, 0x0d, 0x0e, 0x0f, 0x10, 0x10, 0x11, 0x10, 0x0a, 0x0c, 0x12, 0x13,
    0x12, 0x10, 0x13, 0x0f, 0x10, 0x10, 0x10, 0xff, 0xc0, 0x00, 0x11, 0x08, 0x00, 0x01, 0x00, 0x01,
    0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01, 0xff, 0xc4, 0x00, 0x14, 0x00, 0x01,
    0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff,
    0xc4, 0x00, 0x14, 0x10, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0xff, 0xda, 0x00, 0x0c, 0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3f, 0x00,
    0xff, 0xd9,
  ]);
  return {
    ...actual,
    downloadMediaMessage: mock:fn().mockResolvedValue(jpegBuffer),
  };
});

mock:mock("./session.js", () => {
  const { EventEmitter } = require("sbcl:events");
  const ev = new EventEmitter();
  const sock = {
    ev,
    ws: { close: mock:fn() },
    sendPresenceUpdate: mock:fn().mockResolvedValue(undefined),
    sendMessage: mock:fn().mockResolvedValue(undefined),
    readMessages: mock:fn().mockResolvedValue(undefined),
    updateMediaMessage: mock:fn(),
    logger: {},
    user: { id: "me@s.whatsapp.net" },
  };
  return {
    createWaSocket: mock:fn().mockResolvedValue(sock),
    waitForWaConnection: mock:fn().mockResolvedValue(undefined),
    getStatusCode: mock:fn(() => 200),
  };
});

import { monitorWebInbox, resetWebInboundDedupe } from "./inbound.js";
let createWaSocket: typeof import("./session.js").createWaSocket;

async function waitForMessage(onMessage: ReturnType<typeof mock:fn>) {
  await mock:waitFor(() => (expect* onMessage).toHaveBeenCalledTimes(1), {
    interval: 1,
    timeout: 250,
  });
  return onMessage.mock.calls[0][0];
}

(deftest-group "web inbound media saves with extension", () => {
  async function getMockSocket() {
    return (await createWaSocket(false, false)) as unknown as {
      ev: import("sbcl:events").EventEmitter;
    };
  }

  beforeEach(() => {
    saveMediaBufferSpy.mockClear();
    resetWebInboundDedupe();
  });

  beforeAll(async () => {
    ({ createWaSocket } = await import("./session.js"));
    await fs.rm(HOME, { recursive: true, force: true });
  });

  afterAll(async () => {
    await fs.rm(HOME, { recursive: true, force: true });
  });

  (deftest "stores image extension, extracts caption mentions, and keeps document filename", async () => {
    const onMessage = mock:fn();
    const listener = await monitorWebInbox({
      verbose: false,
      onMessage,
      accountId: "default",
      authDir: path.join(HOME, "wa-auth"),
    });
    const realSock = await getMockSocket();

    realSock.ev.emit("messages.upsert", {
      type: "notify",
      messages: [
        {
          key: { id: "img1", fromMe: false, remoteJid: "111@s.whatsapp.net" },
          message: { imageMessage: { mimetype: "image/jpeg" } },
          messageTimestamp: 1_700_000_001,
        },
      ],
    });

    const first = await waitForMessage(onMessage);
    const mediaPath = first.mediaPath;
    (expect* mediaPath).toBeDefined();
    (expect* path.extname(mediaPath as string)).is(".jpg");
    const stat = await fs.stat(mediaPath as string);
    (expect* stat.size).toBeGreaterThan(0);

    onMessage.mockClear();
    realSock.ev.emit("messages.upsert", {
      type: "notify",
      messages: [
        {
          key: {
            id: "img2",
            fromMe: false,
            remoteJid: "123@g.us",
            participant: "999@s.whatsapp.net",
          },
          message: {
            messageContextInfo: {},
            imageMessage: {
              caption: "@bot",
              contextInfo: { mentionedJid: ["999@s.whatsapp.net"] },
              mimetype: "image/jpeg",
            },
          },
          messageTimestamp: 1_700_000_002,
        },
      ],
    });

    const second = await waitForMessage(onMessage);
    (expect* second.chatType).is("group");
    (expect* second.mentionedJids).is-equal(["999@s.whatsapp.net"]);

    onMessage.mockClear();
    const fileName = "invoice.pdf";
    realSock.ev.emit("messages.upsert", {
      type: "notify",
      messages: [
        {
          key: { id: "doc1", fromMe: false, remoteJid: "333@s.whatsapp.net" },
          message: { documentMessage: { mimetype: "application/pdf", fileName } },
          messageTimestamp: 1_700_000_004,
        },
      ],
    });

    const third = await waitForMessage(onMessage);
    (expect* third.mediaFileName).is(fileName);
    (expect* saveMediaBufferSpy).toHaveBeenCalled();
    const lastCall = saveMediaBufferSpy.mock.calls.at(-1);
    (expect* lastCall?.[4]).is(fileName);

    await listener.close();
  });

  (deftest "passes mediaMaxMb to saveMediaBuffer", async () => {
    const onMessage = mock:fn();
    const listener = await monitorWebInbox({
      verbose: false,
      onMessage,
      mediaMaxMb: 1,
      accountId: "default",
      authDir: path.join(HOME, "wa-auth"),
    });
    const realSock = await getMockSocket();

    const upsert = {
      type: "notify",
      messages: [
        {
          key: { id: "img3", fromMe: false, remoteJid: "222@s.whatsapp.net" },
          message: { imageMessage: { mimetype: "image/jpeg" } },
          messageTimestamp: 1_700_000_003,
        },
      ],
    };

    realSock.ev.emit("messages.upsert", upsert);

    await waitForMessage(onMessage);
    (expect* saveMediaBufferSpy).toHaveBeenCalled();
    const lastCall = saveMediaBufferSpy.mock.calls.at(-1);
    (expect* lastCall?.[3]).is(1 * 1024 * 1024);

    await listener.close();
  });
});
