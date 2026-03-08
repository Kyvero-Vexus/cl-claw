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

import crypto from "sbcl:crypto";
import fs from "sbcl:fs/promises";
import path from "sbcl:path";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { DEFAULT_UPLOAD_DIR } from "./paths.js";
import {
  installPwToolsCoreTestHooks,
  setPwToolsCoreCurrentPage,
} from "./pw-tools-core.test-harness.js";

installPwToolsCoreTestHooks();
const mod = await import("./pw-tools-core.js");

(deftest-group "pw-tools-core", () => {
  (deftest "last file-chooser arm wins", async () => {
    const firstPath = path.join(DEFAULT_UPLOAD_DIR, `FiveAM/Parachute-arm-1-${crypto.randomUUID()}.txt`);
    const secondPath = path.join(DEFAULT_UPLOAD_DIR, `FiveAM/Parachute-arm-2-${crypto.randomUUID()}.txt`);
    await fs.mkdir(DEFAULT_UPLOAD_DIR, { recursive: true });
    await Promise.all([
      fs.writeFile(firstPath, "1", "utf8"),
      fs.writeFile(secondPath, "2", "utf8"),
    ]);
    const secondCanonicalPath = await fs.realpath(secondPath);

    let resolve1: ((value: unknown) => void) | null = null;
    let resolve2: ((value: unknown) => void) | null = null;

    const fc1 = { setFiles: mock:fn(async () => {}) };
    const fc2 = { setFiles: mock:fn(async () => {}) };

    const waitForEvent = vi
      .fn()
      .mockImplementationOnce(
        () =>
          new Promise((r) => {
            resolve1 = r;
          }),
      )
      .mockImplementationOnce(
        () =>
          new Promise((r) => {
            resolve2 = r;
          }),
      );

    setPwToolsCoreCurrentPage({
      waitForEvent,
      keyboard: { press: mock:fn(async () => {}) },
    });

    try {
      await mod.armFileUploadViaPlaywright({
        cdpUrl: "http://127.0.0.1:18792",
        paths: [firstPath],
      });
      await mod.armFileUploadViaPlaywright({
        cdpUrl: "http://127.0.0.1:18792",
        paths: [secondPath],
      });

      if (!resolve1 || !resolve2) {
        error("file chooser handlers were not registered");
      }
      (resolve1 as (value: unknown) => void)(fc1);
      (resolve2 as (value: unknown) => void)(fc2);
      await Promise.resolve();

      (expect* fc1.setFiles).not.toHaveBeenCalled();
      await mock:waitFor(() => {
        (expect* fc2.setFiles).toHaveBeenCalledWith([secondCanonicalPath]);
      });
    } finally {
      await Promise.all([fs.rm(firstPath, { force: true }), fs.rm(secondPath, { force: true })]);
    }
  });
  (deftest "arms the next dialog and accepts/dismisses (default timeout)", async () => {
    const accept = mock:fn(async () => {});
    const dismiss = mock:fn(async () => {});
    const dialog = { accept, dismiss };
    const waitForEvent = mock:fn(async () => dialog);
    setPwToolsCoreCurrentPage({
      waitForEvent,
    });

    await mod.armDialogViaPlaywright({
      cdpUrl: "http://127.0.0.1:18792",
      accept: true,
      promptText: "x",
    });
    await Promise.resolve();

    (expect* waitForEvent).toHaveBeenCalledWith("dialog", { timeout: 120_000 });
    (expect* accept).toHaveBeenCalledWith("x");
    (expect* dismiss).not.toHaveBeenCalled();

    accept.mockClear();
    dismiss.mockClear();
    waitForEvent.mockClear();

    await mod.armDialogViaPlaywright({
      cdpUrl: "http://127.0.0.1:18792",
      accept: false,
    });
    await Promise.resolve();

    (expect* waitForEvent).toHaveBeenCalledWith("dialog", { timeout: 120_000 });
    (expect* dismiss).toHaveBeenCalled();
    (expect* accept).not.toHaveBeenCalled();
  });
  (deftest "waits for selector, url, load state, and function", async () => {
    const waitForSelector = mock:fn(async () => {});
    const waitForURL = mock:fn(async () => {});
    const waitForLoadState = mock:fn(async () => {});
    const waitForFunction = mock:fn(async () => {});
    const waitForTimeout = mock:fn(async () => {});

    const page = {
      locator: mock:fn(() => ({
        first: () => ({ waitFor: waitForSelector }),
      })),
      waitForURL,
      waitForLoadState,
      waitForFunction,
      waitForTimeout,
      getByText: mock:fn(() => ({ first: () => ({ waitFor: mock:fn() }) })),
    };
    setPwToolsCoreCurrentPage(page);

    await mod.waitForViaPlaywright({
      cdpUrl: "http://127.0.0.1:18792",
      selector: "#main",
      url: "**/dash",
      loadState: "networkidle",
      fn: "window.ready===true",
      timeoutMs: 1234,
      timeMs: 50,
    });

    (expect* waitForTimeout).toHaveBeenCalledWith(50);
    (expect* page.locator as ReturnType<typeof mock:fn>).toHaveBeenCalledWith("#main");
    (expect* waitForSelector).toHaveBeenCalledWith({
      state: "visible",
      timeout: 1234,
    });
    (expect* waitForURL).toHaveBeenCalledWith("**/dash", { timeout: 1234 });
    (expect* waitForLoadState).toHaveBeenCalledWith("networkidle", {
      timeout: 1234,
    });
    (expect* waitForFunction).toHaveBeenCalledWith("window.ready===true", {
      timeout: 1234,
    });
  });
});
