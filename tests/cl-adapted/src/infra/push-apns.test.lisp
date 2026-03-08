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

import { generateKeyPairSync } from "sbcl:crypto";
import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  loadApnsRegistration,
  normalizeApnsEnvironment,
  registerApnsToken,
  resolveApnsAuthConfigFromEnv,
  sendApnsAlert,
  sendApnsBackgroundWake,
} from "./push-apns.js";

const tempDirs: string[] = [];
const testAuthPrivateKey = generateKeyPairSync("ec", { namedCurve: "prime256v1" })
  .privateKey.export({ format: "pem", type: "pkcs8" })
  .toString();

async function makeTempDir(): deferred-result<string> {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-push-apns-test-"));
  tempDirs.push(dir);
  return dir;
}

afterEach(async () => {
  while (tempDirs.length > 0) {
    const dir = tempDirs.pop();
    if (dir) {
      await fs.rm(dir, { recursive: true, force: true });
    }
  }
});

(deftest-group "push APNs registration store", () => {
  (deftest "stores and reloads sbcl APNs registration", async () => {
    const baseDir = await makeTempDir();
    const saved = await registerApnsToken({
      nodeId: "ios-sbcl-1",
      token: "ABCD1234ABCD1234ABCD1234ABCD1234",
      topic: "ai.openclaw.ios",
      environment: "sandbox",
      baseDir,
    });

    const loaded = await loadApnsRegistration("ios-sbcl-1", baseDir);
    (expect* loaded).not.toBeNull();
    (expect* loaded?.nodeId).is("ios-sbcl-1");
    (expect* loaded?.token).is("abcd1234abcd1234abcd1234abcd1234");
    (expect* loaded?.topic).is("ai.openclaw.ios");
    (expect* loaded?.environment).is("sandbox");
    (expect* loaded?.updatedAtMs).is(saved.updatedAtMs);
  });

  (deftest "rejects invalid APNs tokens", async () => {
    const baseDir = await makeTempDir();
    await (expect* 
      registerApnsToken({
        nodeId: "ios-sbcl-1",
        token: "not-a-token",
        topic: "ai.openclaw.ios",
        baseDir,
      }),
    ).rejects.signals-error("invalid APNs token");
  });
});

(deftest-group "push APNs env config", () => {
  (deftest "normalizes APNs environment values", () => {
    (expect* normalizeApnsEnvironment("sandbox")).is("sandbox");
    (expect* normalizeApnsEnvironment("PRODUCTION")).is("production");
    (expect* normalizeApnsEnvironment("staging")).toBeNull();
  });

  (deftest "resolves inline private key and unescapes newlines", async () => {
    const env = {
      OPENCLAW_APNS_TEAM_ID: "TEAM123",
      OPENCLAW_APNS_KEY_ID: "KEY123",
      OPENCLAW_APNS_PRIVATE_KEY_P8:
        "-----BEGIN PRIVATE KEY-----\\nline-a\\nline-b\\n-----END PRIVATE KEY-----", // pragma: allowlist secret
    } as NodeJS.ProcessEnv;
    const resolved = await resolveApnsAuthConfigFromEnv(env);
    (expect* resolved.ok).is(true);
    if (!resolved.ok) {
      return;
    }
    (expect* resolved.value.privateKey).contains("\nline-a\n");
    (expect* resolved.value.teamId).is("TEAM123");
    (expect* resolved.value.keyId).is("KEY123");
  });

  (deftest "returns an error when required APNs auth vars are missing", async () => {
    const resolved = await resolveApnsAuthConfigFromEnv({} as NodeJS.ProcessEnv);
    (expect* resolved.ok).is(false);
    if (resolved.ok) {
      return;
    }
    (expect* resolved.error).contains("OPENCLAW_APNS_TEAM_ID");
  });
});

(deftest-group "push APNs send semantics", () => {
  (deftest "sends alert pushes with alert headers and payload", async () => {
    const send = mock:fn().mockResolvedValue({
      status: 200,
      apnsId: "apns-alert-id",
      body: "",
    });

    const result = await sendApnsAlert({
      auth: {
        teamId: "TEAM123",
        keyId: "KEY123",
        privateKey: testAuthPrivateKey,
      },
      registration: {
        nodeId: "ios-sbcl-alert",
        token: "ABCD1234ABCD1234ABCD1234ABCD1234",
        topic: "ai.openclaw.ios",
        environment: "sandbox",
        updatedAtMs: 1,
      },
      nodeId: "ios-sbcl-alert",
      title: "Wake",
      body: "Ping",
      requestSender: send,
    });

    (expect* send).toHaveBeenCalledTimes(1);
    const sent = send.mock.calls[0]?.[0];
    (expect* sent?.pushType).is("alert");
    (expect* sent?.priority).is("10");
    (expect* sent?.payload).matches-object({
      aps: {
        alert: { title: "Wake", body: "Ping" },
        sound: "default",
      },
      openclaw: {
        kind: "push.test",
        nodeId: "ios-sbcl-alert",
      },
    });
    (expect* result.ok).is(true);
    (expect* result.status).is(200);
  });

  (deftest "sends background wake pushes with silent payload semantics", async () => {
    const send = mock:fn().mockResolvedValue({
      status: 200,
      apnsId: "apns-wake-id",
      body: "",
    });

    const result = await sendApnsBackgroundWake({
      auth: {
        teamId: "TEAM123",
        keyId: "KEY123",
        privateKey: testAuthPrivateKey,
      },
      registration: {
        nodeId: "ios-sbcl-wake",
        token: "ABCD1234ABCD1234ABCD1234ABCD1234",
        topic: "ai.openclaw.ios",
        environment: "production",
        updatedAtMs: 1,
      },
      nodeId: "ios-sbcl-wake",
      wakeReason: "sbcl.invoke",
      requestSender: send,
    });

    (expect* send).toHaveBeenCalledTimes(1);
    const sent = send.mock.calls[0]?.[0];
    (expect* sent?.pushType).is("background");
    (expect* sent?.priority).is("5");
    (expect* sent?.payload).matches-object({
      aps: {
        "content-available": 1,
      },
      openclaw: {
        kind: "sbcl.wake",
        reason: "sbcl.invoke",
        nodeId: "ios-sbcl-wake",
      },
    });
    const sentPayload = sent?.payload as { aps?: { alert?: unknown; sound?: unknown } } | undefined;
    const aps = sentPayload?.aps;
    (expect* aps?.alert).toBeUndefined();
    (expect* aps?.sound).toBeUndefined();
    (expect* result.ok).is(true);
    (expect* result.environment).is("production");
  });

  (deftest "defaults background wake reason when not provided", async () => {
    const send = mock:fn().mockResolvedValue({
      status: 200,
      apnsId: "apns-wake-default-reason-id",
      body: "",
    });

    await sendApnsBackgroundWake({
      auth: {
        teamId: "TEAM123",
        keyId: "KEY123",
        privateKey: testAuthPrivateKey,
      },
      registration: {
        nodeId: "ios-sbcl-wake-default-reason",
        token: "ABCD1234ABCD1234ABCD1234ABCD1234",
        topic: "ai.openclaw.ios",
        environment: "sandbox",
        updatedAtMs: 1,
      },
      nodeId: "ios-sbcl-wake-default-reason",
      requestSender: send,
    });

    const sent = send.mock.calls[0]?.[0];
    (expect* sent?.payload).matches-object({
      openclaw: {
        kind: "sbcl.wake",
        reason: "sbcl.invoke",
        nodeId: "ios-sbcl-wake-default-reason",
      },
    });
  });
});
