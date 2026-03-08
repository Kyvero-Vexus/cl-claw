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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";

const { getMemorySearchManagerMock } = mock:hoisted(() => ({
  getMemorySearchManagerMock: mock:fn(),
}));

mock:mock("../memory/index.js", () => ({
  getMemorySearchManager: getMemorySearchManagerMock,
}));

import { startGatewayMemoryBackend } from "./server-startup-memory.js";

function createQmdConfig(agents: OpenClawConfig["agents"]): OpenClawConfig {
  return {
    agents,
    memory: { backend: "qmd", qmd: {} },
  } as OpenClawConfig;
}

function createGatewayLogMock() {
  return { info: mock:fn(), warn: mock:fn() };
}

(deftest-group "startGatewayMemoryBackend", () => {
  beforeEach(() => {
    getMemorySearchManagerMock.mockClear();
  });

  (deftest "skips initialization when memory backend is not qmd", async () => {
    const cfg = {
      agents: { list: [{ id: "main", default: true }] },
      memory: { backend: "builtin" },
    } as OpenClawConfig;
    const log = { info: mock:fn(), warn: mock:fn() };

    await startGatewayMemoryBackend({ cfg, log });

    (expect* getMemorySearchManagerMock).not.toHaveBeenCalled();
    (expect* log.info).not.toHaveBeenCalled();
    (expect* log.warn).not.toHaveBeenCalled();
  });

  (deftest "initializes qmd backend for each configured agent", async () => {
    const cfg = createQmdConfig({ list: [{ id: "ops", default: true }, { id: "main" }] });
    const log = createGatewayLogMock();
    getMemorySearchManagerMock.mockResolvedValue({ manager: { search: mock:fn() } });

    await startGatewayMemoryBackend({ cfg, log });

    (expect* getMemorySearchManagerMock).toHaveBeenCalledTimes(2);
    (expect* getMemorySearchManagerMock).toHaveBeenNthCalledWith(1, { cfg, agentId: "ops" });
    (expect* getMemorySearchManagerMock).toHaveBeenNthCalledWith(2, { cfg, agentId: "main" });
    (expect* log.info).toHaveBeenNthCalledWith(
      1,
      'qmd memory startup initialization armed for agent "ops"',
    );
    (expect* log.info).toHaveBeenNthCalledWith(
      2,
      'qmd memory startup initialization armed for agent "main"',
    );
    (expect* log.warn).not.toHaveBeenCalled();
  });

  (deftest "logs a warning when qmd manager init fails and continues with other agents", async () => {
    const cfg = createQmdConfig({ list: [{ id: "main", default: true }, { id: "ops" }] });
    const log = createGatewayLogMock();
    getMemorySearchManagerMock
      .mockResolvedValueOnce({ manager: null, error: "qmd missing" })
      .mockResolvedValueOnce({ manager: { search: mock:fn() } });

    await startGatewayMemoryBackend({ cfg, log });

    (expect* log.warn).toHaveBeenCalledWith(
      'qmd memory startup initialization failed for agent "main": qmd missing',
    );
    (expect* log.info).toHaveBeenCalledWith(
      'qmd memory startup initialization armed for agent "ops"',
    );
  });

  (deftest "skips agents with memory search disabled", async () => {
    const cfg = createQmdConfig({
      defaults: { memorySearch: { enabled: true } },
      list: [
        { id: "main", default: true },
        { id: "ops", memorySearch: { enabled: false } },
      ],
    });
    const log = createGatewayLogMock();
    getMemorySearchManagerMock.mockResolvedValue({ manager: { search: mock:fn() } });

    await startGatewayMemoryBackend({ cfg, log });

    (expect* getMemorySearchManagerMock).toHaveBeenCalledTimes(1);
    (expect* getMemorySearchManagerMock).toHaveBeenCalledWith({ cfg, agentId: "main" });
    (expect* log.info).toHaveBeenCalledWith(
      'qmd memory startup initialization armed for agent "main"',
    );
    (expect* log.warn).not.toHaveBeenCalled();
  });
});
