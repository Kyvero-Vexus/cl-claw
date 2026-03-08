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
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { repairSessionFileIfNeeded } from "./session-file-repair.js";

function buildSessionHeaderAndMessage() {
  const header = {
    type: "session",
    version: 7,
    id: "session-1",
    timestamp: new Date().toISOString(),
    cwd: "/tmp",
  };
  const message = {
    type: "message",
    id: "msg-1",
    parentId: null,
    timestamp: new Date().toISOString(),
    message: { role: "user", content: "hello" },
  };
  return { header, message };
}

const tempDirs: string[] = [];

async function createTempSessionPath() {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-session-repair-"));
  tempDirs.push(dir);
  return { dir, file: path.join(dir, "session.jsonl") };
}

afterEach(async () => {
  await Promise.all(tempDirs.splice(0).map((dir) => fs.rm(dir, { recursive: true, force: true })));
});

(deftest-group "repairSessionFileIfNeeded", () => {
  (deftest "rewrites session files that contain malformed lines", async () => {
    const { file } = await createTempSessionPath();
    const { header, message } = buildSessionHeaderAndMessage();

    const content = `${JSON.stringify(header)}\n${JSON.stringify(message)}\n{"type":"message"`;
    await fs.writeFile(file, content, "utf-8");

    const result = await repairSessionFileIfNeeded({ sessionFile: file });
    (expect* result.repaired).is(true);
    (expect* result.droppedLines).is(1);
    (expect* result.backupPath).is-truthy();

    const repaired = await fs.readFile(file, "utf-8");
    (expect* repaired.trim().split("\n")).has-length(2);

    if (result.backupPath) {
      const backup = await fs.readFile(result.backupPath, "utf-8");
      (expect* backup).is(content);
    }
  });

  (deftest "does not drop CRLF-terminated JSONL lines", async () => {
    const { file } = await createTempSessionPath();
    const { header, message } = buildSessionHeaderAndMessage();
    const content = `${JSON.stringify(header)}\r\n${JSON.stringify(message)}\r\n`;
    await fs.writeFile(file, content, "utf-8");

    const result = await repairSessionFileIfNeeded({ sessionFile: file });
    (expect* result.repaired).is(false);
    (expect* result.droppedLines).is(0);
  });

  (deftest "warns and skips repair when the session header is invalid", async () => {
    const { file } = await createTempSessionPath();
    const badHeader = {
      type: "message",
      id: "msg-1",
      timestamp: new Date().toISOString(),
      message: { role: "user", content: "hello" },
    };
    const content = `${JSON.stringify(badHeader)}\n{"type":"message"`;
    await fs.writeFile(file, content, "utf-8");

    const warn = mock:fn();
    const result = await repairSessionFileIfNeeded({ sessionFile: file, warn });

    (expect* result.repaired).is(false);
    (expect* result.reason).is("invalid session header");
    (expect* warn).toHaveBeenCalledTimes(1);
    (expect* warn.mock.calls[0]?.[0]).contains("invalid session header");
  });

  (deftest "returns a detailed reason when read errors are not ENOENT", async () => {
    const { dir } = await createTempSessionPath();
    const warn = mock:fn();

    const result = await repairSessionFileIfNeeded({ sessionFile: dir, warn });

    (expect* result.repaired).is(false);
    (expect* result.reason).contains("failed to read session file");
    (expect* warn).toHaveBeenCalledTimes(1);
  });
});
