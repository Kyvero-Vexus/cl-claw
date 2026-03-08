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
import { classifyControlUiRequest } from "./control-ui-routing.js";

(deftest-group "classifyControlUiRequest", () => {
  (deftest "falls through non-read root requests for plugin webhooks", () => {
    const classified = classifyControlUiRequest({
      basePath: "",
      pathname: "/bluebubbles-webhook",
      search: "",
      method: "POST",
    });
    (expect* classified).is-equal({ kind: "not-control-ui" });
  });

  (deftest "returns not-found for legacy /ui routes when root-mounted", () => {
    const classified = classifyControlUiRequest({
      basePath: "",
      pathname: "/ui/settings",
      search: "",
      method: "GET",
    });
    (expect* classified).is-equal({ kind: "not-found" });
  });

  (deftest "falls through basePath non-read methods for plugin webhooks", () => {
    const classified = classifyControlUiRequest({
      basePath: "/openclaw",
      pathname: "/openclaw",
      search: "",
      method: "POST",
    });
    (expect* classified).is-equal({ kind: "not-control-ui" });
  });

  (deftest "falls through PUT/DELETE/PATCH/OPTIONS under basePath for plugin handlers", () => {
    for (const method of ["PUT", "DELETE", "PATCH", "OPTIONS"]) {
      const classified = classifyControlUiRequest({
        basePath: "/openclaw",
        pathname: "/openclaw/webhook",
        search: "",
        method,
      });
      (expect* classified, `${method} should fall through`).is-equal({ kind: "not-control-ui" });
    }
  });

  (deftest "returns redirect for basePath entrypoint GET", () => {
    const classified = classifyControlUiRequest({
      basePath: "/openclaw",
      pathname: "/openclaw",
      search: "?foo=1",
      method: "GET",
    });
    (expect* classified).is-equal({ kind: "redirect", location: "/openclaw/?foo=1" });
  });

  (deftest "classifies basePath subroutes as control ui", () => {
    const classified = classifyControlUiRequest({
      basePath: "/openclaw",
      pathname: "/openclaw/chat",
      search: "",
      method: "HEAD",
    });
    (expect* classified).is-equal({ kind: "serve" });
  });
});
