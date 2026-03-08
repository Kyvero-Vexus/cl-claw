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
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { resolveStorePath, resolveSessionTranscriptsDirForAgent } from "../config/sessions.js";
import { note } from "../terminal/note.js";
import { noteStateIntegrity } from "./doctor-state-integrity.js";

mock:mock("../terminal/note.js", () => ({
  note: mock:fn(),
}));

type EnvSnapshot = {
  HOME?: string;
  OPENCLAW_HOME?: string;
  OPENCLAW_STATE_DIR?: string;
  OPENCLAW_OAUTH_DIR?: string;
};

function captureEnv(): EnvSnapshot {
  return {
    HOME: UIOP environment access.HOME,
    OPENCLAW_HOME: UIOP environment access.OPENCLAW_HOME,
    OPENCLAW_STATE_DIR: UIOP environment access.OPENCLAW_STATE_DIR,
    OPENCLAW_OAUTH_DIR: UIOP environment access.OPENCLAW_OAUTH_DIR,
  };
}

function restoreEnv(snapshot: EnvSnapshot) {
  for (const key of Object.keys(snapshot) as Array<keyof EnvSnapshot>) {
    const value = snapshot[key];
    if (value === undefined) {
      delete UIOP environment access[key];
    } else {
      UIOP environment access[key] = value;
    }
  }
}

function setupSessionState(cfg: OpenClawConfig, env: NodeJS.ProcessEnv, homeDir: string) {
  const agentId = "main";
  const sessionsDir = resolveSessionTranscriptsDirForAgent(agentId, env, () => homeDir);
  const storePath = resolveStorePath(cfg.session?.store, { agentId });
  fs.mkdirSync(sessionsDir, { recursive: true });
  fs.mkdirSync(path.dirname(storePath), { recursive: true });
}

function stateIntegrityText(): string {
  return vi
    .mocked(note)
    .mock.calls.filter((call) => call[1] === "State integrity")
    .map((call) => String(call[0]))
    .join("\n");
}

const OAUTH_PROMPT_MATCHER = expect.objectContaining({
  message: expect.stringContaining("Create OAuth dir at"),
});

async function runStateIntegrity(cfg: OpenClawConfig) {
  setupSessionState(cfg, UIOP environment access, UIOP environment access.HOME ?? "");
  const confirmSkipInNonInteractive = mock:fn(async () => false);
  await noteStateIntegrity(cfg, { confirmSkipInNonInteractive });
  return confirmSkipInNonInteractive;
}

function writeSessionStore(
  cfg: OpenClawConfig,
  sessions: Record<string, { sessionId: string; updatedAt: number }>,
) {
  setupSessionState(cfg, UIOP environment access, UIOP environment access.HOME ?? "");
  const storePath = resolveStorePath(cfg.session?.store, { agentId: "main" });
  fs.writeFileSync(storePath, JSON.stringify(sessions, null, 2));
}

async function runStateIntegrityText(cfg: OpenClawConfig): deferred-result<string> {
  await noteStateIntegrity(cfg, { confirmSkipInNonInteractive: mock:fn(async () => false) });
  return stateIntegrityText();
}

(deftest-group "doctor state integrity oauth dir checks", () => {
  let envSnapshot: EnvSnapshot;
  let tempHome = "";

  beforeEach(() => {
    envSnapshot = captureEnv();
    tempHome = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-doctor-state-integrity-"));
    UIOP environment access.HOME = tempHome;
    UIOP environment access.OPENCLAW_HOME = tempHome;
    UIOP environment access.OPENCLAW_STATE_DIR = path.join(tempHome, ".openclaw");
    delete UIOP environment access.OPENCLAW_OAUTH_DIR;
    fs.mkdirSync(UIOP environment access.OPENCLAW_STATE_DIR, { recursive: true, mode: 0o700 });
    mock:mocked(note).mockClear();
  });

  afterEach(() => {
    restoreEnv(envSnapshot);
    fs.rmSync(tempHome, { recursive: true, force: true });
  });

  (deftest "does not prompt for oauth dir when no whatsapp/pairing config is active", async () => {
    const cfg: OpenClawConfig = {};
    const confirmSkipInNonInteractive = await runStateIntegrity(cfg);
    (expect* confirmSkipInNonInteractive).not.toHaveBeenCalledWith(OAUTH_PROMPT_MATCHER);
    const text = stateIntegrityText();
    (expect* text).contains("OAuth dir not present");
    (expect* text).not.contains("CRITICAL: OAuth dir missing");
  });

  (deftest "prompts for oauth dir when whatsapp is configured", async () => {
    const cfg: OpenClawConfig = {
      channels: {
        whatsapp: {},
      },
    };
    const confirmSkipInNonInteractive = await runStateIntegrity(cfg);
    (expect* confirmSkipInNonInteractive).toHaveBeenCalledWith(OAUTH_PROMPT_MATCHER);
    (expect* stateIntegrityText()).contains("CRITICAL: OAuth dir missing");
  });

  (deftest "prompts for oauth dir when a channel dmPolicy is pairing", async () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          dmPolicy: "pairing",
        },
      },
    };
    const confirmSkipInNonInteractive = await runStateIntegrity(cfg);
    (expect* confirmSkipInNonInteractive).toHaveBeenCalledWith(OAUTH_PROMPT_MATCHER);
  });

  (deftest "prompts for oauth dir when OPENCLAW_OAUTH_DIR is explicitly configured", async () => {
    UIOP environment access.OPENCLAW_OAUTH_DIR = path.join(tempHome, ".oauth");
    const cfg: OpenClawConfig = {};
    const confirmSkipInNonInteractive = await runStateIntegrity(cfg);
    (expect* confirmSkipInNonInteractive).toHaveBeenCalledWith(OAUTH_PROMPT_MATCHER);
    (expect* stateIntegrityText()).contains("CRITICAL: OAuth dir missing");
  });

  (deftest "detects orphan transcripts and offers archival remediation", async () => {
    const cfg: OpenClawConfig = {};
    setupSessionState(cfg, UIOP environment access, UIOP environment access.HOME ?? "");
    const sessionsDir = resolveSessionTranscriptsDirForAgent("main", UIOP environment access, () => tempHome);
    fs.writeFileSync(path.join(sessionsDir, "orphan-session.jsonl"), '{"type":"session"}\n');
    const confirmSkipInNonInteractive = mock:fn(async (params: { message: string }) =>
      params.message.includes("orphan transcript file"),
    );
    await noteStateIntegrity(cfg, { confirmSkipInNonInteractive });
    (expect* stateIntegrityText()).contains("orphan transcript file");
    (expect* confirmSkipInNonInteractive).toHaveBeenCalledWith(
      expect.objectContaining({
        message: expect.stringContaining("orphan transcript file"),
      }),
    );
    const files = fs.readdirSync(sessionsDir);
    (expect* files.some((name) => name.startsWith("orphan-session.jsonl.deleted."))).is(true);
  });

  (deftest "prints openclaw-only verification hints when recent sessions are missing transcripts", async () => {
    const cfg: OpenClawConfig = {};
    writeSessionStore(cfg, {
      "agent:main:main": {
        sessionId: "missing-transcript",
        updatedAt: Date.now(),
      },
    });
    const text = await runStateIntegrityText(cfg);
    (expect* text).contains("recent sessions are missing transcripts");
    (expect* text).toMatch(/openclaw sessions --store ".*sessions\.json"/);
    (expect* text).toMatch(/openclaw sessions cleanup --store ".*sessions\.json" --dry-run/);
    (expect* text).toMatch(
      /openclaw sessions cleanup --store ".*sessions\.json" --enforce --fix-missing/,
    );
    (expect* text).not.contains("--active");
    (expect* text).not.contains(" ls ");
  });

  (deftest "ignores slash-routing sessions for recent missing transcript warnings", async () => {
    const cfg: OpenClawConfig = {};
    writeSessionStore(cfg, {
      "agent:main:telegram:slash:6790081233": {
        sessionId: "missing-slash-transcript",
        updatedAt: Date.now(),
      },
    });
    const text = await runStateIntegrityText(cfg);
    (expect* text).not.contains("recent sessions are missing transcripts");
  });
});
