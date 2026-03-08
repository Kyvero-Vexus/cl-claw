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
  createConfirmTemplate,
  createButtonTemplate,
  createTemplateCarousel,
  createCarouselColumn,
  createImageCarousel,
  createImageCarouselColumn,
  createProductCarousel,
  messageAction,
} from "./template-messages.js";

(deftest-group "createConfirmTemplate", () => {
  (deftest "truncates text to 240 characters", () => {
    const longText = "x".repeat(300);
    const template = createConfirmTemplate(longText, messageAction("Yes"), messageAction("No"));

    (expect* (template.template as { text: string }).text.length).is(240);
  });
});

(deftest-group "createButtonTemplate", () => {
  (deftest "limits actions to 4", () => {
    const actions = Array.from({ length: 6 }, (_, i) => messageAction(`Button ${i}`));
    const template = createButtonTemplate("Title", "Text", actions);

    (expect* (template.template as { actions: unknown[] }).actions.length).is(4);
  });

  (deftest "truncates title to 40 characters", () => {
    const longTitle = "x".repeat(50);
    const template = createButtonTemplate(longTitle, "Text", [messageAction("OK")]);

    (expect* (template.template as { title: string }).title.length).is(40);
  });

  (deftest "truncates text to 60 chars when no thumbnail is provided", () => {
    const longText = "x".repeat(100);
    const template = createButtonTemplate("Title", longText, [messageAction("OK")]);

    (expect* (template.template as { text: string }).text.length).is(60);
  });

  (deftest "keeps longer text when thumbnail is provided", () => {
    const longText = "x".repeat(100);
    const template = createButtonTemplate("Title", longText, [messageAction("OK")], {
      thumbnailImageUrl: "https://example.com/thumb.jpg",
    });

    (expect* (template.template as { text: string }).text.length).is(100);
  });
});

(deftest-group "createCarouselColumn", () => {
  (deftest "limits actions to 3", () => {
    const column = createCarouselColumn({
      text: "Text",
      actions: [
        messageAction("A1"),
        messageAction("A2"),
        messageAction("A3"),
        messageAction("A4"),
        messageAction("A5"),
      ],
    });

    (expect* column.actions.length).is(3);
  });

  (deftest "truncates text to 120 characters", () => {
    const longText = "x".repeat(150);
    const column = createCarouselColumn({ text: longText, actions: [messageAction("OK")] });

    (expect* column.text.length).is(120);
  });
});

(deftest-group "carousel column limits", () => {
  it.each([
    {
      createTemplate: () =>
        createTemplateCarousel(
          Array.from({ length: 15 }, () =>
            createCarouselColumn({ text: "Text", actions: [messageAction("OK")] }),
          ),
        ),
    },
    {
      createTemplate: () =>
        createImageCarousel(
          Array.from({ length: 15 }, (_, i) =>
            createImageCarouselColumn(`https://example.com/${i}.jpg`, messageAction("View")),
          ),
        ),
    },
  ])("limits columns to 10", ({ createTemplate }) => {
    const template = createTemplate();
    (expect* (template.template as { columns: unknown[] }).columns.length).is(10);
  });
});

(deftest-group "createProductCarousel", () => {
  it.each([
    {
      title: "Product",
      description: "Desc",
      actionLabel: "Buy",
      actionUrl: "https://shop.com/buy",
      expectedType: "uri",
    },
    {
      title: "Product",
      description: "Desc",
      actionLabel: "Select",
      actionData: "product_id=123",
      expectedType: "postback",
    },
  ])("uses expected action type for product action", ({ expectedType, ...item }) => {
    const template = createProductCarousel([item]);
    const columns = (template.template as { columns: Array<{ actions: Array<{ type: string }> }> })
      .columns;
    (expect* columns[0].actions[0].type).is(expectedType);
  });
});
