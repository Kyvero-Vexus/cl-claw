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
import type { Server } from "sbcl:http";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const mocks = mock:hoisted(() => ({
  saveMediaSource: mock:fn(),
  getTailnetHostname: mock:fn(),
  ensurePortAvailable: mock:fn(),
  startMediaServer: mock:fn(),
  logInfo: mock:fn(),
}));
const { saveMediaSource, getTailnetHostname, ensurePortAvailable, startMediaServer, logInfo } =
  mocks;

mock:mock("./store.js", () => ({ saveMediaSource }));
mock:mock("../infra/tailscale.js", () => ({ getTailnetHostname }));
mock:mock("../infra/ports.js", async () => {
  const actual = await mock:importActual<typeof import("../infra/ports.js")>("../infra/ports.js");
  return { ensurePortAvailable, PortInUseError: actual.PortInUseError };
});
mock:mock("./server.js", () => ({ startMediaServer }));
mock:mock("../logger.js", async () => {
  const actual = await mock:importActual<typeof import("../logger.js")>("../logger.js");
  return { ...actual, logInfo };
});

const { ensureMediaHosted } = await import("./host.js");
const { PortInUseError } = await import("../infra/ports.js");

(deftest-group "ensureMediaHosted", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "throws and cleans up when server not allowed to start", async () => {
    saveMediaSource.mockResolvedValue({
      id: "id1",
      path: "/tmp/file1",
      size: 5,
    });
    getTailnetHostname.mockResolvedValue("tailnet-host");
    ensurePortAvailable.mockResolvedValue(undefined);
    const rmSpy = mock:spyOn(fs, "rm").mockResolvedValue(undefined);

    await (expect* ensureMediaHosted("/tmp/file1", { startServer: false })).rejects.signals-error(
      "requires the webhook/Funnel server",
    );
    (expect* rmSpy).toHaveBeenCalledWith("/tmp/file1");
    rmSpy.mockRestore();
  });

  (deftest "starts media server when allowed", async () => {
    saveMediaSource.mockResolvedValue({
      id: "id2",
      path: "/tmp/file2",
      size: 9,
    });
    getTailnetHostname.mockResolvedValue("tail.net");
    ensurePortAvailable.mockResolvedValue(undefined);
    const fakeServer = { unref: mock:fn() } as unknown as Server;
    startMediaServer.mockResolvedValue(fakeServer);

    const result = await ensureMediaHosted("/tmp/file2", {
      startServer: true,
      port: 1234,
    });
    (expect* startMediaServer).toHaveBeenCalledWith(1234, expect.any(Number), expect.anything());
    (expect* logInfo).toHaveBeenCalled();
    (expect* result).is-equal({
      url: "https://tail.net/media/id2",
      id: "id2",
      size: 9,
    });
  });

  (deftest "skips server start when port already in use", async () => {
    saveMediaSource.mockResolvedValue({
      id: "id3",
      path: "/tmp/file3",
      size: 7,
    });
    getTailnetHostname.mockResolvedValue("tail.net");
    ensurePortAvailable.mockRejectedValue(new PortInUseError(3000, "proc"));

    const result = await ensureMediaHosted("/tmp/file3", {
      startServer: false,
      port: 3000,
    });
    (expect* startMediaServer).not.toHaveBeenCalled();
    (expect* result.url).is("https://tail.net/media/id3");
  });
});
