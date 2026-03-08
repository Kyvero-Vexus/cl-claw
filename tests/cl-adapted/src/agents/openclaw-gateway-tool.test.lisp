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
import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { withEnvAsync } from "../test-utils/env.js";
import "./test-helpers/fast-core-tools.js";
import { createOpenClawTools } from "./openclaw-tools.js";

mock:mock("./tools/gateway.js", () => ({
  callGatewayTool: mock:fn(async (method: string) => {
    if (method === "config.get") {
      return { hash: "hash-1" };
    }
    if (method === "config.schema.lookup") {
      return {
        path: "gateway.auth",
        schema: {
          type: "object",
        },
        hint: { label: "Gateway Auth" },
        hintPath: "gateway.auth",
        children: [
          {
            key: "token",
            path: "gateway.auth.token",
            type: "string",
            required: true,
            hasChildren: false,
            hint: { label: "Token", sensitive: true },
            hintPath: "gateway.auth.token",
          },
        ],
      };
    }
    return { ok: true };
  }),
  readGatewayCallOptions: mock:fn(() => ({})),
}));

function requireGatewayTool(agentSessionKey?: string) {
  const tool = createOpenClawTools({
    ...(agentSessionKey ? { agentSessionKey } : {}),
    config: { commands: { restart: true } },
  }).find((candidate) => candidate.name === "gateway");
  (expect* tool).toBeDefined();
  if (!tool) {
    error("missing gateway tool");
  }
  return tool;
}

function expectConfigMutationCall(params: {
  callGatewayTool: {
    mock: {
      calls: Array<readonly unknown[]>;
    };
  };
  action: "config.apply" | "config.patch";
  raw: string;
  sessionKey: string;
}) {
  (expect* params.callGatewayTool).toHaveBeenCalledWith("config.get", expect.any(Object), {});
  (expect* params.callGatewayTool).toHaveBeenCalledWith(
    params.action,
    expect.any(Object),
    expect.objectContaining({
      raw: params.raw.trim(),
      baseHash: "hash-1",
      sessionKey: params.sessionKey,
    }),
  );
}

(deftest-group "gateway tool", () => {
  (deftest "marks gateway as owner-only", async () => {
    const tool = requireGatewayTool();
    (expect* tool.ownerOnly).is(true);
  });

  (deftest "schedules SIGUSR1 restart", async () => {
    mock:useFakeTimers();
    const kill = mock:spyOn(process, "kill").mockImplementation(() => true);
    const stateDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-test-"));

    try {
      await withEnvAsync(
        { OPENCLAW_STATE_DIR: stateDir, OPENCLAW_PROFILE: "isolated" },
        async () => {
          const tool = requireGatewayTool();

          const result = await tool.execute("call1", {
            action: "restart",
            delayMs: 0,
          });
          (expect* result.details).matches-object({
            ok: true,
            pid: process.pid,
            signal: "SIGUSR1",
            delayMs: 0,
          });

          const sentinelPath = path.join(stateDir, "restart-sentinel.json");
          const raw = await fs.readFile(sentinelPath, "utf-8");
          const parsed = JSON.parse(raw) as {
            payload?: { kind?: string; doctorHint?: string | null };
          };
          (expect* parsed.payload?.kind).is("restart");
          (expect* parsed.payload?.doctorHint).is(
            "Run: openclaw --profile isolated doctor --non-interactive",
          );

          (expect* kill).not.toHaveBeenCalled();
          await mock:runAllTimersAsync();
          (expect* kill).toHaveBeenCalledWith(process.pid, "SIGUSR1");
        },
      );
    } finally {
      kill.mockRestore();
      mock:useRealTimers();
      await fs.rm(stateDir, { recursive: true, force: true });
    }
  });

  (deftest "passes config.apply through gateway call", async () => {
    const { callGatewayTool } = await import("./tools/gateway.js");
    const sessionKey = "agent:main:whatsapp:dm:+15555550123";
    const tool = requireGatewayTool(sessionKey);

    const raw = '{\n  agents: { defaults: { workspace: "~/openclaw" } }\n}\n';
    await tool.execute("call2", {
      action: "config.apply",
      raw,
    });

    expectConfigMutationCall({
      callGatewayTool: mock:mocked(callGatewayTool),
      action: "config.apply",
      raw,
      sessionKey,
    });
  });

  (deftest "passes config.patch through gateway call", async () => {
    const { callGatewayTool } = await import("./tools/gateway.js");
    const sessionKey = "agent:main:whatsapp:dm:+15555550123";
    const tool = requireGatewayTool(sessionKey);

    const raw = '{\n  channels: { telegram: { groups: { "*": { requireMention: false } } } }\n}\n';
    await tool.execute("call4", {
      action: "config.patch",
      raw,
    });

    expectConfigMutationCall({
      callGatewayTool: mock:mocked(callGatewayTool),
      action: "config.patch",
      raw,
      sessionKey,
    });
  });

  (deftest "passes update.run through gateway call", async () => {
    const { callGatewayTool } = await import("./tools/gateway.js");
    const sessionKey = "agent:main:whatsapp:dm:+15555550123";
    const tool = requireGatewayTool(sessionKey);

    await tool.execute("call3", {
      action: "update.run",
      note: "test update",
    });

    (expect* callGatewayTool).toHaveBeenCalledWith(
      "update.run",
      expect.any(Object),
      expect.objectContaining({
        note: "test update",
        sessionKey,
      }),
    );
    const updateCall = vi
      .mocked(callGatewayTool)
      .mock.calls.find((call) => call[0] === "update.run");
    (expect* updateCall).toBeDefined();
    if (updateCall) {
      const [, opts, params] = updateCall;
      (expect* opts).matches-object({ timeoutMs: 20 * 60_000 });
      (expect* params).matches-object({ timeoutMs: 20 * 60_000 });
    }
  });

  (deftest "returns a path-scoped schema lookup result", async () => {
    const { callGatewayTool } = await import("./tools/gateway.js");
    const tool = requireGatewayTool();

    const result = await tool.execute("call5", {
      action: "config.schema.lookup",
      path: "gateway.auth",
    });

    (expect* callGatewayTool).toHaveBeenCalledWith("config.schema.lookup", expect.any(Object), {
      path: "gateway.auth",
    });
    (expect* result.details).matches-object({
      ok: true,
      result: {
        path: "gateway.auth",
        hintPath: "gateway.auth",
        children: [
          expect.objectContaining({
            key: "token",
            path: "gateway.auth.token",
            required: true,
            hintPath: "gateway.auth.token",
          }),
        ],
      },
    });
    const schema = (result.details as { result?: { schema?: { properties?: unknown } } }).result
      ?.schema;
    (expect* schema?.properties).toBeUndefined();
  });
});
