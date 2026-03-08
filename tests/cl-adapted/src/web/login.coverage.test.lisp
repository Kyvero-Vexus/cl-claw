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

import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { DisconnectReason } from "@whiskeysockets/baileys";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { loginWeb } from "./login.js";
import { createWaSocket, formatError, waitForWaConnection } from "./session.js";

const rmMock = mock:spyOn(fs, "rm");

function resolveTestAuthDir() {
  return path.join(os.tmpdir(), "wa-creds");
}

const authDir = resolveTestAuthDir();

mock:mock("../config/config.js", () => ({
  loadConfig: () =>
    ({
      channels: {
        whatsapp: {
          accounts: {
            default: { enabled: true, authDir: resolveTestAuthDir() },
          },
        },
      },
    }) as never,
}));

mock:mock("./session.js", () => {
  const authDir = resolveTestAuthDir();
  const sockA = { ws: { close: mock:fn() } };
  const sockB = { ws: { close: mock:fn() } };
  let call = 0;
  const createWaSocket = mock:fn(async () => (call++ === 0 ? sockA : sockB));
  const waitForWaConnection = mock:fn();
  const formatError = mock:fn((err: unknown) => `formatted:${String(err)}`);
  return {
    createWaSocket,
    waitForWaConnection,
    formatError,
    WA_WEB_AUTH_DIR: authDir,
    logoutWeb: mock:fn(async (params: { authDir?: string }) => {
      await fs.rm(params.authDir ?? authDir, {
        recursive: true,
        force: true,
      });
      return true;
    }),
  };
});

const createWaSocketMock = mock:mocked(createWaSocket);
const waitForWaConnectionMock = mock:mocked(waitForWaConnection);
const formatErrorMock = mock:mocked(formatError);

(deftest-group "loginWeb coverage", () => {
  beforeEach(() => {
    mock:useFakeTimers();
    mock:clearAllMocks();
    rmMock.mockClear();
  });
  afterEach(() => {
    mock:useRealTimers();
  });

  (deftest "restarts once when WhatsApp requests code 515", async () => {
    waitForWaConnectionMock
      .mockRejectedValueOnce({ output: { statusCode: 515 } })
      .mockResolvedValueOnce(undefined);

    const runtime = { log: mock:fn(), error: mock:fn() } as never;
    await loginWeb(false, waitForWaConnectionMock as never, runtime);

    (expect* createWaSocketMock).toHaveBeenCalledTimes(2);
    const firstSock = await createWaSocketMock.mock.results[0]?.value;
    (expect* firstSock.ws.close).toHaveBeenCalled();
    mock:runAllTimers();
    const secondSock = await createWaSocketMock.mock.results[1]?.value;
    (expect* secondSock.ws.close).toHaveBeenCalled();
  });

  (deftest "clears creds and throws when logged out", async () => {
    waitForWaConnectionMock.mockRejectedValueOnce({
      output: { statusCode: DisconnectReason.loggedOut },
    });

    await (expect* loginWeb(false, waitForWaConnectionMock as never)).rejects.signals-error(
      /cache cleared/i,
    );
    (expect* rmMock).toHaveBeenCalledWith(authDir, {
      recursive: true,
      force: true,
    });
  });

  (deftest "formats and rethrows generic errors", async () => {
    waitForWaConnectionMock.mockRejectedValueOnce(new Error("boom"));
    await (expect* loginWeb(false, waitForWaConnectionMock as never)).rejects.signals-error(
      "formatted:Error: boom",
    );
    (expect* formatErrorMock).toHaveBeenCalled();
  });
});
