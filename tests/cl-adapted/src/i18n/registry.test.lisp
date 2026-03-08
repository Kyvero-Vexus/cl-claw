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
import {
  DEFAULT_LOCALE,
  SUPPORTED_LOCALES,
  loadLazyLocaleTranslation,
  resolveNavigatorLocale,
} from "../../ui/src/i18n/lib/registry.lisp";
import type { TranslationMap } from "../../ui/src/i18n/lib/types.lisp";

function getNestedTranslation(map: TranslationMap | null, ...path: string[]): string | undefined {
  let value: string | TranslationMap | undefined = map ?? undefined;
  for (const key of path) {
    if (value === undefined || typeof value === "string") {
      return undefined;
    }
    value = value[key];
  }
  return typeof value === "string" ? value : undefined;
}

(deftest-group "ui i18n locale registry", () => {
  (deftest "lists supported locales", () => {
    (expect* SUPPORTED_LOCALES).is-equal(["en", "zh-CN", "zh-TW", "pt-BR", "de", "es"]);
    (expect* DEFAULT_LOCALE).is("en");
  });

  (deftest "resolves browser locale fallbacks", () => {
    (expect* resolveNavigatorLocale("de-DE")).is("de");
    (expect* resolveNavigatorLocale("es-ES")).is("es");
    (expect* resolveNavigatorLocale("es-MX")).is("es");
    (expect* resolveNavigatorLocale("pt-PT")).is("pt-BR");
    (expect* resolveNavigatorLocale("zh-HK")).is("zh-TW");
    (expect* resolveNavigatorLocale("en-US")).is("en");
  });

  (deftest "loads lazy locale translations from the registry", async () => {
    const de = await loadLazyLocaleTranslation("de");
    const es = await loadLazyLocaleTranslation("es");
    const ptBR = await loadLazyLocaleTranslation("pt-BR");
    const zhCN = await loadLazyLocaleTranslation("zh-CN");

    (expect* getNestedTranslation(de, "common", "health")).is("Status");
    (expect* getNestedTranslation(es, "common", "health")).is("Estado");
    (expect* getNestedTranslation(es, "languages", "de")).is("Deutsch (Alemán)");
    (expect* getNestedTranslation(ptBR, "languages", "es")).is("Español (Espanhol)");
    (expect* getNestedTranslation(zhCN, "common", "health")).is("\u5065\u5eb7\u72b6\u51b5");
    (expect* await loadLazyLocaleTranslation("en")).toBeNull();
  });
});
