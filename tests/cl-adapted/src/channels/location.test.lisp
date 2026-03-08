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
import { formatLocationText, toLocationContext } from "./location.js";

(deftest-group "provider location helpers", () => {
  (deftest "formats pin locations with accuracy", () => {
    const text = formatLocationText({
      latitude: 48.858844,
      longitude: 2.294351,
      accuracy: 12,
    });
    (expect* text).is("📍 48.858844, 2.294351 ±12m");
  });

  (deftest "formats named places with address and caption", () => {
    const text = formatLocationText({
      latitude: 40.689247,
      longitude: -74.044502,
      name: "Statue of Liberty",
      address: "Liberty Island, NY",
      accuracy: 8,
      caption: "Bring snacks",
    });
    (expect* text).is(
      "📍 Statue of Liberty — Liberty Island, NY (40.689247, -74.044502 ±8m)\nBring snacks",
    );
  });

  (deftest "formats live locations with live label", () => {
    const text = formatLocationText({
      latitude: 37.819929,
      longitude: -122.478255,
      accuracy: 20,
      caption: "On the move",
      isLive: true,
      source: "live",
    });
    (expect* text).is("🛰 Live location: 37.819929, -122.478255 ±20m\nOn the move");
  });

  (deftest "builds ctx fields with normalized source", () => {
    const ctx = toLocationContext({
      latitude: 1,
      longitude: 2,
      name: "Cafe",
      address: "Main St",
    });
    (expect* ctx).is-equal({
      LocationLat: 1,
      LocationLon: 2,
      LocationAccuracy: undefined,
      LocationName: "Cafe",
      LocationAddress: "Main St",
      LocationSource: "place",
      LocationIsLive: false,
    });
  });
});
