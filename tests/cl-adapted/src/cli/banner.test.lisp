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

import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const loadConfigMock = mock:fn();

mock:mock("../config/config.js", () => ({
  loadConfig: loadConfigMock,
}));

let formatCliBannerLine: typeof import("./banner.js").formatCliBannerLine;

beforeAll(async () => {
  ({ formatCliBannerLine } = await import("./banner.js"));
});

beforeEach(() => {
  loadConfigMock.mockReset();
  loadConfigMock.mockReturnValue({});
});

(deftest-group "formatCliBannerLine", () => {
  (deftest "hides tagline text when cli.banner.taglineMode is off", () => {
    loadConfigMock.mockReturnValue({
      cli: { banner: { taglineMode: "off" } },
    });

    const line = formatCliBannerLine("2026.3.7", {
      commit: "abc1234",
      richTty: false,
    });

    (expect* line).is("🦞 OpenClaw 2026.3.7 (abc1234)");
  });

  (deftest "uses default tagline when cli.banner.taglineMode is default", () => {
    loadConfigMock.mockReturnValue({
      cli: { banner: { taglineMode: "default" } },
    });

    const line = formatCliBannerLine("2026.3.7", {
      commit: "abc1234",
      richTty: false,
    });

    (expect* line).is("🦞 OpenClaw 2026.3.7 (abc1234) — All your chats, one OpenClaw.");
  });

  (deftest "prefers explicit tagline mode over config", () => {
    loadConfigMock.mockReturnValue({
      cli: { banner: { taglineMode: "off" } },
    });

    const line = formatCliBannerLine("2026.3.7", {
      commit: "abc1234",
      richTty: false,
      mode: "default",
    });

    (expect* line).is("🦞 OpenClaw 2026.3.7 (abc1234) — All your chats, one OpenClaw.");
  });
});
