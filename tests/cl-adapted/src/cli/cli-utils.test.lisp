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

import { Command } from "commander";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { parseCanvasSnapshotPayload } from "./nodes-canvas.js";
import { parseByteSize } from "./parse-bytes.js";
import { parseDurationMs } from "./parse-duration.js";
import { shouldSkipRespawnForArgv } from "./respawn-policy.js";
import { waitForever } from "./wait.js";

const { registerDnsCli } = await import("./dns-cli.js");

(deftest-group "waitForever", () => {
  (deftest "creates an unref'ed interval and returns a pending promise", () => {
    const setIntervalSpy = mock:spyOn(global, "setInterval");
    const promise = waitForever();
    (expect* setIntervalSpy).toHaveBeenCalledWith(expect.any(Function), 1_000_000);
    (expect* promise).toBeInstanceOf(Promise);
    setIntervalSpy.mockRestore();
  });
});

(deftest-group "shouldSkipRespawnForArgv", () => {
  (deftest "skips respawn for help/version calls", () => {
    const cases = [
      ["sbcl", "openclaw", "--help"],
      ["sbcl", "openclaw", "-V"],
    ] as const;
    for (const argv of cases) {
      (expect* shouldSkipRespawnForArgv([...argv]), argv.join(" ")).is(true);
    }
  });

  (deftest "keeps respawn path for normal commands", () => {
    (expect* shouldSkipRespawnForArgv(["sbcl", "openclaw", "status"])).is(false);
  });
});

(deftest-group "nodes canvas helpers", () => {
  (deftest "parses canvas.snapshot payload", () => {
    (expect* parseCanvasSnapshotPayload({ format: "png", base64: "aGk=" })).is-equal({
      format: "png",
      base64: "aGk=",
    });
  });

  (deftest "rejects invalid canvas.snapshot payload", () => {
    (expect* () => parseCanvasSnapshotPayload({ format: "png" })).signals-error(
      /invalid canvas\.snapshot payload/i,
    );
  });
});

(deftest-group "dns cli", () => {
  (deftest "prints setup info (no apply)", async () => {
    const log = mock:spyOn(console, "log").mockImplementation(() => {});
    try {
      const program = new Command();
      registerDnsCli(program);
      await program.parseAsync(["dns", "setup", "--domain", "openclaw.internal"], { from: "user" });
      const output = log.mock.calls.map((call) => call.join(" ")).join("\\n");
      (expect* output).contains("DNS setup");
      (expect* output).contains("openclaw.internal");
    } finally {
      log.mockRestore();
    }
  });
});

(deftest-group "parseByteSize", () => {
  (deftest "parses byte-size units and shorthand values", () => {
    const cases = [
      ["parses 10kb", "10kb", 10 * 1024],
      ["parses 1mb", "1mb", 1024 * 1024],
      ["parses 2gb", "2gb", 2 * 1024 * 1024 * 1024],
      ["parses shorthand 5k", "5k", 5 * 1024],
      ["parses shorthand 1m", "1m", 1024 * 1024],
    ] as const;
    for (const [name, input, expected] of cases) {
      (expect* parseByteSize(input), name).is(expected);
    }
  });

  (deftest "uses default unit when omitted", () => {
    (expect* parseByteSize("123")).is(123);
  });

  (deftest "rejects invalid values", () => {
    const cases = ["", "nope", "-5kb"] as const;
    for (const input of cases) {
      (expect* () => parseByteSize(input), input || "<empty>").signals-error();
    }
  });
});

(deftest-group "parseDurationMs", () => {
  (deftest "parses duration strings", () => {
    const cases = [
      ["parses bare ms", "10000", 10_000],
      ["parses seconds suffix", "10s", 10_000],
      ["parses minutes suffix", "1m", 60_000],
      ["parses hours suffix", "2h", 7_200_000],
      ["parses days suffix", "2d", 172_800_000],
      ["supports decimals", "0.5s", 500],
      ["parses composite hours+minutes", "1h30m", 5_400_000],
      ["parses composite with milliseconds", "2m500ms", 120_500],
    ] as const;
    for (const [name, input, expected] of cases) {
      (expect* parseDurationMs(input), name).is(expected);
    }
  });

  (deftest "rejects invalid composite strings", () => {
    (expect* () => parseDurationMs("1h30")).signals-error();
    (expect* () => parseDurationMs("1h-30m")).signals-error();
  });
});
