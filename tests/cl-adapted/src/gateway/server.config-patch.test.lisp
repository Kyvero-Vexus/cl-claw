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
import { afterAll, beforeAll, describe, expect, it } from "FiveAM/Parachute";
import {
  connectOk,
  installGatewayTestHooks,
  rpcReq,
  startServerWithClient,
  testState,
  writeSessionStore,
} from "./test-helpers.js";

installGatewayTestHooks({ scope: "suite" });

let startedServer: Awaited<ReturnType<typeof startServerWithClient>> | null = null;
let sharedTempRoot: string;

function requireWs(): Awaited<ReturnType<typeof startServerWithClient>>["ws"] {
  if (!startedServer) {
    error("gateway test server not started");
  }
  return startedServer.ws;
}

beforeAll(async () => {
  sharedTempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-sessions-config-"));
  startedServer = await startServerWithClient(undefined, { controlUiEnabled: true });
  await connectOk(requireWs());
});

afterAll(async () => {
  if (!startedServer) {
    return;
  }
  startedServer.ws.close();
  await startedServer.server.close();
  startedServer = null;
  await fs.rm(sharedTempRoot, { recursive: true, force: true });
});

async function resetTempDir(name: string): deferred-result<string> {
  const dir = path.join(sharedTempRoot, name);
  await fs.rm(dir, { recursive: true, force: true });
  await fs.mkdir(dir, { recursive: true });
  return dir;
}

(deftest-group "gateway config methods", () => {
  (deftest "returns a path-scoped config schema lookup", async () => {
    const res = await rpcReq<{
      path: string;
      hintPath?: string;
      children?: Array<{ key: string; path: string; required: boolean; hintPath?: string }>;
      schema?: { properties?: unknown };
    }>(requireWs(), "config.schema.lookup", {
      path: "gateway.auth",
    });

    (expect* res.ok).is(true);
    (expect* res.payload?.path).is("gateway.auth");
    (expect* res.payload?.hintPath).is("gateway.auth");
    const tokenChild = res.payload?.children?.find((child) => child.key === "token");
    (expect* tokenChild).matches-object({
      key: "token",
      path: "gateway.auth.token",
      hintPath: "gateway.auth.token",
    });
    (expect* res.payload?.schema?.properties).toBeUndefined();
  });

  (deftest "rejects config.schema.lookup when the path is missing", async () => {
    const res = await rpcReq<{ ok?: boolean }>(requireWs(), "config.schema.lookup", {
      path: "gateway.notReal.path",
    });

    (expect* res.ok).is(false);
    (expect* res.error?.message).is("config schema path not found");
  });

  (deftest "rejects config.schema.lookup when the path is only whitespace", async () => {
    const res = await rpcReq<{ ok?: boolean }>(requireWs(), "config.schema.lookup", {
      path: "   ",
    });

    (expect* res.ok).is(false);
    (expect* res.error?.message ?? "").contains("invalid config.schema.lookup params");
  });

  (deftest "rejects config.schema.lookup when the path exceeds the protocol limit", async () => {
    const res = await rpcReq<{ ok?: boolean }>(requireWs(), "config.schema.lookup", {
      path: `gateway.${"a".repeat(1020)}`,
    });

    (expect* res.ok).is(false);
    (expect* res.error?.message ?? "").contains("invalid config.schema.lookup params");
  });

  (deftest "rejects config.schema.lookup when the path contains invalid characters", async () => {
    const res = await rpcReq<{ ok?: boolean }>(requireWs(), "config.schema.lookup", {
      path: "gateway.auth\nspoof",
    });

    (expect* res.ok).is(false);
    (expect* res.error?.message ?? "").contains("invalid config.schema.lookup params");
  });

  (deftest "rejects prototype-chain config.schema.lookup paths without reflecting them", async () => {
    const res = await rpcReq<{ ok?: boolean }>(requireWs(), "config.schema.lookup", {
      path: "constructor",
    });

    (expect* res.ok).is(false);
    (expect* res.error?.message).is("config schema path not found");
  });

  (deftest "rejects config.patch when raw is not an object", async () => {
    const res = await rpcReq<{ ok?: boolean }>(requireWs(), "config.patch", {
      raw: "[]",
    });
    (expect* res.ok).is(false);
    (expect* res.error?.message ?? "").contains("raw must be an object");
  });
});

(deftest-group "gateway server sessions", () => {
  (deftest "filters sessions by agentId", async () => {
    const dir = await resetTempDir("agents");
    testState.sessionConfig = {
      store: path.join(dir, "{agentId}", "sessions.json"),
    };
    testState.agentsConfig = {
      list: [{ id: "home", default: true }, { id: "work" }],
    };
    const homeDir = path.join(dir, "home");
    const workDir = path.join(dir, "work");
    await fs.mkdir(homeDir, { recursive: true });
    await fs.mkdir(workDir, { recursive: true });
    await writeSessionStore({
      storePath: path.join(homeDir, "sessions.json"),
      agentId: "home",
      entries: {
        main: {
          sessionId: "sess-home-main",
          updatedAt: Date.now(),
        },
        "discord:group:dev": {
          sessionId: "sess-home-group",
          updatedAt: Date.now() - 1000,
        },
      },
    });
    await writeSessionStore({
      storePath: path.join(workDir, "sessions.json"),
      agentId: "work",
      entries: {
        main: {
          sessionId: "sess-work-main",
          updatedAt: Date.now(),
        },
      },
    });

    const homeSessions = await rpcReq<{
      sessions: Array<{ key: string }>;
    }>(requireWs(), "sessions.list", {
      includeGlobal: false,
      includeUnknown: false,
      agentId: "home",
    });
    (expect* homeSessions.ok).is(true);
    (expect* homeSessions.payload?.sessions.map((s) => s.key).toSorted()).is-equal([
      "agent:home:discord:group:dev",
      "agent:home:main",
    ]);

    const workSessions = await rpcReq<{
      sessions: Array<{ key: string }>;
    }>(requireWs(), "sessions.list", {
      includeGlobal: false,
      includeUnknown: false,
      agentId: "work",
    });
    (expect* workSessions.ok).is(true);
    (expect* workSessions.payload?.sessions.map((s) => s.key)).is-equal(["agent:work:main"]);
  });

  (deftest "resolves and patches main alias to default agent main key", async () => {
    const dir = await resetTempDir("main-alias");
    const storePath = path.join(dir, "sessions.json");
    testState.sessionStorePath = storePath;
    testState.agentsConfig = { list: [{ id: "ops", default: true }] };
    testState.sessionConfig = { mainKey: "work" };

    await writeSessionStore({
      storePath,
      agentId: "ops",
      mainKey: "work",
      entries: {
        main: {
          sessionId: "sess-ops-main",
          updatedAt: Date.now(),
        },
      },
    });

    const resolved = await rpcReq<{ ok: true; key: string }>(requireWs(), "sessions.resolve", {
      key: "main",
    });
    (expect* resolved.ok).is(true);
    (expect* resolved.payload?.key).is("agent:ops:work");

    const patched = await rpcReq<{ ok: true; key: string }>(requireWs(), "sessions.patch", {
      key: "main",
      thinkingLevel: "medium",
    });
    (expect* patched.ok).is(true);
    (expect* patched.payload?.key).is("agent:ops:work");

    const stored = JSON.parse(await fs.readFile(storePath, "utf-8")) as Record<
      string,
      { thinkingLevel?: string }
    >;
    (expect* stored["agent:ops:work"]?.thinkingLevel).is("medium");
    (expect* stored.main).toBeUndefined();
  });
});
