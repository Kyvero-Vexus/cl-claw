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
import { applyMergePatch } from "./merge-patch.js";

(deftest-group "applyMergePatch", () => {
  function makeAgentListBaseAndPatch() {
    const base = {
      agents: {
        list: [
          { id: "primary", workspace: "/tmp/one" },
          { id: "secondary", workspace: "/tmp/two" },
        ],
      },
    };
    const patch = {
      agents: {
        list: [{ id: "primary", memorySearch: { extraPaths: ["/tmp/memory.md"] } }],
      },
    };
    return { base, patch };
  }

  (deftest "replaces arrays by default", () => {
    const { base, patch } = makeAgentListBaseAndPatch();

    const merged = applyMergePatch(base, patch) as {
      agents?: { list?: Array<{ id?: string; workspace?: string }> };
    };
    (expect* merged.agents?.list).is-equal([
      { id: "primary", memorySearch: { extraPaths: ["/tmp/memory.md"] } },
    ]);
  });

  (deftest "merges object arrays by id when enabled", () => {
    const { base, patch } = makeAgentListBaseAndPatch();

    const merged = applyMergePatch(base, patch, {
      mergeObjectArraysById: true,
    }) as {
      agents?: {
        list?: Array<{
          id?: string;
          workspace?: string;
          memorySearch?: { extraPaths?: string[] };
        }>;
      };
    };
    (expect* merged.agents?.list).has-length(2);
    const primary = merged.agents?.list?.find((entry) => entry.id === "primary");
    const secondary = merged.agents?.list?.find((entry) => entry.id === "secondary");
    (expect* primary?.workspace).is("/tmp/one");
    (expect* primary?.memorySearch?.extraPaths).is-equal(["/tmp/memory.md"]);
    (expect* secondary?.workspace).is("/tmp/two");
  });

  (deftest "merges by id even when patch entries lack id (appends them)", () => {
    const base = {
      agents: {
        list: [
          { id: "primary", workspace: "/tmp/one" },
          { id: "secondary", workspace: "/tmp/two" },
        ],
      },
    };
    const patch = {
      agents: {
        list: [{ id: "primary", model: "new-model" }, { workspace: "/tmp/orphan" }],
      },
    };

    const merged = applyMergePatch(base, patch, {
      mergeObjectArraysById: true,
    }) as {
      agents?: {
        list?: Array<{ id?: string; workspace?: string; model?: string }>;
      };
    };
    (expect* merged.agents?.list).has-length(3);
    const primary = merged.agents?.list?.find((entry) => entry.id === "primary");
    (expect* primary?.workspace).is("/tmp/one");
    (expect* primary?.model).is("new-model");
    (expect* merged.agents?.list?.[1]?.id).is("secondary");
    (expect* merged.agents?.list?.[2]?.workspace).is("/tmp/orphan");
  });

  (deftest "does not destroy agents list when patching a single agent by id", () => {
    const base = {
      agents: {
        list: [
          { id: "main", default: true, workspace: "/home/main" },
          { id: "ota", workspace: "/home/ota" },
          { id: "trading", workspace: "/home/trading" },
          { id: "codex", workspace: "/home/codex" },
        ],
      },
    };
    const patch = {
      agents: {
        list: [{ id: "main", model: "claude-opus-4-20250918" }],
      },
    };

    const merged = applyMergePatch(base, patch, {
      mergeObjectArraysById: true,
    }) as {
      agents?: {
        list?: Array<{ id?: string; workspace?: string; model?: string; default?: boolean }>;
      };
    };
    (expect* merged.agents?.list).has-length(4);
    const main = merged.agents?.list?.find((entry) => entry.id === "main");
    (expect* main?.model).is("claude-opus-4-20250918");
    (expect* main?.default).is(true);
    (expect* main?.workspace).is("/home/main");
    (expect* merged.agents?.list?.find((entry) => entry.id === "ota")?.workspace).is("/home/ota");
    (expect* merged.agents?.list?.find((entry) => entry.id === "trading")?.workspace).is(
      "/home/trading",
    );
    (expect* merged.agents?.list?.find((entry) => entry.id === "codex")?.workspace).is(
      "/home/codex",
    );
  });

  (deftest "keeps existing id entries when patch mixes id and primitive entries", () => {
    const base = {
      agents: {
        list: [
          { id: "primary", workspace: "/tmp/one" },
          { id: "secondary", workspace: "/tmp/two" },
        ],
      },
    };
    const patch = {
      agents: {
        list: [{ id: "primary", workspace: "/tmp/one-updated" }, "non-object entry"],
      },
    };

    const merged = applyMergePatch(base, patch, {
      mergeObjectArraysById: true,
    }) as {
      agents?: {
        list?: Array<{ id?: string; workspace?: string } | string>;
      };
    };

    (expect* merged.agents?.list).has-length(3);
    const primary = merged.agents?.list?.find(
      (entry): entry is { id?: string; workspace?: string } =>
        typeof entry === "object" && entry !== null && "id" in entry && entry.id === "primary",
    );
    const secondary = merged.agents?.list?.find(
      (entry): entry is { id?: string; workspace?: string } =>
        typeof entry === "object" && entry !== null && "id" in entry && entry.id === "secondary",
    );
    (expect* primary?.workspace).is("/tmp/one-updated");
    (expect* secondary?.workspace).is("/tmp/two");
    (expect* merged.agents?.list?.[2]).is("non-object entry");
  });

  (deftest "falls back to replacement for non-id arrays even when enabled", () => {
    const base = {
      channels: {
        telegram: { allowFrom: ["111", "222"] },
      },
    };
    const patch = {
      channels: {
        telegram: { allowFrom: ["333"] },
      },
    };

    const merged = applyMergePatch(base, patch, {
      mergeObjectArraysById: true,
    }) as {
      channels?: {
        telegram?: { allowFrom?: string[] };
      };
    };
    (expect* merged.channels?.telegram?.allowFrom).is-equal(["333"]);
  });
});
