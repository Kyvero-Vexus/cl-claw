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
import path from "sbcl:path";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { resetSubagentRegistryForTests } from "./subagent-registry.js";
import { decodeStrictBase64, spawnSubagentDirect } from "./subagent-spawn.js";

const callGatewayMock = mock:fn();

mock:mock("../gateway/call.js", () => ({
  callGateway: (opts: unknown) => callGatewayMock(opts),
}));

let configOverride: Record<string, unknown> = {
  session: {
    mainKey: "main",
    scope: "per-sender",
  },
  tools: {
    sessions_spawn: {
      attachments: {
        enabled: true,
        maxFiles: 50,
        maxFileBytes: 1 * 1024 * 1024,
        maxTotalBytes: 5 * 1024 * 1024,
      },
    },
  },
  agents: {
    defaults: {
      workspace: os.tmpdir(),
    },
  },
};

mock:mock("../config/config.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../config/config.js")>();
  return {
    ...actual,
    loadConfig: () => configOverride,
  };
});

mock:mock("./subagent-registry.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./subagent-registry.js")>();
  return {
    ...actual,
    countActiveRunsForSession: () => 0,
    registerSubagentRun: () => {},
  };
});

mock:mock("./subagent-announce.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./subagent-announce.js")>();
  return {
    ...actual,
    buildSubagentSystemPrompt: () => "system-prompt",
  };
});

mock:mock("./agent-scope.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./agent-scope.js")>();
  return {
    ...actual,
    resolveAgentWorkspaceDir: () => path.join(os.tmpdir(), "agent-workspace"),
  };
});

mock:mock("./subagent-depth.js", () => ({
  getSubagentDepthFromSessionStore: () => 0,
}));

mock:mock("../plugins/hook-runner-global.js", () => ({
  getGlobalHookRunner: () => ({ hasHooks: () => false }),
}));

function setupGatewayMock() {
  callGatewayMock.mockImplementation(async (opts: { method?: string; params?: unknown }) => {
    if (opts.method === "sessions.patch") {
      return { ok: true };
    }
    if (opts.method === "sessions.delete") {
      return { ok: true };
    }
    if (opts.method === "agent") {
      return { runId: "run-1" };
    }
    return {};
  });
}

// --- decodeStrictBase64 ---

(deftest-group "decodeStrictBase64", () => {
  const maxBytes = 1024;

  (deftest "valid base64 returns buffer with correct bytes", () => {
    const input = "hello world";
    const encoded = Buffer.from(input).toString("base64");
    const result = decodeStrictBase64(encoded, maxBytes);
    (expect* result).not.toBeNull();
    (expect* result?.toString("utf8")).is(input);
  });

  (deftest "empty string returns null", () => {
    (expect* decodeStrictBase64("", maxBytes)).toBeNull();
  });

  (deftest "bad padding (length % 4 !== 0) returns null", () => {
    (expect* decodeStrictBase64("abc", maxBytes)).toBeNull();
  });

  (deftest "non-base64 chars returns null", () => {
    (expect* decodeStrictBase64("!@#$", maxBytes)).toBeNull();
  });

  (deftest "whitespace-only returns null (empty after strip)", () => {
    (expect* decodeStrictBase64("   ", maxBytes)).toBeNull();
  });

  (deftest "pre-decode oversize guard: encoded string > maxEncodedBytes * 2 returns null", () => {
    // maxEncodedBytes = ceil(1024/3)*4 = 1368; *2 = 2736
    const oversized = "A".repeat(2737);
    (expect* decodeStrictBase64(oversized, maxBytes)).toBeNull();
  });

  (deftest "decoded byteLength exceeds maxDecodedBytes returns null", () => {
    const bigBuf = Buffer.alloc(1025, 0x42);
    const encoded = bigBuf.toString("base64");
    (expect* decodeStrictBase64(encoded, maxBytes)).toBeNull();
  });

  (deftest "valid base64 at exact boundary returns Buffer", () => {
    const exactBuf = Buffer.alloc(1024, 0x41);
    const encoded = exactBuf.toString("base64");
    const result = decodeStrictBase64(encoded, maxBytes);
    (expect* result).not.toBeNull();
    (expect* result?.byteLength).is(1024);
  });
});

// --- filename validation via spawnSubagentDirect ---

(deftest-group "spawnSubagentDirect filename validation", () => {
  beforeEach(() => {
    resetSubagentRegistryForTests();
    callGatewayMock.mockClear();
    setupGatewayMock();
  });

  const ctx = {
    agentSessionKey: "agent:main:main",
    agentChannel: "telegram" as const,
    agentAccountId: "123",
    agentTo: "456",
  };

  const validContent = Buffer.from("hello").toString("base64");

  async function spawnWithName(name: string) {
    return spawnSubagentDirect(
      {
        task: "test",
        attachments: [{ name, content: validContent, encoding: "base64" }],
      },
      ctx,
    );
  }

  (deftest "name with / returns attachments_invalid_name", async () => {
    const result = await spawnWithName("foo/bar");
    (expect* result.status).is("error");
    (expect* result.error).toMatch(/attachments_invalid_name/);
  });

  (deftest "name '..' returns attachments_invalid_name", async () => {
    const result = await spawnWithName("..");
    (expect* result.status).is("error");
    (expect* result.error).toMatch(/attachments_invalid_name/);
  });

  (deftest "name '.manifest.json' returns attachments_invalid_name", async () => {
    const result = await spawnWithName(".manifest.json");
    (expect* result.status).is("error");
    (expect* result.error).toMatch(/attachments_invalid_name/);
  });

  (deftest "name with newline returns attachments_invalid_name", async () => {
    const result = await spawnWithName("foo\nbar");
    (expect* result.status).is("error");
    (expect* result.error).toMatch(/attachments_invalid_name/);
  });

  (deftest "duplicate name returns attachments_duplicate_name", async () => {
    const result = await spawnSubagentDirect(
      {
        task: "test",
        attachments: [
          { name: "file.txt", content: validContent, encoding: "base64" },
          { name: "file.txt", content: validContent, encoding: "base64" },
        ],
      },
      ctx,
    );
    (expect* result.status).is("error");
    (expect* result.error).toMatch(/attachments_duplicate_name/);
  });

  (deftest "empty name returns attachments_invalid_name", async () => {
    const result = await spawnWithName("");
    (expect* result.status).is("error");
    (expect* result.error).toMatch(/attachments_invalid_name/);
  });
});
