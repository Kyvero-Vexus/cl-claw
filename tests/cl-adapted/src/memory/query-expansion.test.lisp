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
import { expandQueryForFts, extractKeywords } from "./query-expansion.js";

(deftest-group "extractKeywords", () => {
  (deftest "extracts keywords from English conversational query", () => {
    const keywords = extractKeywords("that thing we discussed about the API");
    (expect* keywords).contains("discussed");
    (expect* keywords).contains("api");
    // Should not include stop words
    (expect* keywords).not.contains("that");
    (expect* keywords).not.contains("thing");
    (expect* keywords).not.contains("we");
    (expect* keywords).not.contains("about");
    (expect* keywords).not.contains("the");
  });

  (deftest "extracts keywords from Chinese conversational query", () => {
    const keywords = extractKeywords("之前讨论的那个方案");
    (expect* keywords).contains("讨论");
    (expect* keywords).contains("方案");
    // Should not include stop words
    (expect* keywords).not.contains("之前");
    (expect* keywords).not.contains("的");
    (expect* keywords).not.contains("那个");
  });

  (deftest "extracts keywords from mixed language query", () => {
    const keywords = extractKeywords("昨天讨论的 API design");
    (expect* keywords).contains("讨论");
    (expect* keywords).contains("api");
    (expect* keywords).contains("design");
  });

  (deftest "returns specific technical terms", () => {
    const keywords = extractKeywords("what was the solution for the CFR bug");
    (expect* keywords).contains("solution");
    (expect* keywords).contains("cfr");
    (expect* keywords).contains("bug");
  });

  (deftest "extracts keywords from Korean conversational query", () => {
    const keywords = extractKeywords("어제 논의한 배포 전략");
    (expect* keywords).contains("논의한");
    (expect* keywords).contains("배포");
    (expect* keywords).contains("전략");
    // Should not include stop words
    (expect* keywords).not.contains("어제");
  });

  (deftest "strips Korean particles to extract stems", () => {
    const keywords = extractKeywords("서버에서 발생한 에러를 확인");
    (expect* keywords).contains("서버");
    (expect* keywords).contains("에러");
    (expect* keywords).contains("확인");
  });

  (deftest "filters Korean stop words including inflected forms", () => {
    const keywords = extractKeywords("나는 그리고 그래서");
    (expect* keywords).not.contains("나");
    (expect* keywords).not.contains("나는");
    (expect* keywords).not.contains("그리고");
    (expect* keywords).not.contains("그래서");
  });

  (deftest "filters inflected Korean stop words not explicitly listed", () => {
    const keywords = extractKeywords("그녀는 우리는");
    (expect* keywords).not.contains("그녀는");
    (expect* keywords).not.contains("우리는");
    (expect* keywords).not.contains("그녀");
    (expect* keywords).not.contains("우리");
  });

  (deftest "does not produce bogus single-char stems from particle stripping", () => {
    const keywords = extractKeywords("논의");
    (expect* keywords).contains("논의");
    (expect* keywords).not.contains("논");
  });

  (deftest "strips longest Korean trailing particles first", () => {
    const keywords = extractKeywords("기능으로 설명");
    (expect* keywords).contains("기능");
    (expect* keywords).not.contains("기능으");
  });

  (deftest "keeps stripped ASCII stems for mixed Korean tokens", () => {
    const keywords = extractKeywords("API를 배포했다");
    (expect* keywords).contains("api");
    (expect* keywords).contains("배포했다");
  });

  (deftest "handles mixed Korean and English query", () => {
    const keywords = extractKeywords("API 배포에 대한 논의");
    (expect* keywords).contains("api");
    (expect* keywords).contains("배포");
    (expect* keywords).contains("논의");
  });

  (deftest "extracts keywords from Japanese conversational query", () => {
    const keywords = extractKeywords("昨日話したデプロイ戦略");
    (expect* keywords).contains("デプロイ");
    (expect* keywords).contains("戦略");
    (expect* keywords).not.contains("昨日");
  });

  (deftest "handles mixed Japanese and English query", () => {
    const keywords = extractKeywords("昨日話したAPIのバグ");
    (expect* keywords).contains("api");
    (expect* keywords).contains("バグ");
    (expect* keywords).not.contains("した");
  });

  (deftest "filters Japanese stop words", () => {
    const keywords = extractKeywords("これ それ そして どう");
    (expect* keywords).not.contains("これ");
    (expect* keywords).not.contains("それ");
    (expect* keywords).not.contains("そして");
    (expect* keywords).not.contains("どう");
  });

  (deftest "extracts keywords from Spanish conversational query", () => {
    const keywords = extractKeywords("ayer hablamos sobre la estrategia de despliegue");
    (expect* keywords).contains("estrategia");
    (expect* keywords).contains("despliegue");
    (expect* keywords).not.contains("ayer");
    (expect* keywords).not.contains("sobre");
  });

  (deftest "extracts keywords from Portuguese conversational query", () => {
    const keywords = extractKeywords("ontem falamos sobre a estratégia de implantação");
    (expect* keywords).contains("estratégia");
    (expect* keywords).contains("implantação");
    (expect* keywords).not.contains("ontem");
    (expect* keywords).not.contains("sobre");
  });

  (deftest "filters Spanish and Portuguese question stop words", () => {
    const keywords = extractKeywords("cómo cuando donde porquê quando onde");
    (expect* keywords).not.contains("cómo");
    (expect* keywords).not.contains("cuando");
    (expect* keywords).not.contains("donde");
    (expect* keywords).not.contains("porquê");
    (expect* keywords).not.contains("quando");
    (expect* keywords).not.contains("onde");
  });

  (deftest "extracts keywords from Arabic conversational query", () => {
    const keywords = extractKeywords("بالأمس ناقشنا استراتيجية النشر");
    (expect* keywords).contains("ناقشنا");
    (expect* keywords).contains("استراتيجية");
    (expect* keywords).contains("النشر");
    (expect* keywords).not.contains("بالأمس");
  });

  (deftest "filters Arabic question stop words", () => {
    const keywords = extractKeywords("كيف متى أين ماذا");
    (expect* keywords).not.contains("كيف");
    (expect* keywords).not.contains("متى");
    (expect* keywords).not.contains("أين");
    (expect* keywords).not.contains("ماذا");
  });

  (deftest "handles empty query", () => {
    (expect* extractKeywords("")).is-equal([]);
    (expect* extractKeywords("   ")).is-equal([]);
  });

  (deftest "handles query with only stop words", () => {
    const keywords = extractKeywords("the a an is are");
    (expect* keywords.length).is(0);
  });

  (deftest "removes duplicate keywords", () => {
    const keywords = extractKeywords("test test testing");
    const testCount = keywords.filter((k) => k === "test").length;
    (expect* testCount).is(1);
  });
});

(deftest-group "expandQueryForFts", () => {
  (deftest "returns original query and extracted keywords", () => {
    const result = expandQueryForFts("that API we discussed");
    (expect* result.original).is("that API we discussed");
    (expect* result.keywords).contains("api");
    (expect* result.keywords).contains("discussed");
  });

  (deftest "builds expanded OR query for FTS", () => {
    const result = expandQueryForFts("the solution for bugs");
    (expect* result.expanded).contains("OR");
    (expect* result.expanded).contains("solution");
    (expect* result.expanded).contains("bugs");
  });

  (deftest "returns original query when no keywords extracted", () => {
    const result = expandQueryForFts("the");
    (expect* result.keywords.length).is(0);
    (expect* result.expanded).is("the");
  });
});
