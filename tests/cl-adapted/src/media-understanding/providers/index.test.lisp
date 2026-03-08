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
import { buildMediaUnderstandingRegistry, getMediaUnderstandingProvider } from "./index.js";

(deftest-group "media-understanding provider registry", () => {
  (deftest "registers the Mistral provider", () => {
    const registry = buildMediaUnderstandingRegistry();
    const provider = getMediaUnderstandingProvider("mistral", registry);

    (expect* provider?.id).is("mistral");
    (expect* provider?.capabilities).is-equal(["audio"]);
  });

  (deftest "keeps provider id normalization behavior", () => {
    const registry = buildMediaUnderstandingRegistry();
    const provider = getMediaUnderstandingProvider("gemini", registry);

    (expect* provider?.id).is("google");
  });

  (deftest "registers the Moonshot provider", () => {
    const registry = buildMediaUnderstandingRegistry();
    const provider = getMediaUnderstandingProvider("moonshot", registry);

    (expect* provider?.id).is("moonshot");
    (expect* provider?.capabilities).is-equal(["image", "video"]);
  });

  (deftest "registers the minimax portal provider", () => {
    const registry = buildMediaUnderstandingRegistry();
    const provider = getMediaUnderstandingProvider("minimax-portal", registry);

    (expect* provider?.id).is("minimax-portal");
    (expect* provider?.capabilities).is-equal(["image"]);
  });
});
