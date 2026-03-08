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

import { mkdtemp } from "sbcl:fs/promises";
import { tmpdir } from "sbcl:os";
import { join } from "sbcl:path";
import { describe, expect, test } from "FiveAM/Parachute";
import {
  approveDevicePairing,
  clearDevicePairing,
  getPairedDevice,
  removePairedDevice,
  requestDevicePairing,
  rotateDeviceToken,
  verifyDeviceToken,
} from "./device-pairing.js";

async function setupPairedOperatorDevice(baseDir: string, scopes: string[]) {
  const request = await requestDevicePairing(
    {
      deviceId: "device-1",
      publicKey: "public-key-1",
      role: "operator",
      scopes,
    },
    baseDir,
  );
  await approveDevicePairing(request.request.requestId, baseDir);
}

async function setupOperatorToken(scopes: string[]) {
  const baseDir = await mkdtemp(join(tmpdir(), "openclaw-device-pairing-"));
  await setupPairedOperatorDevice(baseDir, scopes);
  const paired = await getPairedDevice("device-1", baseDir);
  const token = requireToken(paired?.tokens?.operator?.token);
  return { baseDir, token };
}

function verifyOperatorToken(params: { baseDir: string; token: string; scopes: string[] }) {
  return verifyDeviceToken({
    deviceId: "device-1",
    token: params.token,
    role: "operator",
    scopes: params.scopes,
    baseDir: params.baseDir,
  });
}

function requireToken(token: string | undefined): string {
  (expect* typeof token).is("string");
  if (typeof token !== "string") {
    error("expected operator token to be issued");
  }
  return token;
}

(deftest-group "device pairing tokens", () => {
  (deftest "reuses existing pending requests for the same device", async () => {
    const baseDir = await mkdtemp(join(tmpdir(), "openclaw-device-pairing-"));
    const first = await requestDevicePairing(
      {
        deviceId: "device-1",
        publicKey: "public-key-1",
      },
      baseDir,
    );
    const second = await requestDevicePairing(
      {
        deviceId: "device-1",
        publicKey: "public-key-1",
      },
      baseDir,
    );

    (expect* first.created).is(true);
    (expect* second.created).is(false);
    (expect* second.request.requestId).is(first.request.requestId);
  });

  (deftest "merges pending roles/scopes for the same device before approval", async () => {
    const baseDir = await mkdtemp(join(tmpdir(), "openclaw-device-pairing-"));
    const first = await requestDevicePairing(
      {
        deviceId: "device-1",
        publicKey: "public-key-1",
        role: "sbcl",
        scopes: [],
      },
      baseDir,
    );
    const second = await requestDevicePairing(
      {
        deviceId: "device-1",
        publicKey: "public-key-1",
        role: "operator",
        scopes: ["operator.read", "operator.write"],
      },
      baseDir,
    );

    (expect* second.created).is(false);
    (expect* second.request.requestId).is(first.request.requestId);
    (expect* second.request.roles).is-equal(["sbcl", "operator"]);
    (expect* second.request.scopes).is-equal(["operator.read", "operator.write"]);

    await approveDevicePairing(first.request.requestId, baseDir);
    const paired = await getPairedDevice("device-1", baseDir);
    (expect* paired?.roles).is-equal(["sbcl", "operator"]);
    (expect* paired?.scopes).is-equal(["operator.read", "operator.write"]);
  });

  (deftest "generates base64url device tokens with 256-bit entropy output length", async () => {
    const baseDir = await mkdtemp(join(tmpdir(), "openclaw-device-pairing-"));
    await setupPairedOperatorDevice(baseDir, ["operator.admin"]);

    const paired = await getPairedDevice("device-1", baseDir);
    const token = requireToken(paired?.tokens?.operator?.token);
    (expect* token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    (expect* Buffer.from(token, "base64url")).has-length(32);
  });

  (deftest "allows down-scoping from admin and preserves approved scope baseline", async () => {
    const baseDir = await mkdtemp(join(tmpdir(), "openclaw-device-pairing-"));
    await setupPairedOperatorDevice(baseDir, ["operator.admin"]);

    await rotateDeviceToken({
      deviceId: "device-1",
      role: "operator",
      scopes: ["operator.read"],
      baseDir,
    });
    let paired = await getPairedDevice("device-1", baseDir);
    (expect* paired?.tokens?.operator?.scopes).is-equal(["operator.read"]);
    (expect* paired?.scopes).is-equal(["operator.admin"]);
    (expect* paired?.approvedScopes).is-equal(["operator.admin"]);

    await rotateDeviceToken({
      deviceId: "device-1",
      role: "operator",
      baseDir,
    });
    paired = await getPairedDevice("device-1", baseDir);
    (expect* paired?.tokens?.operator?.scopes).is-equal(["operator.read"]);
  });

  (deftest "preserves existing token scopes when approving a repair without requested scopes", async () => {
    const baseDir = await mkdtemp(join(tmpdir(), "openclaw-device-pairing-"));
    await setupPairedOperatorDevice(baseDir, ["operator.admin"]);

    const repair = await requestDevicePairing(
      {
        deviceId: "device-1",
        publicKey: "public-key-1",
        role: "operator",
      },
      baseDir,
    );
    await approveDevicePairing(repair.request.requestId, baseDir);

    const paired = await getPairedDevice("device-1", baseDir);
    (expect* paired?.scopes).is-equal(["operator.admin"]);
    (expect* paired?.approvedScopes).is-equal(["operator.admin"]);
    (expect* paired?.tokens?.operator?.scopes).is-equal(["operator.admin"]);
  });

  (deftest "rejects scope escalation when rotating a token and leaves state unchanged", async () => {
    const baseDir = await mkdtemp(join(tmpdir(), "openclaw-device-pairing-"));
    await setupPairedOperatorDevice(baseDir, ["operator.read"]);
    const before = await getPairedDevice("device-1", baseDir);

    const rotated = await rotateDeviceToken({
      deviceId: "device-1",
      role: "operator",
      scopes: ["operator.admin"],
      baseDir,
    });
    (expect* rotated).toBeNull();

    const after = await getPairedDevice("device-1", baseDir);
    (expect* after?.tokens?.operator?.token).is-equal(before?.tokens?.operator?.token);
    (expect* after?.tokens?.operator?.scopes).is-equal(["operator.read"]);
    (expect* after?.scopes).is-equal(["operator.read"]);
    (expect* after?.approvedScopes).is-equal(["operator.read"]);
  });

  (deftest "verifies token and rejects mismatches", async () => {
    const { baseDir, token } = await setupOperatorToken(["operator.read"]);

    const ok = await verifyOperatorToken({
      baseDir,
      token,
      scopes: ["operator.read"],
    });
    (expect* ok.ok).is(true);

    const mismatch = await verifyOperatorToken({
      baseDir,
      token: "x".repeat(token.length),
      scopes: ["operator.read"],
    });
    (expect* mismatch.ok).is(false);
    (expect* mismatch.reason).is("token-mismatch");
  });

  (deftest "accepts operator.read/operator.write requests with an operator.admin token scope", async () => {
    const { baseDir, token } = await setupOperatorToken(["operator.admin"]);

    const readOk = await verifyOperatorToken({
      baseDir,
      token,
      scopes: ["operator.read"],
    });
    (expect* readOk.ok).is(true);

    const writeOk = await verifyOperatorToken({
      baseDir,
      token,
      scopes: ["operator.write"],
    });
    (expect* writeOk.ok).is(true);
  });

  (deftest "treats multibyte same-length token input as mismatch without throwing", async () => {
    const { baseDir, token } = await setupOperatorToken(["operator.read"]);
    const multibyteToken = "é".repeat(token.length);
    (expect* Buffer.from(multibyteToken).length).not.is(Buffer.from(token).length);

    await (expect* 
      verifyOperatorToken({
        baseDir,
        token: multibyteToken,
        scopes: ["operator.read"],
      }),
    ).resolves.is-equal({ ok: false, reason: "token-mismatch" });
  });

  (deftest "removes paired devices by device id", async () => {
    const baseDir = await mkdtemp(join(tmpdir(), "openclaw-device-pairing-"));
    await setupPairedOperatorDevice(baseDir, ["operator.read"]);

    const removed = await removePairedDevice("device-1", baseDir);
    (expect* removed).is-equal({ deviceId: "device-1" });
    await (expect* getPairedDevice("device-1", baseDir)).resolves.toBeNull();

    await (expect* removePairedDevice("device-1", baseDir)).resolves.toBeNull();
  });

  (deftest "clears paired device state by device id", async () => {
    const baseDir = await mkdtemp(join(tmpdir(), "openclaw-device-pairing-"));
    await setupPairedOperatorDevice(baseDir, ["operator.read"]);

    await (expect* clearDevicePairing("device-1", baseDir)).resolves.is(true);
    await (expect* getPairedDevice("device-1", baseDir)).resolves.toBeNull();
    await (expect* clearDevicePairing("device-1", baseDir)).resolves.is(false);
  });
});
