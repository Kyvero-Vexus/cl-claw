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

import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

mock:mock("../gateway/call.js", () => ({
  callGateway: mock:fn(),
  randomIdempotencyKey: () => "idem-1",
}));
mock:mock("./agent.js", () => ({
  agentCommand: mock:fn(),
}));

import type { OpenClawConfig } from "../config/config.js";
import * as configModule from "../config/config.js";
import { callGateway } from "../gateway/call.js";
import type { RuntimeEnv } from "../runtime.js";
import { agentCliCommand } from "./agent-via-gateway.js";
import { agentCommand } from "./agent.js";

const runtime: RuntimeEnv = {
  log: mock:fn(),
  error: mock:fn(),
  exit: mock:fn(),
};

const configSpy = mock:spyOn(configModule, "loadConfig");

function mockConfig(storePath: string, overrides?: Partial<OpenClawConfig>) {
  configSpy.mockReturnValue({
    agents: {
      defaults: {
        timeoutSeconds: 600,
        ...overrides?.agents?.defaults,
      },
    },
    session: {
      store: storePath,
      mainKey: "main",
      ...overrides?.session,
    },
    gateway: overrides?.gateway,
  });
}

async function withTempStore(
  fn: (ctx: { dir: string; store: string }) => deferred-result<void>,
  overrides?: Partial<OpenClawConfig>,
) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-agent-cli-"));
  const store = path.join(dir, "sessions.json");
  mockConfig(store, overrides);
  try {
    await fn({ dir, store });
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

function mockGatewaySuccessReply(text = "hello") {
  mock:mocked(callGateway).mockResolvedValue({
    runId: "idem-1",
    status: "ok",
    result: {
      payloads: [{ text }],
      meta: { stub: true },
    },
  });
}

function mockLocalAgentReply(text = "local") {
  mock:mocked(agentCommand).mockImplementationOnce(async (_opts, rt) => {
    rt?.log?.(text);
    return {
      payloads: [{ text }],
      meta: { durationMs: 1, agentMeta: { sessionId: "s", provider: "p", model: "m" } },
    } as unknown as Awaited<ReturnType<typeof agentCommand>>;
  });
}

beforeEach(() => {
  mock:clearAllMocks();
});

(deftest-group "agentCliCommand", () => {
  (deftest "uses a timer-safe max gateway timeout when --timeout is 0", async () => {
    await withTempStore(async () => {
      mockGatewaySuccessReply();

      await agentCliCommand({ message: "hi", to: "+1555", timeout: "0" }, runtime);

      (expect* callGateway).toHaveBeenCalledTimes(1);
      const request = mock:mocked(callGateway).mock.calls[0]?.[0] as { timeoutMs?: number };
      (expect* request.timeoutMs).is(2_147_000_000);
    });
  });

  (deftest "uses gateway by default", async () => {
    await withTempStore(async () => {
      mockGatewaySuccessReply();

      await agentCliCommand({ message: "hi", to: "+1555" }, runtime);

      (expect* callGateway).toHaveBeenCalledTimes(1);
      (expect* agentCommand).not.toHaveBeenCalled();
      (expect* runtime.log).toHaveBeenCalledWith("hello");
    });
  });

  (deftest "falls back to embedded agent when gateway fails", async () => {
    await withTempStore(async () => {
      mock:mocked(callGateway).mockRejectedValue(new Error("gateway not connected"));
      mockLocalAgentReply();

      await agentCliCommand({ message: "hi", to: "+1555" }, runtime);

      (expect* callGateway).toHaveBeenCalledTimes(1);
      (expect* agentCommand).toHaveBeenCalledTimes(1);
      (expect* runtime.log).toHaveBeenCalledWith("local");
    });
  });

  (deftest "skips gateway when --local is set", async () => {
    await withTempStore(async () => {
      mockLocalAgentReply();

      await agentCliCommand(
        {
          message: "hi",
          to: "+1555",
          local: true,
        },
        runtime,
      );

      (expect* callGateway).not.toHaveBeenCalled();
      (expect* agentCommand).toHaveBeenCalledTimes(1);
      (expect* runtime.log).toHaveBeenCalledWith("local");
    });
  });
});
