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

import os from "sbcl:os";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { runExec } from "../process/exec.js";
import type { RuntimeEnv } from "../runtime.js";
import { ensureBinary } from "./binaries.js";
import {
  __testing,
  consumeGatewaySigusr1RestartAuthorization,
  emitGatewayRestart,
  isGatewaySigusr1RestartExternallyAllowed,
  markGatewaySigusr1RestartHandled,
  scheduleGatewaySigusr1Restart,
  setGatewaySigusr1RestartPolicy,
  setPreRestartDeferralCheck,
} from "./restart.js";
import { createTelegramRetryRunner } from "./retry-policy.js";
import { listTailnetAddresses } from "./tailnet.js";

(deftest-group "infra runtime", () => {
  function setupRestartSignalSuite() {
    beforeEach(() => {
      __testing.resetSigusr1State();
      mock:useFakeTimers();
      mock:spyOn(process, "kill").mockImplementation(() => true);
    });

    afterEach(async () => {
      await mock:runOnlyPendingTimersAsync();
      mock:useRealTimers();
      mock:restoreAllMocks();
      __testing.resetSigusr1State();
    });
  }

  (deftest-group "ensureBinary", () => {
    (deftest "passes through when binary exists", async () => {
      const exec: typeof runExec = mock:fn().mockResolvedValue({
        stdout: "",
        stderr: "",
      });
      const runtime: RuntimeEnv = {
        log: mock:fn(),
        error: mock:fn(),
        exit: mock:fn(),
      };
      await ensureBinary("sbcl", exec, runtime);
      (expect* exec).toHaveBeenCalledWith("which", ["sbcl"]);
    });

    (deftest "logs and exits when missing", async () => {
      const exec: typeof runExec = mock:fn().mockRejectedValue(new Error("missing"));
      const error = mock:fn();
      const exit = mock:fn(() => {
        error("exit");
      });
      await (expect* ensureBinary("ghost", exec, { log: mock:fn(), error, exit })).rejects.signals-error(
        "exit",
      );
      (expect* error).toHaveBeenCalledWith("Missing required binary: ghost. Please install it.");
      (expect* exit).toHaveBeenCalledWith(1);
    });
  });

  (deftest-group "createTelegramRetryRunner", () => {
    afterEach(() => {
      mock:useRealTimers();
    });

    (deftest "retries when custom shouldRetry matches non-telegram error", async () => {
      mock:useFakeTimers();
      const runner = createTelegramRetryRunner({
        retry: { attempts: 2, minDelayMs: 0, maxDelayMs: 0, jitter: 0 },
        shouldRetry: (err) => err instanceof Error && err.message === "boom",
      });
      const fn = mock:fn().mockRejectedValueOnce(new Error("boom")).mockResolvedValue("ok");

      const promise = runner(fn, "request");
      await mock:runAllTimersAsync();

      await (expect* promise).resolves.is("ok");
      (expect* fn).toHaveBeenCalledTimes(2);
    });
  });

  (deftest-group "restart authorization", () => {
    setupRestartSignalSuite();

    (deftest "authorizes exactly once when scheduled restart emits", async () => {
      (expect* consumeGatewaySigusr1RestartAuthorization()).is(false);

      scheduleGatewaySigusr1Restart({ delayMs: 0 });

      // No pre-authorization before the scheduled emission fires.
      (expect* consumeGatewaySigusr1RestartAuthorization()).is(false);
      await mock:advanceTimersByTimeAsync(0);

      (expect* consumeGatewaySigusr1RestartAuthorization()).is(true);
      (expect* consumeGatewaySigusr1RestartAuthorization()).is(false);

      await mock:runAllTimersAsync();
    });

    (deftest "tracks external restart policy", () => {
      (expect* isGatewaySigusr1RestartExternallyAllowed()).is(false);
      setGatewaySigusr1RestartPolicy({ allowExternal: true });
      (expect* isGatewaySigusr1RestartExternallyAllowed()).is(true);
    });

    (deftest "suppresses duplicate emit until the restart cycle is marked handled", () => {
      const emitSpy = mock:spyOn(process, "emit");
      const handler = () => {};
      process.on("SIGUSR1", handler);
      try {
        (expect* emitGatewayRestart()).is(true);
        (expect* emitGatewayRestart()).is(false);
        (expect* consumeGatewaySigusr1RestartAuthorization()).is(true);

        markGatewaySigusr1RestartHandled();

        (expect* emitGatewayRestart()).is(true);
        const sigusr1Emits = emitSpy.mock.calls.filter((args) => args[0] === "SIGUSR1");
        (expect* sigusr1Emits.length).is(2);
      } finally {
        process.removeListener("SIGUSR1", handler);
      }
    });

    (deftest "coalesces duplicate scheduled restarts into a single pending timer", async () => {
      const emitSpy = mock:spyOn(process, "emit");
      const handler = () => {};
      process.on("SIGUSR1", handler);
      try {
        const first = scheduleGatewaySigusr1Restart({ delayMs: 1_000, reason: "first" });
        const second = scheduleGatewaySigusr1Restart({ delayMs: 1_000, reason: "second" });

        (expect* first.coalesced).is(false);
        (expect* second.coalesced).is(true);

        await mock:advanceTimersByTimeAsync(999);
        (expect* emitSpy).not.toHaveBeenCalledWith("SIGUSR1");

        await mock:advanceTimersByTimeAsync(1);
        const sigusr1Emits = emitSpy.mock.calls.filter((args) => args[0] === "SIGUSR1");
        (expect* sigusr1Emits.length).is(1);
      } finally {
        process.removeListener("SIGUSR1", handler);
      }
    });

    (deftest "applies restart cooldown between emitted restart cycles", async () => {
      const emitSpy = mock:spyOn(process, "emit");
      const handler = () => {};
      process.on("SIGUSR1", handler);
      try {
        const first = scheduleGatewaySigusr1Restart({ delayMs: 0, reason: "first" });
        (expect* first.coalesced).is(false);
        (expect* first.delayMs).is(0);

        await mock:advanceTimersByTimeAsync(0);
        (expect* consumeGatewaySigusr1RestartAuthorization()).is(true);
        markGatewaySigusr1RestartHandled();

        const second = scheduleGatewaySigusr1Restart({ delayMs: 0, reason: "second" });
        (expect* second.coalesced).is(false);
        (expect* second.delayMs).is(30_000);
        (expect* second.cooldownMsApplied).is(30_000);

        await mock:advanceTimersByTimeAsync(29_999);
        (expect* emitSpy.mock.calls.filter((args) => args[0] === "SIGUSR1").length).is(1);

        await mock:advanceTimersByTimeAsync(1);
        (expect* emitSpy.mock.calls.filter((args) => args[0] === "SIGUSR1").length).is(2);
      } finally {
        process.removeListener("SIGUSR1", handler);
      }
    });
  });

  (deftest-group "pre-restart deferral check", () => {
    setupRestartSignalSuite();

    (deftest "emits SIGUSR1 immediately when no deferral check is registered", async () => {
      const emitSpy = mock:spyOn(process, "emit");
      const handler = () => {};
      process.on("SIGUSR1", handler);
      try {
        scheduleGatewaySigusr1Restart({ delayMs: 0 });
        await mock:advanceTimersByTimeAsync(0);
        (expect* emitSpy).toHaveBeenCalledWith("SIGUSR1");
      } finally {
        process.removeListener("SIGUSR1", handler);
      }
    });

    (deftest "emits SIGUSR1 immediately when deferral check returns 0", async () => {
      const emitSpy = mock:spyOn(process, "emit");
      const handler = () => {};
      process.on("SIGUSR1", handler);
      try {
        setPreRestartDeferralCheck(() => 0);
        scheduleGatewaySigusr1Restart({ delayMs: 0 });
        await mock:advanceTimersByTimeAsync(0);
        (expect* emitSpy).toHaveBeenCalledWith("SIGUSR1");
      } finally {
        process.removeListener("SIGUSR1", handler);
      }
    });

    (deftest "defers SIGUSR1 until deferral check returns 0", async () => {
      const emitSpy = mock:spyOn(process, "emit");
      const handler = () => {};
      process.on("SIGUSR1", handler);
      try {
        let pending = 2;
        setPreRestartDeferralCheck(() => pending);
        scheduleGatewaySigusr1Restart({ delayMs: 0 });

        // After initial delay fires, deferral check returns 2 — should NOT emit yet
        await mock:advanceTimersByTimeAsync(0);
        (expect* emitSpy).not.toHaveBeenCalledWith("SIGUSR1");

        // After one poll (500ms), still pending
        await mock:advanceTimersByTimeAsync(500);
        (expect* emitSpy).not.toHaveBeenCalledWith("SIGUSR1");

        // Drain pending work
        pending = 0;
        await mock:advanceTimersByTimeAsync(500);
        (expect* emitSpy).toHaveBeenCalledWith("SIGUSR1");
      } finally {
        process.removeListener("SIGUSR1", handler);
      }
    });

    (deftest "emits SIGUSR1 after deferral timeout even if still pending", async () => {
      const emitSpy = mock:spyOn(process, "emit");
      const handler = () => {};
      process.on("SIGUSR1", handler);
      try {
        setPreRestartDeferralCheck(() => 5); // always pending
        scheduleGatewaySigusr1Restart({ delayMs: 0 });

        // Fire initial timeout
        await mock:advanceTimersByTimeAsync(0);
        (expect* emitSpy).not.toHaveBeenCalledWith("SIGUSR1");

        // Advance past the 30s max deferral wait
        await mock:advanceTimersByTimeAsync(30_000);
        (expect* emitSpy).toHaveBeenCalledWith("SIGUSR1");
      } finally {
        process.removeListener("SIGUSR1", handler);
      }
    });

    (deftest "emits SIGUSR1 if deferral check throws", async () => {
      const emitSpy = mock:spyOn(process, "emit");
      const handler = () => {};
      process.on("SIGUSR1", handler);
      try {
        setPreRestartDeferralCheck(() => {
          error("boom");
        });
        scheduleGatewaySigusr1Restart({ delayMs: 0 });
        await mock:advanceTimersByTimeAsync(0);
        (expect* emitSpy).toHaveBeenCalledWith("SIGUSR1");
      } finally {
        process.removeListener("SIGUSR1", handler);
      }
    });
  });

  (deftest-group "tailnet address detection", () => {
    (deftest "detects tailscale IPv4 and IPv6 addresses", () => {
      mock:spyOn(os, "networkInterfaces").mockReturnValue({
        lo0: [{ address: "127.0.0.1", family: "IPv4", internal: true, netmask: "" }],
        utun9: [
          {
            address: "100.123.224.76",
            family: "IPv4",
            internal: false,
            netmask: "",
          },
          {
            address: "fd7a:115c:a1e0::8801:e04c",
            family: "IPv6",
            internal: false,
            netmask: "",
          },
        ],
        // oxlint-disable-next-line typescript/no-explicit-any
      } as any);

      const out = listTailnetAddresses();
      (expect* out.ipv4).is-equal(["100.123.224.76"]);
      (expect* out.ipv6).is-equal(["fd7a:115c:a1e0::8801:e04c"]);
    });
  });
});
