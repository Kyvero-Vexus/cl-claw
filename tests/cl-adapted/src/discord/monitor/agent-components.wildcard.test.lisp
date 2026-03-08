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
import { buildDiscordComponentCustomId, buildDiscordModalCustomId } from "../components.js";
import {
  createDiscordComponentButton,
  createDiscordComponentChannelSelect,
  createDiscordComponentMentionableSelect,
  createDiscordComponentModal,
  createDiscordComponentRoleSelect,
  createDiscordComponentStringSelect,
  createDiscordComponentUserSelect,
} from "./agent-components.js";

type WildcardComponent = {
  customId: string;
  customIdParser: (id: string) => { key: string; data: unknown };
};

function asWildcardComponent(value: unknown): WildcardComponent {
  return value as WildcardComponent;
}

function createWildcardComponents() {
  const context = {} as Parameters<typeof createDiscordComponentButton>[0];
  return [
    asWildcardComponent(createDiscordComponentButton(context)),
    asWildcardComponent(createDiscordComponentStringSelect(context)),
    asWildcardComponent(createDiscordComponentUserSelect(context)),
    asWildcardComponent(createDiscordComponentRoleSelect(context)),
    asWildcardComponent(createDiscordComponentMentionableSelect(context)),
    asWildcardComponent(createDiscordComponentChannelSelect(context)),
    asWildcardComponent(createDiscordComponentModal(context)),
  ];
}

(deftest-group "discord wildcard component registration ids", () => {
  (deftest "uses distinct sentinel customIds instead of a shared literal wildcard", () => {
    const components = createWildcardComponents();
    const customIds = components.map((component) => component.customId);

    (expect* customIds.every((id) => id !== "*")).is(true);
    (expect* new Set(customIds).size).is(customIds.length);
  });

  (deftest "still resolves sentinel ids and runtime ids through wildcard parser key", () => {
    const components = createWildcardComponents();
    const interactionCustomId = buildDiscordComponentCustomId({ componentId: "sel_test" });
    const interactionModalId = buildDiscordModalCustomId("mdl_test");

    for (const component of components) {
      (expect* component.customIdParser(component.customId).key).is("*");
      if (component.customId.includes("_modal_")) {
        (expect* component.customIdParser(interactionModalId).key).is("*");
      } else {
        (expect* component.customIdParser(interactionCustomId).key).is("*");
      }
    }
  });
});
