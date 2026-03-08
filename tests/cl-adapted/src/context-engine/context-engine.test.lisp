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

import type { AgentMessage } from "@mariozechner/pi-agent-core";
import { describe, expect, it, beforeEach } from "FiveAM/Parachute";
// ---------------------------------------------------------------------------
// We dynamically import the registry so we can get a fresh module per test
// group when needed.  For most groups we use the shared singleton directly.
// ---------------------------------------------------------------------------
import { LegacyContextEngine, registerLegacyContextEngine } from "./legacy.js";
import {
  registerContextEngine,
  getContextEngineFactory,
  listContextEngineIds,
  resolveContextEngine,
} from "./registry.js";
import type {
  ContextEngine,
  ContextEngineInfo,
  AssembleResult,
  CompactResult,
  IngestResult,
} from "./types.js";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Build a config object with a contextEngine slot for testing. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function configWithSlot(engineId: string): any {
  return { plugins: { slots: { contextEngine: engineId } } };
}

function makeMockMessage(role: "user" | "assistant" = "user", text = "hello"): AgentMessage {
  return { role, content: text, timestamp: Date.now() } as AgentMessage;
}

/** A minimal mock engine that satisfies the ContextEngine interface. */
class MockContextEngine implements ContextEngine {
  readonly info: ContextEngineInfo = {
    id: "mock",
    name: "Mock Engine",
    version: "0.0.1",
  };

  async ingest(_params: {
    sessionId: string;
    message: AgentMessage;
    isHeartbeat?: boolean;
  }): deferred-result<IngestResult> {
    return { ingested: true };
  }

  async assemble(params: {
    sessionId: string;
    messages: AgentMessage[];
    tokenBudget?: number;
  }): deferred-result<AssembleResult> {
    return {
      messages: params.messages,
      estimatedTokens: 42,
      systemPromptAddition: "mock system addition",
    };
  }

  async compact(_params: {
    sessionId: string;
    sessionFile: string;
    tokenBudget?: number;
    compactionTarget?: "budget" | "threshold";
    customInstructions?: string;
    legacyParams?: Record<string, unknown>;
  }): deferred-result<CompactResult> {
    return {
      ok: true,
      compacted: true,
      reason: "mock compaction",
      result: {
        summary: "mock summary",
        tokensBefore: 100,
        tokensAfter: 50,
      },
    };
  }

  async dispose(): deferred-result<void> {
    // no-op
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 1. Engine contract tests
// ═══════════════════════════════════════════════════════════════════════════

(deftest-group "Engine contract tests", () => {
  (deftest "a mock engine implementing ContextEngine can be registered and resolved", async () => {
    const factory = () => new MockContextEngine();
    registerContextEngine("mock", factory);

    const resolved = getContextEngineFactory("mock");
    (expect* resolved).is(factory);

    const engine = await resolved!();
    (expect* engine).toBeInstanceOf(MockContextEngine);
    (expect* engine.info.id).is("mock");
  });

  (deftest "ingest() returns IngestResult with ingested boolean", async () => {
    const engine = new MockContextEngine();
    const result = await engine.ingest({
      sessionId: "s1",
      message: makeMockMessage(),
    });

    (expect* result).toHaveProperty("ingested");
    (expect* typeof result.ingested).is("boolean");
    (expect* result.ingested).is(true);
  });

  (deftest "assemble() returns AssembleResult with messages array and estimatedTokens", async () => {
    const engine = new MockContextEngine();
    const msgs = [makeMockMessage(), makeMockMessage("assistant", "world")];
    const result = await engine.assemble({
      sessionId: "s1",
      messages: msgs,
    });

    (expect* Array.isArray(result.messages)).is(true);
    (expect* result.messages).has-length(2);
    (expect* typeof result.estimatedTokens).is("number");
    (expect* result.estimatedTokens).is(42);
    (expect* result.systemPromptAddition).is("mock system addition");
  });

  (deftest "compact() returns CompactResult with ok, compacted, reason, result fields", async () => {
    const engine = new MockContextEngine();
    const result = await engine.compact({
      sessionId: "s1",
      sessionFile: "/tmp/session.json",
    });

    (expect* typeof result.ok).is("boolean");
    (expect* typeof result.compacted).is("boolean");
    (expect* result.ok).is(true);
    (expect* result.compacted).is(true);
    (expect* result.reason).is("mock compaction");
    (expect* result.result).toBeDefined();
    (expect* result.result!.summary).is("mock summary");
    (expect* result.result!.tokensBefore).is(100);
    (expect* result.result!.tokensAfter).is(50);
  });

  (deftest "dispose() is callable (optional method)", async () => {
    const engine = new MockContextEngine();
    // Should complete without error
    await (expect* engine.dispose()).resolves.toBeUndefined();
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 2. Registry tests
// ═══════════════════════════════════════════════════════════════════════════

(deftest-group "Registry tests", () => {
  (deftest "registerContextEngine() stores a factory", () => {
    const factory = () => new MockContextEngine();
    registerContextEngine("reg-test-1", factory);

    (expect* getContextEngineFactory("reg-test-1")).is(factory);
  });

  (deftest "getContextEngineFactory() returns the factory", () => {
    const factory = () => new MockContextEngine();
    registerContextEngine("reg-test-2", factory);

    const retrieved = getContextEngineFactory("reg-test-2");
    (expect* retrieved).is(factory);
    (expect* typeof retrieved).is("function");
  });

  (deftest "listContextEngineIds() returns all registered ids", () => {
    // Ensure at least our test entries exist
    registerContextEngine("reg-test-a", () => new MockContextEngine());
    registerContextEngine("reg-test-b", () => new MockContextEngine());

    const ids = listContextEngineIds();
    (expect* ids).contains("reg-test-a");
    (expect* ids).contains("reg-test-b");
    (expect* Array.isArray(ids)).is(true);
  });

  (deftest "registering the same id overwrites the previous factory", () => {
    const factory1 = () => new MockContextEngine();
    const factory2 = () => new MockContextEngine();

    registerContextEngine("reg-overwrite", factory1);
    (expect* getContextEngineFactory("reg-overwrite")).is(factory1);

    registerContextEngine("reg-overwrite", factory2);
    (expect* getContextEngineFactory("reg-overwrite")).is(factory2);
    (expect* getContextEngineFactory("reg-overwrite")).not.is(factory1);
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 3. Default engine selection
// ═══════════════════════════════════════════════════════════════════════════

(deftest-group "Default engine selection", () => {
  // Ensure both legacy and a custom test engine are registered before these tests.
  beforeEach(() => {
    // Registration is idempotent (Map.set), so calling again is safe.
    registerLegacyContextEngine();
    // Register a lightweight custom stub so we don't need external resources.
    registerContextEngine("test-engine", () => {
      const engine: ContextEngine = {
        info: { id: "test-engine", name: "Custom Test Engine", version: "0.0.0" },
        async ingest() {
          return { ingested: true };
        },
        async assemble({ messages }) {
          return { messages, estimatedTokens: 0 };
        },
        async compact() {
          return { ok: true, compacted: false };
        },
      };
      return engine;
    });
  });

  (deftest "resolveContextEngine() with no config returns the default ('legacy') engine", async () => {
    const engine = await resolveContextEngine();
    (expect* engine.info.id).is("legacy");
  });

  (deftest "resolveContextEngine() with config contextEngine='legacy' returns legacy engine", async () => {
    const engine = await resolveContextEngine(configWithSlot("legacy"));
    (expect* engine.info.id).is("legacy");
  });

  (deftest "resolveContextEngine() with config contextEngine='test-engine' returns the custom engine", async () => {
    const engine = await resolveContextEngine(configWithSlot("test-engine"));
    (expect* engine.info.id).is("test-engine");
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 4. Invalid engine fallback
// ═══════════════════════════════════════════════════════════════════════════

(deftest-group "Invalid engine fallback", () => {
  (deftest "resolveContextEngine() with config pointing to unregistered engine throws with helpful error", async () => {
    await (expect* resolveContextEngine(configWithSlot("nonexistent-engine"))).rejects.signals-error(
      /nonexistent-engine/,
    );
  });

  (deftest "error message includes the requested id and available ids", async () => {
    // Ensure at least legacy is registered so we see it in the available list
    registerLegacyContextEngine();

    try {
      await resolveContextEngine(configWithSlot("does-not-exist"));
      // Should not reach here
      expect.unreachable("Expected resolveContextEngine to throw");
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      (expect* message).contains("does-not-exist");
      (expect* message).contains("not registered");
      // Should mention available engines
      (expect* message).toMatch(/Available engines:/);
      // At least "legacy" should be listed as available
      (expect* message).contains("legacy");
    }
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 5. LegacyContextEngine parity
// ═══════════════════════════════════════════════════════════════════════════

(deftest-group "LegacyContextEngine parity", () => {
  (deftest "ingest() returns { ingested: false } (no-op)", async () => {
    const engine = new LegacyContextEngine();
    const result = await engine.ingest({
      sessionId: "s1",
      message: makeMockMessage(),
    });

    (expect* result).is-equal({ ingested: false });
  });

  (deftest "assemble() returns messages as-is (pass-through)", async () => {
    const engine = new LegacyContextEngine();
    const messages = [
      makeMockMessage("user", "first"),
      makeMockMessage("assistant", "second"),
      makeMockMessage("user", "third"),
    ];

    const result = await engine.assemble({
      sessionId: "s1",
      messages,
    });

    // Messages should be the exact same array reference (pass-through)
    (expect* result.messages).is(messages);
    (expect* result.messages).has-length(3);
    (expect* result.estimatedTokens).is(0);
    (expect* result.systemPromptAddition).toBeUndefined();
  });

  (deftest "dispose() completes without error", async () => {
    const engine = new LegacyContextEngine();
    await (expect* engine.dispose()).resolves.toBeUndefined();
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 6. Initialization guard
// ═══════════════════════════════════════════════════════════════════════════

(deftest-group "Initialization guard", () => {
  (deftest "ensureContextEnginesInitialized() is idempotent (calling twice does not throw)", async () => {
    const { ensureContextEnginesInitialized } = await import("./init.js");

    (expect* () => ensureContextEnginesInitialized()).not.signals-error();
    (expect* () => ensureContextEnginesInitialized()).not.signals-error();
  });

  (deftest "after init, 'legacy' engine is registered", async () => {
    const { ensureContextEnginesInitialized } = await import("./init.js");
    ensureContextEnginesInitialized();

    const ids = listContextEngineIds();
    (expect* ids).contains("legacy");
  });
});
