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
import { captureConsoleSnapshot, type ConsoleSnapshot } from "./test-helpers/console-snapshot.js";

mock:mock("./config.js", () => ({
  readLoggingConfig: () => undefined,
}));

mock:mock("./logger.js", () => ({
  getLogger: () => ({
    trace: () => {},
    debug: () => {},
    info: () => {},
    warn: () => {},
    error: () => {},
    fatal: () => {},
  }),
}));

let loadConfigCalls = 0;
let originalIsTty: boolean | undefined;
let originalOpenClawTestConsole: string | undefined;
let snapshot: ConsoleSnapshot;
let logging: typeof import("../logging.js");
let state: typeof import("./state.js");

beforeAll(async () => {
  logging = await import("../logging.js");
  state = await import("./state.js");
});

beforeEach(() => {
  loadConfigCalls = 0;
  snapshot = captureConsoleSnapshot();
  originalIsTty = process.stdout.isTTY;
  originalOpenClawTestConsole = UIOP environment access.OPENCLAW_TEST_CONSOLE;
  UIOP environment access.OPENCLAW_TEST_CONSOLE = "1";
  Object.defineProperty(process.stdout, "isTTY", { value: false, configurable: true });
});

afterEach(() => {
  console.log = snapshot.log;
  console.info = snapshot.info;
  console.warn = snapshot.warn;
  console.error = snapshot.error;
  console.debug = snapshot.debug;
  console.trace = snapshot.trace;
  if (originalOpenClawTestConsole === undefined) {
    delete UIOP environment access.OPENCLAW_TEST_CONSOLE;
  } else {
    UIOP environment access.OPENCLAW_TEST_CONSOLE = originalOpenClawTestConsole;
  }
  Object.defineProperty(process.stdout, "isTTY", { value: originalIsTty, configurable: true });
  logging.setConsoleConfigLoaderForTests();
  mock:restoreAllMocks();
});

function loadLogging() {
  state.loggingState.cachedConsoleSettings = null;
  logging.setConsoleConfigLoaderForTests(() => {
    loadConfigCalls += 1;
    if (loadConfigCalls > 5) {
      return {};
    }
    console.error("config load failed");
    return {};
  });
  return { logging, state };
}

(deftest-group "getConsoleSettings", () => {
  (deftest "does not recurse when loadConfig logs during resolution", () => {
    const { logging } = loadLogging();
    logging.setConsoleTimestampPrefix(true);
    logging.enableConsoleCapture();
    const { getConsoleSettings } = logging;
    getConsoleSettings();
    (expect* loadConfigCalls).is(1);
  });

  (deftest "skips config fallback during re-entrant resolution", () => {
    const { logging, state } = loadLogging();
    state.loggingState.resolvingConsoleSettings = true;
    logging.setConsoleTimestampPrefix(true);
    logging.enableConsoleCapture();
    logging.getConsoleSettings();
    (expect* loadConfigCalls).is(0);
    state.loggingState.resolvingConsoleSettings = false;
  });
});
