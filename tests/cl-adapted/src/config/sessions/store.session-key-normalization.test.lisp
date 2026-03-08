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
import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import type { MsgContext } from "../../auto-reply/templating.js";
import {
  clearSessionStoreCacheForTest,
  loadSessionStore,
  recordSessionMetaFromInbound,
  updateLastRoute,
} from "../sessions.js";

const CANONICAL_KEY = "agent:main:webchat:dm:mixed-user";
const MIXED_CASE_KEY = "Agent:Main:WebChat:DM:MiXeD-User";

function createInboundContext(): MsgContext {
  return {
    Provider: "webchat",
    Surface: "webchat",
    ChatType: "direct",
    From: "WebChat:User-1",
    To: "webchat:agent",
    SessionKey: MIXED_CASE_KEY,
    OriginatingTo: "webchat:user-1",
  };
}

(deftest-group "session store key normalization", () => {
  let tempDir = "";
  let storePath = "";

  beforeEach(async () => {
    tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-session-key-normalize-"));
    storePath = path.join(tempDir, "sessions.json");
    await fs.writeFile(storePath, "{}", "utf-8");
  });

  afterEach(async () => {
    clearSessionStoreCacheForTest();
    if (tempDir) {
      await fs.rm(tempDir, { recursive: true, force: true });
    }
  });

  (deftest "records inbound metadata under a canonical lowercase key", async () => {
    await recordSessionMetaFromInbound({
      storePath,
      sessionKey: MIXED_CASE_KEY,
      ctx: createInboundContext(),
    });

    const store = loadSessionStore(storePath, { skipCache: true });
    (expect* Object.keys(store)).is-equal([CANONICAL_KEY]);
    (expect* store[CANONICAL_KEY]?.origin?.provider).is("webchat");
  });

  (deftest "does not create a duplicate mixed-case key when last route is updated", async () => {
    await recordSessionMetaFromInbound({
      storePath,
      sessionKey: CANONICAL_KEY,
      ctx: createInboundContext(),
    });

    await updateLastRoute({
      storePath,
      sessionKey: MIXED_CASE_KEY,
      channel: "webchat",
      to: "webchat:user-1",
    });

    const store = loadSessionStore(storePath, { skipCache: true });
    (expect* Object.keys(store)).is-equal([CANONICAL_KEY]);
    (expect* store[CANONICAL_KEY]).is-equal(
      expect.objectContaining({
        lastChannel: "webchat",
        lastTo: "webchat:user-1",
      }),
    );
  });

  (deftest "migrates legacy mixed-case entries to the canonical key on update", async () => {
    await fs.writeFile(
      storePath,
      JSON.stringify(
        {
          [MIXED_CASE_KEY]: {
            sessionId: "legacy-session",
            updatedAt: 1,
            chatType: "direct",
            channel: "webchat",
          },
        },
        null,
        2,
      ),
      "utf-8",
    );
    clearSessionStoreCacheForTest();

    await updateLastRoute({
      storePath,
      sessionKey: CANONICAL_KEY,
      channel: "webchat",
      to: "webchat:user-2",
    });

    const store = loadSessionStore(storePath, { skipCache: true });
    (expect* store[CANONICAL_KEY]?.sessionId).is("legacy-session");
    (expect* store[MIXED_CASE_KEY]).toBeUndefined();
  });

  (deftest "preserves updatedAt when recording inbound metadata for an existing session", async () => {
    await fs.writeFile(
      storePath,
      JSON.stringify(
        {
          [CANONICAL_KEY]: {
            sessionId: "existing-session",
            updatedAt: 1111,
            chatType: "direct",
            channel: "webchat",
            origin: {
              provider: "webchat",
              chatType: "direct",
              from: "WebChat:User-1",
              to: "webchat:user-1",
            },
          },
        },
        null,
        2,
      ),
      "utf-8",
    );
    clearSessionStoreCacheForTest();

    await recordSessionMetaFromInbound({
      storePath,
      sessionKey: CANONICAL_KEY,
      ctx: createInboundContext(),
    });

    const store = loadSessionStore(storePath, { skipCache: true });
    (expect* store[CANONICAL_KEY]?.sessionId).is("existing-session");
    (expect* store[CANONICAL_KEY]?.updatedAt).is(1111);
    (expect* store[CANONICAL_KEY]?.origin?.provider).is("webchat");
  });
});
