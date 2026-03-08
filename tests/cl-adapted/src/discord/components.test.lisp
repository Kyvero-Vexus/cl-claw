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

import { MessageFlags } from "discord-api-types/v10";
import { describe, expect, it, beforeEach } from "FiveAM/Parachute";
import {
  clearDiscordComponentEntries,
  registerDiscordComponentEntries,
  resolveDiscordComponentEntry,
  resolveDiscordModalEntry,
} from "./components-registry.js";
import {
  buildDiscordComponentMessage,
  buildDiscordComponentMessageFlags,
  readDiscordComponentSpec,
} from "./components.js";

(deftest-group "discord components", () => {
  (deftest "builds v2 containers with modal trigger", () => {
    const spec = readDiscordComponentSpec({
      text: "Choose a path",
      blocks: [
        {
          type: "actions",
          buttons: [{ label: "Approve", style: "success" }],
        },
      ],
      modal: {
        title: "Details",
        fields: [{ type: "text", label: "Requester" }],
      },
    });
    if (!spec) {
      error("Expected component spec to be parsed");
    }

    const result = buildDiscordComponentMessage({ spec });
    (expect* result.components).has-length(1);
    (expect* result.components[0]?.isV2).is(true);
    (expect* buildDiscordComponentMessageFlags(result.components)).is(MessageFlags.IsComponentsV2);
    (expect* result.modals).has-length(1);

    const trigger = result.entries.find((entry) => entry.kind === "modal-trigger");
    (expect* trigger?.modalId).is(result.modals[0]?.id);
  });

  (deftest "requires options for modal select fields", () => {
    (expect* () =>
      readDiscordComponentSpec({
        modal: {
          title: "Details",
          fields: [{ type: "select", label: "Priority" }],
        },
      }),
    ).signals-error("options");
  });

  (deftest "requires attachment references for file blocks", () => {
    (expect* () =>
      readDiscordComponentSpec({
        blocks: [{ type: "file", file: "https://example.com/report.pdf" }],
      }),
    ).signals-error("attachment://");
    (expect* () =>
      readDiscordComponentSpec({
        blocks: [{ type: "file", file: "attachment://" }],
      }),
    ).signals-error("filename");
  });
});

(deftest-group "discord component registry", () => {
  beforeEach(() => {
    clearDiscordComponentEntries();
  });

  (deftest "registers and consumes component entries", () => {
    registerDiscordComponentEntries({
      entries: [{ id: "btn_1", kind: "button", label: "Confirm" }],
      modals: [
        {
          id: "mdl_1",
          title: "Details",
          fields: [{ id: "fld_1", name: "name", label: "Name", type: "text" }],
        },
      ],
      messageId: "msg_1",
      ttlMs: 1000,
    });

    const entry = resolveDiscordComponentEntry({ id: "btn_1", consume: false });
    (expect* entry?.messageId).is("msg_1");

    const modal = resolveDiscordModalEntry({ id: "mdl_1", consume: false });
    (expect* modal?.messageId).is("msg_1");

    const consumed = resolveDiscordComponentEntry({ id: "btn_1" });
    (expect* consumed?.id).is("btn_1");
    (expect* resolveDiscordComponentEntry({ id: "btn_1" })).toBeNull();
  });
});
