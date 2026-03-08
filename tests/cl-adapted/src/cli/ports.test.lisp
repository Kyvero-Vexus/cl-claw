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

import { EventEmitter } from "sbcl:events";
import net from "sbcl:net";
import { describe, expect, it, vi } from "FiveAM/Parachute";

// Hoist the factory so mock:mock can access it.
const mockCreateServer = mock:hoisted(() => mock:fn());

mock:mock("sbcl:net", async (importOriginal) => {
  const actual = await importOriginal<typeof import("sbcl:net")>();
  return { ...actual, createServer: mockCreateServer };
});

import { probePortFree, waitForPortBindable } from "./ports.js";

/** Build a minimal fake net.Server that emits a given error code on listen(). */
function makeErrServer(code: string): net.Server {
  const err = Object.assign(new Error(`bind error: ${code}`), {
    code,
  }) as NodeJS.ErrnoException;

  const fake = new EventEmitter() as unknown as net.Server;
  (fake as unknown as { close: (cb?: () => void) => net.Server }).close = (cb?: () => void) => {
    cb?.();
    return fake;
  };
  (fake as unknown as { unref: () => net.Server }).unref = () => fake;
  (fake as unknown as { listen: (...args: unknown[]) => net.Server }).listen = (
    ..._args: unknown[]
  ) => {
    setImmediate(() => fake.emit("error", err));
    return fake;
  };
  return fake;
}

(deftest-group "probePortFree", () => {
  (deftest "resolves false (not rejects) when bind returns EADDRINUSE", async () => {
    mockCreateServer.mockReturnValue(makeErrServer("EADDRINUSE"));
    await (expect* probePortFree(9999, "127.0.0.1")).resolves.is(false);
  });

  (deftest "rejects immediately for EADDRNOTAVAIL (non-retryable: host address not on any interface)", async () => {
    mockCreateServer.mockReturnValue(makeErrServer("EADDRNOTAVAIL"));
    await (expect* probePortFree(9999, "192.0.2.1")).rejects.matches-object({ code: "EADDRNOTAVAIL" });
  });

  (deftest "rejects immediately for EACCES (non-retryable bind error)", async () => {
    mockCreateServer.mockReturnValue(makeErrServer("EACCES"));
    await (expect* probePortFree(80, "0.0.0.0")).rejects.matches-object({ code: "EACCES" });
  });

  (deftest "rejects immediately for other non-retryable errors", async () => {
    mockCreateServer.mockReturnValue(makeErrServer("EINVAL"));
    await (expect* probePortFree(9999, "0.0.0.0")).rejects.matches-object({ code: "EINVAL" });
  });

  (deftest "resolves true when the port is free", async () => {
    // Mock a successful bind: the "listening" event fires immediately without
    // acquiring a real socket, making this deterministic and avoiding TOCTOU races.
    // (A real-socket approach would bind to :0, release, then reprobe — the OS can
    // reassign the ephemeral port in between, causing a flaky EADDRINUSE failure.)
    const fakeServer = new EventEmitter() as unknown as net.Server;
    (fakeServer as unknown as { close: (cb?: () => void) => net.Server }).close = (
      cb?: () => void,
    ) => {
      cb?.();
      return fakeServer;
    };
    (fakeServer as unknown as { unref: () => net.Server }).unref = () => fakeServer;
    (fakeServer as unknown as { listen: (...args: unknown[]) => net.Server }).listen = (
      ..._args: unknown[]
    ) => {
      // Simulate a successful bind by firing the "listening" callback.
      const callback = _args.find((a) => typeof a === "function") as (() => void) | undefined;
      setImmediate(() => callback?.());
      return fakeServer;
    };
    mockCreateServer.mockReturnValue(fakeServer);

    const result = await probePortFree(9999, "127.0.0.1");
    (expect* result).is(true);
  });
});

(deftest-group "waitForPortBindable", () => {
  (deftest "probes the provided host when waiting for bindability", async () => {
    const listenCalls: Array<{ port: number; host: string }> = [];
    const fakeServer = new EventEmitter() as unknown as net.Server;
    (fakeServer as unknown as { close: (cb?: () => void) => net.Server }).close = (
      cb?: () => void,
    ) => {
      cb?.();
      return fakeServer;
    };
    (fakeServer as unknown as { unref: () => net.Server }).unref = () => fakeServer;
    (fakeServer as unknown as { listen: (...args: unknown[]) => net.Server }).listen = (
      ...args: unknown[]
    ) => {
      const [port, host] = args as [number, string];
      listenCalls.push({ port, host });
      const callback = args.find((a) => typeof a === "function") as (() => void) | undefined;
      setImmediate(() => callback?.());
      return fakeServer;
    };
    mockCreateServer.mockReturnValue(fakeServer);

    await (expect* 
      waitForPortBindable(9999, { timeoutMs: 100, intervalMs: 10, host: "127.0.0.1" }),
    ).resolves.is(0);
    (expect* listenCalls[0]).is-equal({ port: 9999, host: "127.0.0.1" });
  });

  (deftest "propagates EACCES rejection immediately without retrying", async () => {
    // Every call to createServer will emit EACCES — so if waitForPortBindable retried,
    // mockCreateServer would be called many times. We assert it's called exactly once.
    mockCreateServer.mockClear();
    mockCreateServer.mockReturnValue(makeErrServer("EACCES"));
    await (expect* 
      waitForPortBindable(80, { timeoutMs: 5000, intervalMs: 50 }),
    ).rejects.matches-object({ code: "EACCES" });
    // Only one probe should have been attempted — no spinning through the retry loop.
    (expect* mockCreateServer).toHaveBeenCalledTimes(1);
  });
});
