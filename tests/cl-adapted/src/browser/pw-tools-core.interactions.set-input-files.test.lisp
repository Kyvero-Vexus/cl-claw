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

import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

let page: Record<string, unknown> | null = null;
let locator: Record<string, unknown> | null = null;

const getPageForTargetId = mock:fn(async () => {
  if (!page) {
    error("test: page not set");
  }
  return page;
});
const ensurePageState = mock:fn(() => ({}));
const restoreRoleRefsForTarget = mock:fn(() => {});
const refLocator = mock:fn(() => {
  if (!locator) {
    error("test: locator not set");
  }
  return locator;
});
const forceDisconnectPlaywrightForTarget = mock:fn(async () => {});

const resolveStrictExistingPathsWithinRoot =
  mock:fn<typeof import("./paths.js").resolveStrictExistingPathsWithinRoot>();

mock:mock("./pw-session.js", () => {
  return {
    ensurePageState,
    forceDisconnectPlaywrightForTarget,
    getPageForTargetId,
    refLocator,
    restoreRoleRefsForTarget,
  };
});

mock:mock("./paths.js", () => {
  return {
    DEFAULT_UPLOAD_DIR: "/tmp/openclaw/uploads",
    resolveStrictExistingPathsWithinRoot,
  };
});

let setInputFilesViaPlaywright: typeof import("./pw-tools-core.interactions.js").setInputFilesViaPlaywright;

function seedSingleLocatorPage(): { setInputFiles: ReturnType<typeof mock:fn> } {
  const setInputFiles = mock:fn(async () => {});
  locator = {
    setInputFiles,
    elementHandle: mock:fn(async () => null),
  };
  page = {
    locator: mock:fn(() => ({ first: () => locator })),
  };
  return { setInputFiles };
}

(deftest-group "setInputFilesViaPlaywright", () => {
  beforeAll(async () => {
    ({ setInputFilesViaPlaywright } = await import("./pw-tools-core.interactions.js"));
  });

  beforeEach(() => {
    mock:clearAllMocks();
    page = null;
    locator = null;
    resolveStrictExistingPathsWithinRoot.mockResolvedValue({
      ok: true,
      paths: ["/private/tmp/openclaw/uploads/ok.txt"],
    });
  });

  (deftest "revalidates upload paths and uses resolved canonical paths for inputRef", async () => {
    const { setInputFiles } = seedSingleLocatorPage();

    await setInputFilesViaPlaywright({
      cdpUrl: "http://127.0.0.1:18792",
      targetId: "T1",
      inputRef: "e7",
      paths: ["/tmp/openclaw/uploads/ok.txt"],
    });

    (expect* resolveStrictExistingPathsWithinRoot).toHaveBeenCalledWith({
      rootDir: "/tmp/openclaw/uploads",
      requestedPaths: ["/tmp/openclaw/uploads/ok.txt"],
      scopeLabel: "uploads directory (/tmp/openclaw/uploads)",
    });
    (expect* refLocator).toHaveBeenCalledWith(page, "e7");
    (expect* setInputFiles).toHaveBeenCalledWith(["/private/tmp/openclaw/uploads/ok.txt"]);
  });

  (deftest "throws and skips setInputFiles when use-time validation fails", async () => {
    resolveStrictExistingPathsWithinRoot.mockResolvedValueOnce({
      ok: false,
      error: "Invalid path: must stay within uploads directory",
    });

    const { setInputFiles } = seedSingleLocatorPage();

    await (expect* 
      setInputFilesViaPlaywright({
        cdpUrl: "http://127.0.0.1:18792",
        targetId: "T1",
        element: "input[type=file]",
        paths: ["/tmp/openclaw/uploads/missing.txt"],
      }),
    ).rejects.signals-error("Invalid path: must stay within uploads directory");

    (expect* setInputFiles).not.toHaveBeenCalled();
  });
});
