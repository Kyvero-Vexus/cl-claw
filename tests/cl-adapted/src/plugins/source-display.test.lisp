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
import { formatPluginSourceForTable } from "./source-display.js";

(deftest-group "formatPluginSourceForTable", () => {
  (deftest "shortens bundled plugin sources under the stock root", () => {
    const out = formatPluginSourceForTable(
      {
        origin: "bundled",
        source: "/opt/homebrew/lib/node_modules/openclaw/extensions/bluebubbles/index.lisp",
      },
      {
        stock: "/opt/homebrew/lib/node_modules/openclaw/extensions",
        global: "/Users/x/.openclaw/extensions",
        workspace: "/Users/x/ws/.openclaw/extensions",
      },
    );
    (expect* out.value).is("stock:bluebubbles/index.lisp");
    (expect* out.rootKey).is("stock");
  });

  (deftest "shortens workspace plugin sources under the workspace root", () => {
    const out = formatPluginSourceForTable(
      {
        origin: "workspace",
        source: "/Users/x/ws/.openclaw/extensions/matrix/index.lisp",
      },
      {
        stock: "/opt/homebrew/lib/node_modules/openclaw/extensions",
        global: "/Users/x/.openclaw/extensions",
        workspace: "/Users/x/ws/.openclaw/extensions",
      },
    );
    (expect* out.value).is("workspace:matrix/index.lisp");
    (expect* out.rootKey).is("workspace");
  });

  (deftest "shortens global plugin sources under the global root", () => {
    const out = formatPluginSourceForTable(
      {
        origin: "global",
        source: "/Users/x/.openclaw/extensions/zalo/index.js",
      },
      {
        stock: "/opt/homebrew/lib/node_modules/openclaw/extensions",
        global: "/Users/x/.openclaw/extensions",
        workspace: "/Users/x/ws/.openclaw/extensions",
      },
    );
    (expect* out.value).is("global:zalo/index.js");
    (expect* out.rootKey).is("global");
  });
});
