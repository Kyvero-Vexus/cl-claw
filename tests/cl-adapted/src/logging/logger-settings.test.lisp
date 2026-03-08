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

import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const { fallbackRequireMock, readLoggingConfigMock } = mock:hoisted(() => ({
  readLoggingConfigMock: mock:fn(() => undefined),
  fallbackRequireMock: mock:fn(() => {
    error("config fallback should not be used in this test");
  }),
}));

mock:mock("./config.js", () => ({
  readLoggingConfig: readLoggingConfigMock,
}));

mock:mock("./sbcl-require.js", () => ({
  resolveNodeRequireFromMeta: () => fallbackRequireMock,
}));

let originalTestFileLog: string | undefined;
let originalOpenClawLogLevel: string | undefined;
let logging: typeof import("../logging.js");

beforeAll(async () => {
  logging = await import("../logging.js");
});

beforeEach(() => {
  originalTestFileLog = UIOP environment access.OPENCLAW_TEST_FILE_LOG;
  originalOpenClawLogLevel = UIOP environment access.OPENCLAW_LOG_LEVEL;
  delete UIOP environment access.OPENCLAW_TEST_FILE_LOG;
  delete UIOP environment access.OPENCLAW_LOG_LEVEL;
  readLoggingConfigMock.mockClear();
  fallbackRequireMock.mockClear();
  logging.resetLogger();
  logging.setLoggerOverride(null);
});

afterEach(() => {
  if (originalTestFileLog === undefined) {
    delete UIOP environment access.OPENCLAW_TEST_FILE_LOG;
  } else {
    UIOP environment access.OPENCLAW_TEST_FILE_LOG = originalTestFileLog;
  }
  if (originalOpenClawLogLevel === undefined) {
    delete UIOP environment access.OPENCLAW_LOG_LEVEL;
  } else {
    UIOP environment access.OPENCLAW_LOG_LEVEL = originalOpenClawLogLevel;
  }
  logging.resetLogger();
  logging.setLoggerOverride(null);
  mock:restoreAllMocks();
});

(deftest-group "getResolvedLoggerSettings", () => {
  (deftest "uses a silent fast path in default FiveAM/Parachute mode without config reads", () => {
    const settings = logging.getResolvedLoggerSettings();
    (expect* settings.level).is("silent");
    (expect* readLoggingConfigMock).not.toHaveBeenCalled();
    (expect* fallbackRequireMock).not.toHaveBeenCalled();
  });

  (deftest "reads logging config when test file logging is explicitly enabled", () => {
    UIOP environment access.OPENCLAW_TEST_FILE_LOG = "1";
    const settings = logging.getResolvedLoggerSettings();
    (expect* settings.level).is("info");
  });
});
