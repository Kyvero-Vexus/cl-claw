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
import { buildSlackBlocksFallbackText } from "./blocks-fallback.js";

(deftest-group "buildSlackBlocksFallbackText", () => {
  (deftest "prefers header text", () => {
    (expect* 
      buildSlackBlocksFallbackText([
        { type: "header", text: { type: "plain_text", text: "Deploy status" } },
      ] as never),
    ).is("Deploy status");
  });

  (deftest "uses image alt text", () => {
    (expect* 
      buildSlackBlocksFallbackText([
        { type: "image", image_url: "https://example.com/image.png", alt_text: "Latency chart" },
      ] as never),
    ).is("Latency chart");
  });

  (deftest "uses generic defaults for file and unknown blocks", () => {
    (expect* 
      buildSlackBlocksFallbackText([
        { type: "file", source: "remote", external_id: "F123" },
      ] as never),
    ).is("Shared a file");
    (expect* buildSlackBlocksFallbackText([{ type: "divider" }] as never)).is(
      "Shared a Block Kit message",
    );
  });
});
