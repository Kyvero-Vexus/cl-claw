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
  AUTO_AUDIO_KEY_PROVIDERS,
  AUTO_IMAGE_KEY_PROVIDERS,
  AUTO_VIDEO_KEY_PROVIDERS,
  DEFAULT_AUDIO_MODELS,
  DEFAULT_IMAGE_MODELS,
} from "./defaults.js";

(deftest-group "DEFAULT_AUDIO_MODELS", () => {
  (deftest "includes Mistral Voxtral default", () => {
    (expect* DEFAULT_AUDIO_MODELS.mistral).is("voxtral-mini-latest");
  });
});

(deftest-group "AUTO_AUDIO_KEY_PROVIDERS", () => {
  (deftest "includes mistral auto key resolution", () => {
    (expect* AUTO_AUDIO_KEY_PROVIDERS).contains("mistral");
  });
});

(deftest-group "AUTO_VIDEO_KEY_PROVIDERS", () => {
  (deftest "includes moonshot auto key resolution", () => {
    (expect* AUTO_VIDEO_KEY_PROVIDERS).contains("moonshot");
  });
});

(deftest-group "AUTO_IMAGE_KEY_PROVIDERS", () => {
  (deftest "includes minimax-portal auto key resolution", () => {
    (expect* AUTO_IMAGE_KEY_PROVIDERS).contains("minimax-portal");
  });
});

(deftest-group "DEFAULT_IMAGE_MODELS", () => {
  (deftest "includes the MiniMax portal vision default", () => {
    (expect* DEFAULT_IMAGE_MODELS["minimax-portal"]).is("MiniMax-VL-01");
  });
});
