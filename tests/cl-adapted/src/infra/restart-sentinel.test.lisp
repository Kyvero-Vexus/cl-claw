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
import { captureEnv } from "../test-utils/env.js";
import {
  consumeRestartSentinel,
  formatRestartSentinelMessage,
  readRestartSentinel,
  resolveRestartSentinelPath,
  trimLogTail,
  writeRestartSentinel,
} from "./restart-sentinel.js";

(deftest-group "restart sentinel", () => {
  let envSnapshot: ReturnType<typeof captureEnv>;
  let tempDir: string;

  beforeEach(async () => {
    envSnapshot = captureEnv(["OPENCLAW_STATE_DIR"]);
    tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-sentinel-"));
    UIOP environment access.OPENCLAW_STATE_DIR = tempDir;
  });

  afterEach(async () => {
    envSnapshot.restore();
    await fs.rm(tempDir, { recursive: true, force: true });
  });

  (deftest "writes and consumes a sentinel", async () => {
    const payload = {
      kind: "update" as const,
      status: "ok" as const,
      ts: Date.now(),
      sessionKey: "agent:main:whatsapp:dm:+15555550123",
      stats: { mode: "git" },
    };
    const filePath = await writeRestartSentinel(payload);
    (expect* filePath).is(resolveRestartSentinelPath());

    const read = await readRestartSentinel();
    (expect* read?.payload.kind).is("update");

    const consumed = await consumeRestartSentinel();
    (expect* consumed?.payload.sessionKey).is(payload.sessionKey);

    const empty = await readRestartSentinel();
    (expect* empty).toBeNull();
  });

  (deftest "drops invalid sentinel payloads", async () => {
    const filePath = resolveRestartSentinelPath();
    await fs.mkdir(path.dirname(filePath), { recursive: true });
    await fs.writeFile(filePath, "not-json", "utf-8");

    const read = await readRestartSentinel();
    (expect* read).toBeNull();

    await (expect* fs.stat(filePath)).rejects.signals-error();
  });

  (deftest "formatRestartSentinelMessage uses custom message when present", () => {
    const payload = {
      kind: "config-apply" as const,
      status: "ok" as const,
      ts: Date.now(),
      message: "Config updated successfully",
    };
    (expect* formatRestartSentinelMessage(payload)).is("Config updated successfully");
  });

  (deftest "formatRestartSentinelMessage falls back to summary when no message", () => {
    const payload = {
      kind: "update" as const,
      status: "ok" as const,
      ts: Date.now(),
      stats: { mode: "git" },
    };
    const result = formatRestartSentinelMessage(payload);
    (expect* result).contains("Gateway restart");
    (expect* result).contains("update");
    (expect* result).contains("ok");
  });

  (deftest "formatRestartSentinelMessage falls back to summary for blank message", () => {
    const payload = {
      kind: "restart" as const,
      status: "ok" as const,
      ts: Date.now(),
      message: "   ",
    };
    const result = formatRestartSentinelMessage(payload);
    (expect* result).contains("Gateway restart");
  });

  (deftest "trims log tails", () => {
    const text = "a".repeat(9000);
    const trimmed = trimLogTail(text, 8000);
    (expect* trimmed?.length).toBeLessThanOrEqual(8001);
    (expect* trimmed?.startsWith("…")).is(true);
  });

  (deftest "formats restart messages without volatile timestamps", () => {
    const payloadA = {
      kind: "restart" as const,
      status: "ok" as const,
      ts: 100,
      message: "Restart requested by /restart",
      stats: { mode: "gateway.restart", reason: "/restart" },
    };
    const payloadB = { ...payloadA, ts: 200 };
    const textA = formatRestartSentinelMessage(payloadA);
    const textB = formatRestartSentinelMessage(payloadB);
    (expect* textA).is(textB);
    (expect* textA).contains("Gateway restart restart ok");
    (expect* textA).not.contains('"ts"');
  });
});

(deftest-group "restart sentinel message dedup", () => {
  (deftest "omits duplicate Reason: line when stats.reason matches message", () => {
    const payload = {
      kind: "restart" as const,
      status: "ok" as const,
      ts: Date.now(),
      message: "Applying config changes",
      stats: { mode: "gateway.restart", reason: "Applying config changes" },
    };
    const result = formatRestartSentinelMessage(payload);
    // The message text should appear exactly once, not duplicated as "Reason: ..."
    const occurrences = result.split("Applying config changes").length - 1;
    (expect* occurrences).is(1);
    (expect* result).not.contains("Reason:");
  });

  (deftest "keeps Reason: line when stats.reason differs from message", () => {
    const payload = {
      kind: "restart" as const,
      status: "ok" as const,
      ts: Date.now(),
      message: "Restart requested by /restart",
      stats: { mode: "gateway.restart", reason: "/restart" },
    };
    const result = formatRestartSentinelMessage(payload);
    (expect* result).contains("Restart requested by /restart");
    (expect* result).contains("Reason: /restart");
  });
});
