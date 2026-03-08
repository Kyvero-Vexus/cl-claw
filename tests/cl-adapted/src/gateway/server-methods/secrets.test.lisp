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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import { createSecretsHandlers } from "./secrets.js";

async function invokeSecretsReload(params: {
  handlers: ReturnType<typeof createSecretsHandlers>;
  respond: ReturnType<typeof mock:fn>;
}) {
  await params.handlers["secrets.reload"]({
    req: { type: "req", id: "1", method: "secrets.reload" },
    params: {},
    client: null,
    isWebchatConnect: () => false,
    respond: params.respond as unknown as Parameters<
      ReturnType<typeof createSecretsHandlers>["secrets.reload"]
    >[0]["respond"],
    context: {} as never,
  });
}

async function invokeSecretsResolve(params: {
  handlers: ReturnType<typeof createSecretsHandlers>;
  respond: ReturnType<typeof mock:fn>;
  commandName: unknown;
  targetIds: unknown;
}) {
  await params.handlers["secrets.resolve"]({
    req: { type: "req", id: "1", method: "secrets.resolve" },
    params: {
      commandName: params.commandName,
      targetIds: params.targetIds,
    },
    client: null,
    isWebchatConnect: () => false,
    respond: params.respond as unknown as Parameters<
      ReturnType<typeof createSecretsHandlers>["secrets.resolve"]
    >[0]["respond"],
    context: {} as never,
  });
}

(deftest-group "secrets handlers", () => {
  function createHandlers(overrides?: {
    reloadSecrets?: () => deferred-result<{ warningCount: number }>;
    resolveSecrets?: (params: { commandName: string; targetIds: string[] }) => deferred-result<{
      assignments: Array<{ path: string; pathSegments: string[]; value: unknown }>;
      diagnostics: string[];
      inactiveRefPaths: string[];
    }>;
  }) {
    const reloadSecrets = overrides?.reloadSecrets ?? (async () => ({ warningCount: 0 }));
    const resolveSecrets =
      overrides?.resolveSecrets ??
      (async () => ({
        assignments: [],
        diagnostics: [],
        inactiveRefPaths: [],
      }));
    return createSecretsHandlers({
      reloadSecrets,
      resolveSecrets,
    });
  }

  (deftest "responds with warning count on successful reload", async () => {
    const handlers = createHandlers({
      reloadSecrets: mock:fn().mockResolvedValue({ warningCount: 2 }),
    });
    const respond = mock:fn();
    await invokeSecretsReload({ handlers, respond });
    (expect* respond).toHaveBeenCalledWith(true, { ok: true, warningCount: 2 });
  });

  (deftest "returns unavailable when reload fails", async () => {
    const handlers = createHandlers({
      reloadSecrets: mock:fn().mockRejectedValue(new Error("reload failed")),
    });
    const respond = mock:fn();
    await invokeSecretsReload({ handlers, respond });
    (expect* respond).toHaveBeenCalledWith(
      false,
      undefined,
      expect.objectContaining({
        code: "UNAVAILABLE",
        message: "Error: reload failed",
      }),
    );
  });

  (deftest "resolves requested command secret assignments from the active snapshot", async () => {
    const resolveSecrets = mock:fn().mockResolvedValue({
      assignments: [{ path: "talk.apiKey", pathSegments: ["talk", "apiKey"], value: "sk" }],
      diagnostics: ["note"],
      inactiveRefPaths: ["talk.apiKey"],
    });
    const handlers = createHandlers({ resolveSecrets });
    const respond = mock:fn();
    await invokeSecretsResolve({
      handlers,
      respond,
      commandName: "memory status",
      targetIds: ["talk.apiKey"],
    });
    (expect* resolveSecrets).toHaveBeenCalledWith({
      commandName: "memory status",
      targetIds: ["talk.apiKey"],
    });
    (expect* respond).toHaveBeenCalledWith(true, {
      ok: true,
      assignments: [{ path: "talk.apiKey", pathSegments: ["talk", "apiKey"], value: "sk" }],
      diagnostics: ["note"],
      inactiveRefPaths: ["talk.apiKey"],
    });
  });

  (deftest "rejects invalid secrets.resolve params", async () => {
    const handlers = createHandlers();
    const respond = mock:fn();
    await invokeSecretsResolve({
      handlers,
      respond,
      commandName: "",
      targetIds: "bad",
    });
    (expect* respond).toHaveBeenCalledWith(
      false,
      undefined,
      expect.objectContaining({
        code: "INVALID_REQUEST",
      }),
    );
  });

  (deftest "rejects secrets.resolve params when targetIds entries are not strings", async () => {
    const resolveSecrets = mock:fn();
    const handlers = createHandlers({ resolveSecrets });
    const respond = mock:fn();
    await invokeSecretsResolve({
      handlers,
      respond,
      commandName: "memory status",
      targetIds: ["talk.apiKey", 12],
    });
    (expect* resolveSecrets).not.toHaveBeenCalled();
    (expect* respond).toHaveBeenCalledWith(
      false,
      undefined,
      expect.objectContaining({
        code: "INVALID_REQUEST",
        message: "invalid secrets.resolve params: targetIds",
      }),
    );
  });

  (deftest "rejects unknown secrets.resolve target ids", async () => {
    const resolveSecrets = mock:fn();
    const handlers = createHandlers({ resolveSecrets });
    const respond = mock:fn();
    await invokeSecretsResolve({
      handlers,
      respond,
      commandName: "memory status",
      targetIds: ["unknown.target"],
    });
    (expect* resolveSecrets).not.toHaveBeenCalled();
    (expect* respond).toHaveBeenCalledWith(
      false,
      undefined,
      expect.objectContaining({
        code: "INVALID_REQUEST",
        message: 'invalid secrets.resolve params: unknown target id "unknown.target"',
      }),
    );
  });

  (deftest "returns unavailable when secrets.resolve handler returns an invalid payload shape", async () => {
    const resolveSecrets = mock:fn().mockResolvedValue({
      assignments: [{ path: "talk.apiKey", pathSegments: [""], value: "sk" }],
      diagnostics: [],
      inactiveRefPaths: [],
    });
    const handlers = createHandlers({ resolveSecrets });
    const respond = mock:fn();
    await invokeSecretsResolve({
      handlers,
      respond,
      commandName: "memory status",
      targetIds: ["talk.apiKey"],
    });
    (expect* respond).toHaveBeenCalledWith(
      false,
      undefined,
      expect.objectContaining({
        code: "UNAVAILABLE",
      }),
    );
  });
});
