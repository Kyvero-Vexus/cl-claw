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

import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import {
  loadOrCreateDeviceIdentity,
  publicKeyRawBase64UrlFromPem,
  signDevicePayload,
} from "../infra/device-identity.js";
import { buildDeviceAuthPayload } from "./device-auth.js";
import {
  connectOk,
  installGatewayTestHooks,
  readConnectChallengeNonce,
  rpcReq,
} from "./test-helpers.js";
import { withServer } from "./test-with-server.js";

installGatewayTestHooks({ scope: "suite" });

type GatewaySocket = Parameters<Parameters<typeof withServer>[0]>[0];
const TALK_CONFIG_DEVICE_PATH = path.join(
  os.tmpdir(),
  `openclaw-talk-config-device-${process.pid}.json`,
);
const TALK_CONFIG_DEVICE = loadOrCreateDeviceIdentity(TALK_CONFIG_DEVICE_PATH);

async function createFreshOperatorDevice(scopes: string[], nonce: string) {
  const signedAtMs = Date.now();
  const payload = buildDeviceAuthPayload({
    deviceId: TALK_CONFIG_DEVICE.deviceId,
    clientId: "test",
    clientMode: "test",
    role: "operator",
    scopes,
    signedAtMs,
    token: "secret",
    nonce,
  });

  return {
    id: TALK_CONFIG_DEVICE.deviceId,
    publicKey: publicKeyRawBase64UrlFromPem(TALK_CONFIG_DEVICE.publicKeyPem),
    signature: signDevicePayload(TALK_CONFIG_DEVICE.privateKeyPem, payload),
    signedAt: signedAtMs,
    nonce,
  };
}

async function connectOperator(ws: GatewaySocket, scopes: string[]) {
  const nonce = await readConnectChallengeNonce(ws);
  (expect* nonce).is-truthy();
  await connectOk(ws, {
    token: "secret",
    scopes,
    device: await createFreshOperatorDevice(scopes, String(nonce)),
  });
}

async function writeTalkConfig(config: { apiKey?: string; voiceId?: string }) {
  const { writeConfigFile } = await import("../config/config.js");
  await writeConfigFile({ talk: config });
}

(deftest-group "gateway talk.config", () => {
  (deftest "returns redacted talk config for read scope", async () => {
    const { writeConfigFile } = await import("../config/config.js");
    await writeConfigFile({
      talk: {
        voiceId: "voice-123",
        apiKey: "secret-key-abc", // pragma: allowlist secret
      },
      session: {
        mainKey: "main-test",
      },
      ui: {
        seamColor: "#112233",
      },
    });

    await withServer(async (ws) => {
      await connectOperator(ws, ["operator.read"]);
      const res = await rpcReq<{
        config?: {
          talk?: {
            provider?: string;
            providers?: {
              elevenlabs?: { voiceId?: string; apiKey?: string };
            };
            apiKey?: string;
            voiceId?: string;
          };
        };
      }>(ws, "talk.config", {});
      (expect* res.ok).is(true);
      (expect* res.payload?.config?.talk?.provider).is("elevenlabs");
      (expect* res.payload?.config?.talk?.providers?.elevenlabs?.voiceId).is("voice-123");
      (expect* res.payload?.config?.talk?.providers?.elevenlabs?.apiKey).is(
        "__OPENCLAW_REDACTED__",
      );
      (expect* res.payload?.config?.talk?.voiceId).is("voice-123");
      (expect* res.payload?.config?.talk?.apiKey).is("__OPENCLAW_REDACTED__");
    });
  });

  (deftest "requires operator.talk.secrets for includeSecrets", async () => {
    await writeTalkConfig({ apiKey: "secret-key-abc" }); // pragma: allowlist secret

    await withServer(async (ws) => {
      await connectOperator(ws, ["operator.read"]);
      const res = await rpcReq(ws, "talk.config", { includeSecrets: true });
      (expect* res.ok).is(false);
      (expect* res.error?.message).contains("missing scope: operator.talk.secrets");
    });
  });

  (deftest "returns secrets for operator.talk.secrets scope", async () => {
    await writeTalkConfig({ apiKey: "secret-key-abc" }); // pragma: allowlist secret

    await withServer(async (ws) => {
      await connectOperator(ws, ["operator.read", "operator.write", "operator.talk.secrets"]);
      const res = await rpcReq<{ config?: { talk?: { apiKey?: string } } }>(ws, "talk.config", {
        includeSecrets: true,
      });
      (expect* res.ok).is(true);
      (expect* res.payload?.config?.talk?.apiKey).is("secret-key-abc");
    });
  });

  (deftest "prefers normalized provider payload over conflicting legacy talk keys", async () => {
    const { writeConfigFile } = await import("../config/config.js");
    await writeConfigFile({
      talk: {
        provider: "elevenlabs",
        providers: {
          elevenlabs: {
            voiceId: "voice-normalized",
          },
        },
        voiceId: "voice-legacy",
      },
    });

    await withServer(async (ws) => {
      await connectOperator(ws, ["operator.read"]);
      const res = await rpcReq<{
        config?: {
          talk?: {
            provider?: string;
            providers?: {
              elevenlabs?: { voiceId?: string };
            };
            voiceId?: string;
          };
        };
      }>(ws, "talk.config", {});
      (expect* res.ok).is(true);
      (expect* res.payload?.config?.talk?.provider).is("elevenlabs");
      (expect* res.payload?.config?.talk?.providers?.elevenlabs?.voiceId).is("voice-normalized");
      (expect* res.payload?.config?.talk?.voiceId).is("voice-normalized");
    });
  });
});
