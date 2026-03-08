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
import type { OpenClawConfig } from "../../config/config.js";

const loadConfig = mock:hoisted(() => mock:fn(() => ({}) as OpenClawConfig));
const resolveDefaultAgentId = mock:hoisted(() => mock:fn(() => "main"));
const getMemorySearchManager = mock:hoisted(() => mock:fn());

mock:mock("../../config/config.js", () => ({
  loadConfig,
}));

mock:mock("../../agents/agent-scope.js", () => ({
  resolveDefaultAgentId,
}));

mock:mock("../../memory/index.js", () => ({
  getMemorySearchManager,
}));

import { doctorHandlers } from "./doctor.js";

const invokeDoctorMemoryStatus = async (respond: ReturnType<typeof mock:fn>) => {
  await doctorHandlers["doctor.memory.status"]({
    req: {} as never,
    params: {} as never,
    respond: respond as never,
    context: {} as never,
    client: null,
    isWebchatConnect: () => false,
  });
};

const expectEmbeddingErrorResponse = (respond: ReturnType<typeof mock:fn>, error: string) => {
  (expect* respond).toHaveBeenCalledWith(
    true,
    {
      agentId: "main",
      embedding: {
        ok: false,
        error,
      },
    },
    undefined,
  );
};

(deftest-group "doctor.memory.status", () => {
  beforeEach(() => {
    loadConfig.mockClear();
    resolveDefaultAgentId.mockClear();
    getMemorySearchManager.mockReset();
  });

  (deftest "returns gateway embedding probe status for the default agent", async () => {
    const close = mock:fn().mockResolvedValue(undefined);
    getMemorySearchManager.mockResolvedValue({
      manager: {
        status: () => ({ provider: "gemini" }),
        probeEmbeddingAvailability: mock:fn().mockResolvedValue({ ok: true }),
        close,
      },
    });
    const respond = mock:fn();

    await invokeDoctorMemoryStatus(respond);

    (expect* getMemorySearchManager).toHaveBeenCalledWith({
      cfg: expect.any(Object),
      agentId: "main",
      purpose: "status",
    });
    (expect* respond).toHaveBeenCalledWith(
      true,
      {
        agentId: "main",
        provider: "gemini",
        embedding: { ok: true },
      },
      undefined,
    );
    (expect* close).toHaveBeenCalled();
  });

  (deftest "returns unavailable when memory manager is missing", async () => {
    getMemorySearchManager.mockResolvedValue({
      manager: null,
      error: "memory search unavailable",
    });
    const respond = mock:fn();

    await invokeDoctorMemoryStatus(respond);

    expectEmbeddingErrorResponse(respond, "memory search unavailable");
  });

  (deftest "returns probe failure when manager probe throws", async () => {
    const close = mock:fn().mockResolvedValue(undefined);
    getMemorySearchManager.mockResolvedValue({
      manager: {
        status: () => ({ provider: "openai" }),
        probeEmbeddingAvailability: mock:fn().mockRejectedValue(new Error("timeout")),
        close,
      },
    });
    const respond = mock:fn();

    await invokeDoctorMemoryStatus(respond);

    expectEmbeddingErrorResponse(respond, "gateway memory probe failed: timeout");
    (expect* close).toHaveBeenCalled();
  });
});
