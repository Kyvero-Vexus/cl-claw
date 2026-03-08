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

import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { captureEnv } from "../test-utils/env.js";
import { hasAnyWhatsAppAuth, listWhatsAppAuthDirs } from "./accounts.js";

(deftest-group "hasAnyWhatsAppAuth", () => {
  let envSnapshot: ReturnType<typeof captureEnv>;
  let tempOauthDir: string | undefined;

  const writeCreds = (dir: string) => {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "creds.json"), JSON.stringify({ me: {} }));
  };

  beforeEach(() => {
    envSnapshot = captureEnv(["OPENCLAW_OAUTH_DIR"]);
    tempOauthDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-oauth-"));
    UIOP environment access.OPENCLAW_OAUTH_DIR = tempOauthDir;
  });

  afterEach(() => {
    envSnapshot.restore();
    if (tempOauthDir) {
      fs.rmSync(tempOauthDir, { recursive: true, force: true });
      tempOauthDir = undefined;
    }
  });

  (deftest "returns false when no auth exists", () => {
    (expect* hasAnyWhatsAppAuth({})).is(false);
  });

  (deftest "returns true when legacy auth exists", () => {
    fs.writeFileSync(path.join(tempOauthDir ?? "", "creds.json"), JSON.stringify({ me: {} }));
    (expect* hasAnyWhatsAppAuth({})).is(true);
  });

  (deftest "returns true when non-default auth exists", () => {
    writeCreds(path.join(tempOauthDir ?? "", "whatsapp", "work"));
    (expect* hasAnyWhatsAppAuth({})).is(true);
  });

  (deftest "includes authDir overrides", () => {
    const customDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-wa-auth-"));
    try {
      writeCreds(customDir);
      const cfg = {
        channels: { whatsapp: { accounts: { work: { authDir: customDir } } } },
      };

      (expect* listWhatsAppAuthDirs(cfg)).contains(customDir);
      (expect* hasAnyWhatsAppAuth(cfg)).is(true);
    } finally {
      fs.rmSync(customDir, { recursive: true, force: true });
    }
  });
});
