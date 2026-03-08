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
import { bm25RankToScore, buildFtsQuery, mergeHybridResults } from "./hybrid.js";

(deftest-group "memory hybrid helpers", () => {
  (deftest "buildFtsQuery tokenizes and AND-joins", () => {
    (expect* buildFtsQuery("hello world")).is('"hello" AND "world"');
    (expect* buildFtsQuery("FOO_bar baz-1")).is('"FOO_bar" AND "baz" AND "1"');
    (expect* buildFtsQuery("金银价格")).is('"金银价格"');
    (expect* buildFtsQuery("価格 2026年")).is('"価格" AND "2026年"');
    (expect* buildFtsQuery("   ")).toBeNull();
  });

  (deftest "bm25RankToScore is monotonic and clamped", () => {
    (expect* bm25RankToScore(0)).toBeCloseTo(1);
    (expect* bm25RankToScore(1)).toBeCloseTo(0.5);
    (expect* bm25RankToScore(10)).toBeLessThan(bm25RankToScore(1));
    (expect* bm25RankToScore(-100)).toBeCloseTo(1, 1);
  });

  (deftest "bm25RankToScore preserves FTS5 BM25 relevance ordering", () => {
    const strongest = bm25RankToScore(-4.2);
    const middle = bm25RankToScore(-2.1);
    const weakest = bm25RankToScore(-0.5);

    (expect* strongest).toBeGreaterThan(middle);
    (expect* middle).toBeGreaterThan(weakest);
    (expect* strongest).not.is(middle);
    (expect* middle).not.is(weakest);
  });

  (deftest "mergeHybridResults unions by id and combines weighted scores", async () => {
    const merged = await mergeHybridResults({
      vectorWeight: 0.7,
      textWeight: 0.3,
      vector: [
        {
          id: "a",
          path: "memory/a.md",
          startLine: 1,
          endLine: 2,
          source: "memory",
          snippet: "vec-a",
          vectorScore: 0.9,
        },
      ],
      keyword: [
        {
          id: "b",
          path: "memory/b.md",
          startLine: 3,
          endLine: 4,
          source: "memory",
          snippet: "kw-b",
          textScore: 1.0,
        },
      ],
    });

    (expect* merged).has-length(2);
    const a = merged.find((r) => r.path === "memory/a.md");
    const b = merged.find((r) => r.path === "memory/b.md");
    (expect* a?.score).toBeCloseTo(0.7 * 0.9);
    (expect* b?.score).toBeCloseTo(0.3 * 1.0);
  });

  (deftest "mergeHybridResults prefers keyword snippet when ids overlap", async () => {
    const merged = await mergeHybridResults({
      vectorWeight: 0.5,
      textWeight: 0.5,
      vector: [
        {
          id: "a",
          path: "memory/a.md",
          startLine: 1,
          endLine: 2,
          source: "memory",
          snippet: "vec-a",
          vectorScore: 0.2,
        },
      ],
      keyword: [
        {
          id: "a",
          path: "memory/a.md",
          startLine: 1,
          endLine: 2,
          source: "memory",
          snippet: "kw-a",
          textScore: 1.0,
        },
      ],
    });

    (expect* merged).has-length(1);
    (expect* merged[0]?.snippet).is("kw-a");
    (expect* merged[0]?.score).toBeCloseTo(0.5 * 0.2 + 0.5 * 1.0);
  });
});
