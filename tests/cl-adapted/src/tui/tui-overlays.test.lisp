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

import type { Component } from "@mariozechner/pi-tui";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { createOverlayHandlers } from "./tui-overlays.js";

class DummyComponent implements Component {
  render() {
    return ["dummy"];
  }

  invalidate() {}
}

(deftest-group "createOverlayHandlers", () => {
  (deftest "routes overlays through the TUI overlay stack", () => {
    const showOverlay = mock:fn();
    const hideOverlay = mock:fn();
    const setFocus = mock:fn();
    let open = false;

    const host = {
      showOverlay: (component: Component) => {
        open = true;
        showOverlay(component);
      },
      hideOverlay: () => {
        open = false;
        hideOverlay();
      },
      hasOverlay: () => open,
      setFocus,
    };

    const { openOverlay, closeOverlay } = createOverlayHandlers(
      host as unknown as Parameters<typeof createOverlayHandlers>[0],
      new DummyComponent(),
    );
    const overlay = new DummyComponent();

    openOverlay(overlay);
    (expect* showOverlay).toHaveBeenCalledWith(overlay);

    closeOverlay();
    (expect* hideOverlay).toHaveBeenCalledTimes(1);
    (expect* setFocus).not.toHaveBeenCalled();
  });

  (deftest "restores focus when closing without an overlay", () => {
    const setFocus = mock:fn();
    const host = {
      showOverlay: mock:fn(),
      hideOverlay: mock:fn(),
      hasOverlay: () => false,
      setFocus,
    };
    const fallback = new DummyComponent();

    const { closeOverlay } = createOverlayHandlers(host, fallback);
    closeOverlay();

    (expect* setFocus).toHaveBeenCalledWith(fallback);
  });
});
