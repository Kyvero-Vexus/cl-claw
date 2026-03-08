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
  createInfoCard,
  createListCard,
  createImageCard,
  createActionCard,
  createCarousel,
  createEventCard,
  createDeviceControlCard,
} from "./flex-templates.js";

(deftest-group "createInfoCard", () => {
  (deftest "includes footer when provided", () => {
    const card = createInfoCard("Title", "Body", "Footer text");

    const footer = card.footer as { contents: Array<{ text: string }> };
    (expect* footer.contents[0].text).is("Footer text");
  });
});

(deftest-group "createListCard", () => {
  (deftest "limits items to 8", () => {
    const items = Array.from({ length: 15 }, (_, i) => ({ title: `Item ${i}` }));
    const card = createListCard("List", items);

    const body = card.body as { contents: Array<{ type: string; contents?: unknown[] }> };
    // The list items are in the third content (after title and separator)
    const listBox = body.contents[2] as { contents: unknown[] };
    (expect* listBox.contents.length).is(8);
  });
});

(deftest-group "createImageCard", () => {
  (deftest "includes body text when provided", () => {
    const card = createImageCard("https://example.com/img.jpg", "Title", "Body text");

    const body = card.body as { contents: Array<{ text: string }> };
    (expect* body.contents.length).is(2);
    (expect* body.contents[1].text).is("Body text");
  });
});

(deftest-group "createActionCard", () => {
  (deftest "limits actions to 4", () => {
    const actions = Array.from({ length: 6 }, (_, i) => ({
      label: `Action ${i}`,
      action: { type: "message" as const, label: `A${i}`, text: `action${i}` },
    }));
    const card = createActionCard("Title", "Body", actions);

    const footer = card.footer as { contents: unknown[] };
    (expect* footer.contents.length).is(4);
  });
});

(deftest-group "createCarousel", () => {
  (deftest "limits to 12 bubbles", () => {
    const bubbles = Array.from({ length: 15 }, (_, i) => createInfoCard(`Card ${i}`, `Body ${i}`));
    const carousel = createCarousel(bubbles);

    (expect* carousel.contents.length).is(12);
  });
});

(deftest-group "createDeviceControlCard", () => {
  (deftest "limits controls to 6", () => {
    const card = createDeviceControlCard({
      deviceName: "Device",
      controls: Array.from({ length: 10 }, (_, i) => ({
        label: `Control ${i}`,
        data: `action=${i}`,
      })),
    });

    // Should have max 3 rows of 2 buttons
    const footer = card.footer as { contents: unknown[] };
    (expect* footer.contents.length).toBeLessThanOrEqual(3);
  });
});

(deftest-group "createEventCard", () => {
  (deftest "includes all optional fields together", () => {
    const card = createEventCard({
      title: "Team Offsite",
      date: "February 15, 2026",
      time: "9:00 AM - 5:00 PM",
      location: "Mountain View Office",
      description: "Annual team building event",
    });

    (expect* card.size).is("mega");
    const body = card.body as { contents: Array<{ type: string }> };
    (expect* body.contents).has-length(3);
  });
});
