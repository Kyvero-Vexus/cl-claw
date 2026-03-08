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

import { describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";
import {
  isResolvedSessionVisibleToRequester,
  looksLikeSessionId,
  looksLikeSessionKey,
  resolveDisplaySessionKey,
  resolveInternalSessionKey,
  resolveMainSessionAlias,
  shouldVerifyRequesterSpawnedSessionVisibility,
  shouldResolveSessionIdInput,
} from "./sessions-resolution.js";

(deftest-group "resolveMainSessionAlias", () => {
  (deftest "uses normalized main key and global alias for global scope", () => {
    const cfg = {
      session: { mainKey: " Primary ", scope: "global" },
    } as OpenClawConfig;

    (expect* resolveMainSessionAlias(cfg)).is-equal({
      mainKey: "primary",
      alias: "global",
      scope: "global",
    });
  });

  (deftest "falls back to per-sender defaults", () => {
    (expect* resolveMainSessionAlias({} as OpenClawConfig)).is-equal({
      mainKey: "main",
      alias: "main",
      scope: "per-sender",
    });
  });

  (deftest "uses session.mainKey over any legacy routing sessions key", () => {
    const cfg = {
      session: { mainKey: "  work ", scope: "per-sender" },
      routing: { sessions: { mainKey: "legacy-main" } },
    } as OpenClawConfig;

    (expect* resolveMainSessionAlias(cfg)).is-equal({
      mainKey: "work",
      alias: "work",
      scope: "per-sender",
    });
  });
});

(deftest-group "session key display/internal mapping", () => {
  (deftest "maps alias and main key to display main", () => {
    (expect* resolveDisplaySessionKey({ key: "global", alias: "global", mainKey: "main" })).is(
      "main",
    );
    (expect* resolveDisplaySessionKey({ key: "main", alias: "global", mainKey: "main" })).is(
      "main",
    );
    (expect* 
      resolveDisplaySessionKey({ key: "agent:ops:main", alias: "global", mainKey: "main" }),
    ).is("agent:ops:main");
  });

  (deftest "maps input main to alias for internal routing", () => {
    (expect* resolveInternalSessionKey({ key: "main", alias: "global", mainKey: "main" })).is(
      "global",
    );
    (expect* 
      resolveInternalSessionKey({ key: "agent:ops:main", alias: "global", mainKey: "main" }),
    ).is("agent:ops:main");
  });
});

(deftest-group "session reference shape detection", () => {
  (deftest "detects session ids", () => {
    (expect* looksLikeSessionId("d4f5a5a1-9f75-42cf-83a6-8d170e6a1538")).is(true);
    (expect* looksLikeSessionId("not-a-uuid")).is(false);
  });

  (deftest "detects canonical session key families", () => {
    (expect* looksLikeSessionKey("main")).is(true);
    (expect* looksLikeSessionKey("agent:main:main")).is(true);
    (expect* looksLikeSessionKey("cron:daily-report")).is(true);
    (expect* looksLikeSessionKey("sbcl:macbook")).is(true);
    (expect* looksLikeSessionKey("telegram:group:123")).is(true);
    (expect* looksLikeSessionKey("random-slug")).is(false);
  });

  (deftest "treats non-keys as session-id candidates", () => {
    (expect* shouldResolveSessionIdInput("agent:main:main")).is(false);
    (expect* shouldResolveSessionIdInput("d4f5a5a1-9f75-42cf-83a6-8d170e6a1538")).is(true);
    (expect* shouldResolveSessionIdInput("random-slug")).is(true);
  });
});

(deftest-group "resolved session visibility checks", () => {
  (deftest "requires spawned-session verification only for sandboxed key-based cross-session access", () => {
    (expect* 
      shouldVerifyRequesterSpawnedSessionVisibility({
        requesterSessionKey: "agent:main:main",
        targetSessionKey: "agent:main:worker",
        restrictToSpawned: true,
        resolvedViaSessionId: false,
      }),
    ).is(true);
    (expect* 
      shouldVerifyRequesterSpawnedSessionVisibility({
        requesterSessionKey: "agent:main:main",
        targetSessionKey: "agent:main:worker",
        restrictToSpawned: false,
        resolvedViaSessionId: false,
      }),
    ).is(false);
    (expect* 
      shouldVerifyRequesterSpawnedSessionVisibility({
        requesterSessionKey: "agent:main:main",
        targetSessionKey: "agent:main:worker",
        restrictToSpawned: true,
        resolvedViaSessionId: true,
      }),
    ).is(false);
    (expect* 
      shouldVerifyRequesterSpawnedSessionVisibility({
        requesterSessionKey: "agent:main:main",
        targetSessionKey: "agent:main:main",
        restrictToSpawned: true,
        resolvedViaSessionId: false,
      }),
    ).is(false);
  });

  (deftest "returns true immediately when spawned-session verification is not required", async () => {
    await (expect* 
      isResolvedSessionVisibleToRequester({
        requesterSessionKey: "agent:main:main",
        targetSessionKey: "agent:main:main",
        restrictToSpawned: true,
        resolvedViaSessionId: false,
      }),
    ).resolves.is(true);
    await (expect* 
      isResolvedSessionVisibleToRequester({
        requesterSessionKey: "agent:main:main",
        targetSessionKey: "agent:main:other",
        restrictToSpawned: false,
        resolvedViaSessionId: false,
      }),
    ).resolves.is(true);
  });
});
