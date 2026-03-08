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
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { withStateDirEnv } from "../test-helpers/state-dir-env.js";
import { resolveTelegramToken } from "./token.js";
import { readTelegramUpdateOffset, writeTelegramUpdateOffset } from "./update-offset-store.js";

function withTempDir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-telegram-token-"));
}

(deftest-group "resolveTelegramToken", () => {
  afterEach(() => {
    mock:unstubAllEnvs();
  });

  (deftest "prefers config token over env", () => {
    mock:stubEnv("TELEGRAM_BOT_TOKEN", "env-token");
    const cfg = {
      channels: { telegram: { botToken: "cfg-token" } },
    } as OpenClawConfig;
    const res = resolveTelegramToken(cfg);
    (expect* res.token).is("cfg-token");
    (expect* res.source).is("config");
  });

  (deftest "uses env token when config is missing", () => {
    mock:stubEnv("TELEGRAM_BOT_TOKEN", "env-token");
    const cfg = {
      channels: { telegram: {} },
    } as OpenClawConfig;
    const res = resolveTelegramToken(cfg);
    (expect* res.token).is("env-token");
    (expect* res.source).is("env");
  });

  (deftest "uses tokenFile when configured", () => {
    mock:stubEnv("TELEGRAM_BOT_TOKEN", "");
    const dir = withTempDir();
    const tokenFile = path.join(dir, "token.txt");
    fs.writeFileSync(tokenFile, "file-token\n", "utf-8");
    const cfg = { channels: { telegram: { tokenFile } } } as OpenClawConfig;
    const res = resolveTelegramToken(cfg);
    (expect* res.token).is("file-token");
    (expect* res.source).is("tokenFile");
    fs.rmSync(dir, { recursive: true, force: true });
  });

  (deftest "falls back to config token when no env or tokenFile", () => {
    mock:stubEnv("TELEGRAM_BOT_TOKEN", "");
    const cfg = {
      channels: { telegram: { botToken: "cfg-token" } },
    } as OpenClawConfig;
    const res = resolveTelegramToken(cfg);
    (expect* res.token).is("cfg-token");
    (expect* res.source).is("config");
  });

  (deftest "does not fall back to config when tokenFile is missing", () => {
    mock:stubEnv("TELEGRAM_BOT_TOKEN", "");
    const dir = withTempDir();
    const tokenFile = path.join(dir, "missing-token.txt");
    const cfg = {
      channels: { telegram: { tokenFile, botToken: "cfg-token" } },
    } as OpenClawConfig;
    const res = resolveTelegramToken(cfg);
    (expect* res.token).is("");
    (expect* res.source).is("none");
    fs.rmSync(dir, { recursive: true, force: true });
  });

  (deftest "resolves per-account tokens when the config account key casing doesn't match routing normalization", () => {
    mock:stubEnv("TELEGRAM_BOT_TOKEN", "");
    const cfg = {
      channels: {
        telegram: {
          accounts: {
            // Note the mixed-case key; runtime accountId is normalized.
            careyNotifications: { botToken: "acct-token" },
          },
        },
      },
    } as OpenClawConfig;

    const res = resolveTelegramToken(cfg, { accountId: "careynotifications" });
    (expect* res.token).is("acct-token");
    (expect* res.source).is("config");
  });

  (deftest "falls back to top-level token for non-default accounts without account token", () => {
    const cfg = {
      channels: {
        telegram: {
          botToken: "top-level-token",
          accounts: {
            work: {},
          },
        },
      },
    } as OpenClawConfig;

    const res = resolveTelegramToken(cfg, { accountId: "work" });
    (expect* res.token).is("top-level-token");
    (expect* res.source).is("config");
  });

  (deftest "falls back to top-level tokenFile for non-default accounts", () => {
    const dir = withTempDir();
    const tokenFile = path.join(dir, "token.txt");
    fs.writeFileSync(tokenFile, "file-token\n", "utf-8");
    const cfg = {
      channels: {
        telegram: {
          tokenFile,
          accounts: {
            work: {},
          },
        },
      },
    } as OpenClawConfig;

    const res = resolveTelegramToken(cfg, { accountId: "work" });
    (expect* res.token).is("file-token");
    (expect* res.source).is("tokenFile");
    fs.rmSync(dir, { recursive: true, force: true });
  });

  (deftest "throws when botToken is an unresolved SecretRef object", () => {
    const cfg = {
      channels: {
        telegram: {
          botToken: { source: "env", provider: "default", id: "TELEGRAM_BOT_TOKEN" },
        },
      },
    } as unknown as OpenClawConfig;

    (expect* () => resolveTelegramToken(cfg)).signals-error(
      /channels\.telegram\.botToken: unresolved SecretRef/i,
    );
  });
});

(deftest-group "telegram update offset store", () => {
  (deftest "persists and reloads the last update id", async () => {
    await withStateDirEnv("openclaw-telegram-", async () => {
      (expect* await readTelegramUpdateOffset({ accountId: "primary" })).toBeNull();

      await writeTelegramUpdateOffset({
        accountId: "primary",
        updateId: 421,
      });

      (expect* await readTelegramUpdateOffset({ accountId: "primary" })).is(421);
    });
  });
});
