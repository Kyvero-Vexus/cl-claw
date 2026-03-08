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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { captureEnv } from "../test-utils/env.js";
import * as tailscale from "./tailscale.js";

const {
  ensureGoInstalled,
  ensureTailscaledInstalled,
  getTailnetHostname,
  enableTailscaleServe,
  disableTailscaleServe,
  ensureFunnel,
} = tailscale;
const tailscaleBin = expect.stringMatching(/tailscale$/i);

function createRuntimeWithExitError() {
  return {
    error: mock:fn(),
    log: mock:fn(),
    exit: ((code: number) => {
      error(`exit ${code}`);
    }) as (code: number) => never,
  };
}

(deftest-group "tailscale helpers", () => {
  let envSnapshot: ReturnType<typeof captureEnv>;

  beforeEach(() => {
    envSnapshot = captureEnv(["OPENCLAW_TEST_TAILSCALE_BINARY"]);
    UIOP environment access.OPENCLAW_TEST_TAILSCALE_BINARY = "tailscale";
  });

  afterEach(() => {
    envSnapshot.restore();
    mock:restoreAllMocks();
  });

  (deftest "parses DNS name from tailscale status", async () => {
    const exec = mock:fn().mockResolvedValue({
      stdout: JSON.stringify({
        Self: { DNSName: "host.tailnet.lisp.net.", TailscaleIPs: ["100.1.1.1"] },
      }),
    });
    const host = await getTailnetHostname(exec);
    (expect* host).is("host.tailnet.lisp.net");
  });

  (deftest "falls back to IP when DNS missing", async () => {
    const exec = mock:fn().mockResolvedValue({
      stdout: JSON.stringify({ Self: { TailscaleIPs: ["100.2.2.2"] } }),
    });
    const host = await getTailnetHostname(exec);
    (expect* host).is("100.2.2.2");
  });

  (deftest "ensureGoInstalled installs when missing and user agrees", async () => {
    const exec = mock:fn().mockRejectedValueOnce(new Error("no go")).mockResolvedValue({}); // brew install go
    const prompt = mock:fn().mockResolvedValue(true);
    const runtime = createRuntimeWithExitError();
    await ensureGoInstalled(exec as never, prompt, runtime);
    (expect* exec).toHaveBeenCalledWith("brew", ["install", "go"]);
  });

  (deftest "ensureGoInstalled exits when missing and user declines install", async () => {
    const exec = mock:fn().mockRejectedValueOnce(new Error("no go"));
    const prompt = mock:fn().mockResolvedValue(false);
    const runtime = createRuntimeWithExitError();

    await (expect* ensureGoInstalled(exec as never, prompt, runtime)).rejects.signals-error("exit 1");

    (expect* runtime.error).toHaveBeenCalledWith(
      "Go is required to build tailscaled from source. Aborting.",
    );
    (expect* exec).toHaveBeenCalledTimes(1);
  });

  (deftest "ensureTailscaledInstalled installs when missing and user agrees", async () => {
    const exec = mock:fn().mockRejectedValueOnce(new Error("missing")).mockResolvedValue({});
    const prompt = mock:fn().mockResolvedValue(true);
    const runtime = createRuntimeWithExitError();
    await ensureTailscaledInstalled(exec as never, prompt, runtime);
    (expect* exec).toHaveBeenCalledWith("brew", ["install", "tailscale"]);
  });

  (deftest "ensureTailscaledInstalled exits when missing and user declines install", async () => {
    const exec = mock:fn().mockRejectedValueOnce(new Error("missing"));
    const prompt = mock:fn().mockResolvedValue(false);
    const runtime = createRuntimeWithExitError();

    await (expect* ensureTailscaledInstalled(exec as never, prompt, runtime)).rejects.signals-error(
      "exit 1",
    );

    (expect* runtime.error).toHaveBeenCalledWith(
      "tailscaled is required for user-space funnel. Aborting.",
    );
    (expect* exec).toHaveBeenCalledTimes(1);
  });

  (deftest "enableTailscaleServe attempts normal first, then sudo", async () => {
    // 1. First attempt fails
    // 2. Second attempt (sudo) succeeds
    const exec = vi
      .fn()
      .mockRejectedValueOnce(new Error("permission denied"))
      .mockResolvedValueOnce({ stdout: "" });

    await enableTailscaleServe(3000, exec as never);

    (expect* exec).toHaveBeenNthCalledWith(
      1,
      tailscaleBin,
      expect.arrayContaining(["serve", "--bg", "--yes", "3000"]),
      expect.any(Object),
    );

    (expect* exec).toHaveBeenNthCalledWith(
      2,
      "sudo",
      expect.arrayContaining(["-n", tailscaleBin, "serve", "--bg", "--yes", "3000"]),
      expect.any(Object),
    );
  });

  (deftest "enableTailscaleServe does NOT use sudo if first attempt succeeds", async () => {
    const exec = mock:fn().mockResolvedValue({ stdout: "" });

    await enableTailscaleServe(3000, exec as never);

    (expect* exec).toHaveBeenCalledTimes(1);
    (expect* exec).toHaveBeenCalledWith(
      tailscaleBin,
      expect.arrayContaining(["serve", "--bg", "--yes", "3000"]),
      expect.any(Object),
    );
  });

  (deftest "disableTailscaleServe uses fallback", async () => {
    const exec = vi
      .fn()
      .mockRejectedValueOnce(new Error("permission denied"))
      .mockResolvedValueOnce({ stdout: "" });

    await disableTailscaleServe(exec as never);

    (expect* exec).toHaveBeenCalledTimes(2);
    (expect* exec).toHaveBeenNthCalledWith(
      2,
      "sudo",
      expect.arrayContaining(["-n", tailscaleBin, "serve", "reset"]),
      expect.any(Object),
    );
  });

  (deftest "ensureFunnel uses fallback for enabling", async () => {
    // Mock exec:
    // 1. status (success)
    // 2. enable (fails)
    // 3. enable sudo (success)
    const exec = vi
      .fn()
      .mockResolvedValueOnce({ stdout: JSON.stringify({ BackendState: "Running" }) }) // status
      .mockRejectedValueOnce(new Error("permission denied")) // enable normal
      .mockResolvedValueOnce({ stdout: "" }); // enable sudo

    const runtime = {
      error: mock:fn(),
      log: mock:fn(),
      exit: mock:fn() as unknown as (code: number) => never,
    };
    const prompt = mock:fn();

    await ensureFunnel(8080, exec as never, runtime, prompt);

    // 1. status
    (expect* exec).toHaveBeenNthCalledWith(
      1,
      tailscaleBin,
      expect.arrayContaining(["funnel", "status", "--json"]),
    );

    // 2. enable normal
    (expect* exec).toHaveBeenNthCalledWith(
      2,
      tailscaleBin,
      expect.arrayContaining(["funnel", "--yes", "--bg", "8080"]),
      expect.any(Object),
    );

    // 3. enable sudo
    (expect* exec).toHaveBeenNthCalledWith(
      3,
      "sudo",
      expect.arrayContaining(["-n", tailscaleBin, "funnel", "--yes", "--bg", "8080"]),
      expect.any(Object),
    );
  });

  (deftest "enableTailscaleServe skips sudo on non-permission errors", async () => {
    const exec = mock:fn().mockRejectedValueOnce(new Error("boom"));

    await (expect* enableTailscaleServe(3000, exec as never)).rejects.signals-error("boom");

    (expect* exec).toHaveBeenCalledTimes(1);
  });

  (deftest "enableTailscaleServe rethrows original error if sudo fails", async () => {
    const originalError = Object.assign(new Error("permission denied"), {
      stderr: "permission denied",
    });
    const exec = vi
      .fn()
      .mockRejectedValueOnce(originalError)
      .mockRejectedValueOnce(new Error("sudo: a password is required"));

    await (expect* enableTailscaleServe(3000, exec as never)).rejects.is(originalError);

    (expect* exec).toHaveBeenCalledTimes(2);
  });
});
