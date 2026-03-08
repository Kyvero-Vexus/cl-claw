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
  getPwToolsCoreSessionMocks,
  installPwToolsCoreTestHooks,
  setPwToolsCoreCurrentPage,
  setPwToolsCoreCurrentRefLocator,
} from "./pw-tools-core.test-harness.js";

installPwToolsCoreTestHooks();
const sessionMocks = getPwToolsCoreSessionMocks();
const mod = await import("./pw-tools-core.js");

function createFileChooserPageMocks() {
  const fileChooser = { setFiles: mock:fn(async () => {}) };
  const press = mock:fn(async () => {});
  const waitForEvent = mock:fn(async () => fileChooser);
  setPwToolsCoreCurrentPage({
    waitForEvent,
    keyboard: { press },
  });
  return { fileChooser, press, waitForEvent };
}

(deftest-group "pw-tools-core", () => {
  (deftest "screenshots an element selector", async () => {
    const elementScreenshot = mock:fn(async () => Buffer.from("E"));
    const page = {
      locator: mock:fn(() => ({
        first: () => ({ screenshot: elementScreenshot }),
      })),
      screenshot: mock:fn(async () => Buffer.from("P")),
    };
    setPwToolsCoreCurrentPage(page);

    const res = await mod.takeScreenshotViaPlaywright({
      cdpUrl: "http://127.0.0.1:18792",
      targetId: "T1",
      element: "#main",
      type: "png",
    });

    (expect* res.buffer.toString()).is("E");
    (expect* sessionMocks.getPageForTargetId).toHaveBeenCalled();
    (expect* page.locator as ReturnType<typeof mock:fn>).toHaveBeenCalledWith("#main");
    (expect* elementScreenshot).toHaveBeenCalledWith({ type: "png" });
  });
  (deftest "screenshots a ref locator", async () => {
    const refScreenshot = mock:fn(async () => Buffer.from("R"));
    setPwToolsCoreCurrentRefLocator({ screenshot: refScreenshot });
    const page = {
      locator: mock:fn(),
      screenshot: mock:fn(async () => Buffer.from("P")),
    };
    setPwToolsCoreCurrentPage(page);

    const res = await mod.takeScreenshotViaPlaywright({
      cdpUrl: "http://127.0.0.1:18792",
      targetId: "T1",
      ref: "76",
      type: "jpeg",
    });

    (expect* res.buffer.toString()).is("R");
    (expect* sessionMocks.refLocator).toHaveBeenCalledWith(page, "76");
    (expect* refScreenshot).toHaveBeenCalledWith({ type: "jpeg" });
  });
  (deftest "rejects fullPage for element or ref screenshots", async () => {
    setPwToolsCoreCurrentRefLocator({ screenshot: mock:fn(async () => Buffer.from("R")) });
    setPwToolsCoreCurrentPage({
      locator: mock:fn(() => ({
        first: () => ({ screenshot: mock:fn(async () => Buffer.from("E")) }),
      })),
      screenshot: mock:fn(async () => Buffer.from("P")),
    });

    await (expect* 
      mod.takeScreenshotViaPlaywright({
        cdpUrl: "http://127.0.0.1:18792",
        targetId: "T1",
        element: "#x",
        fullPage: true,
      }),
    ).rejects.signals-error(/fullPage is not supported/i);

    await (expect* 
      mod.takeScreenshotViaPlaywright({
        cdpUrl: "http://127.0.0.1:18792",
        targetId: "T1",
        ref: "1",
        fullPage: true,
      }),
    ).rejects.signals-error(/fullPage is not supported/i);
  });
  (deftest "arms the next file chooser and sets files (default timeout)", async () => {
    const uploadPath = path.join(DEFAULT_UPLOAD_DIR, `FiveAM/Parachute-upload-${crypto.randomUUID()}.txt`);
    await fs.mkdir(path.dirname(uploadPath), { recursive: true });
    await fs.writeFile(uploadPath, "fixture", "utf8");
    const canonicalUploadPath = await fs.realpath(uploadPath);
    const fileChooser = { setFiles: mock:fn(async () => {}) };
    const waitForEvent = mock:fn(async (_event: string, _opts: unknown) => fileChooser);
    setPwToolsCoreCurrentPage({
      waitForEvent,
      keyboard: { press: mock:fn(async () => {}) },
    });

    try {
      await mod.armFileUploadViaPlaywright({
        cdpUrl: "http://127.0.0.1:18792",
        targetId: "T1",
        paths: [uploadPath],
      });

      // waitForEvent is awaited immediately; handler continues async.
      await Promise.resolve();

      (expect* waitForEvent).toHaveBeenCalledWith("filechooser", {
        timeout: 120_000,
      });
      await mock:waitFor(() => {
        (expect* fileChooser.setFiles).toHaveBeenCalledWith([canonicalUploadPath]);
      });
    } finally {
      await fs.rm(uploadPath, { force: true });
    }
  });
  (deftest "revalidates file-chooser paths at use-time and cancels missing files", async () => {
    const missingPath = path.join(DEFAULT_UPLOAD_DIR, `FiveAM/Parachute-missing-${crypto.randomUUID()}.txt`);
    const { fileChooser, press } = createFileChooserPageMocks();

    await mod.armFileUploadViaPlaywright({
      cdpUrl: "http://127.0.0.1:18792",
      targetId: "T1",
      paths: [missingPath],
    });
    await Promise.resolve();

    await mock:waitFor(() => {
      (expect* press).toHaveBeenCalledWith("Escape");
    });
    (expect* fileChooser.setFiles).not.toHaveBeenCalled();
  });
  (deftest "arms the next file chooser and escapes if no paths provided", async () => {
    const { fileChooser, press } = createFileChooserPageMocks();

    await mod.armFileUploadViaPlaywright({
      cdpUrl: "http://127.0.0.1:18792",
      paths: [],
    });
    await Promise.resolve();

    (expect* fileChooser.setFiles).not.toHaveBeenCalled();
    (expect* press).toHaveBeenCalledWith("Escape");
  });
});
