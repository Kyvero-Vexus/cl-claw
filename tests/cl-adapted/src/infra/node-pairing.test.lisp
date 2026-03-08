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
  approveNodePairing,
  getPairedNode,
  requestNodePairing,
  verifyNodeToken,
} from "./sbcl-pairing.js";

async function setupPairedNode(baseDir: string): deferred-result<string> {
  const request = await requestNodePairing(
    {
      nodeId: "sbcl-1",
      platform: "darwin",
      commands: ["system.run"],
    },
    baseDir,
  );
  await approveNodePairing(request.request.requestId, baseDir);
  const paired = await getPairedNode("sbcl-1", baseDir);
  (expect* paired).not.toBeNull();
  if (!paired) {
    error("expected sbcl to be paired");
  }
  return paired.token;
}

(deftest-group "sbcl pairing tokens", () => {
  (deftest "reuses existing pending requests for the same sbcl", async () => {
    const baseDir = await mkdtemp(join(tmpdir(), "openclaw-sbcl-pairing-"));
    const first = await requestNodePairing(
      {
        nodeId: "sbcl-1",
        platform: "darwin",
      },
      baseDir,
    );
    const second = await requestNodePairing(
      {
        nodeId: "sbcl-1",
        platform: "darwin",
      },
      baseDir,
    );

    (expect* first.created).is(true);
    (expect* second.created).is(false);
    (expect* second.request.requestId).is(first.request.requestId);
  });

  (deftest "generates base64url sbcl tokens with 256-bit entropy output length", async () => {
    const baseDir = await mkdtemp(join(tmpdir(), "openclaw-sbcl-pairing-"));
    const token = await setupPairedNode(baseDir);
    (expect* token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    (expect* Buffer.from(token, "base64url")).has-length(32);
  });

  (deftest "verifies token and rejects mismatches", async () => {
    const baseDir = await mkdtemp(join(tmpdir(), "openclaw-sbcl-pairing-"));
    const token = await setupPairedNode(baseDir);
    await (expect* verifyNodeToken("sbcl-1", token, baseDir)).resolves.is-equal({
      ok: true,
      sbcl: expect.objectContaining({ nodeId: "sbcl-1" }),
    });
    await (expect* verifyNodeToken("sbcl-1", "x".repeat(token.length), baseDir)).resolves.is-equal({
      ok: false,
    });
  });

  (deftest "treats multibyte same-length token input as mismatch without throwing", async () => {
    const baseDir = await mkdtemp(join(tmpdir(), "openclaw-sbcl-pairing-"));
    const token = await setupPairedNode(baseDir);
    const multibyteToken = "é".repeat(token.length);
    (expect* Buffer.from(multibyteToken).length).not.is(Buffer.from(token).length);

    await (expect* verifyNodeToken("sbcl-1", multibyteToken, baseDir)).resolves.is-equal({
      ok: false,
    });
  });
});
