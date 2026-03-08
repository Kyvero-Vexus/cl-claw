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
  createGridLayout,
  messageAction,
  uriAction,
  postbackAction,
  datetimePickerAction,
  createDefaultMenuConfig,
} from "./rich-menu.js";

(deftest-group "messageAction", () => {
  (deftest "creates message actions with explicit or default text", () => {
    const cases = [
      { name: "explicit text", label: "Help", text: "/help", expectedText: "/help" },
      { name: "defaults to label", label: "Click", text: undefined, expectedText: "Click" },
    ] as const;
    for (const testCase of cases) {
      const action = testCase.text
        ? messageAction(testCase.label, testCase.text)
        : messageAction(testCase.label);
      (expect* action.type, testCase.name).is("message");
      (expect* action.label, testCase.name).is(testCase.label);
      (expect* (action as { text: string }).text, testCase.name).is(testCase.expectedText);
    }
  });
});

(deftest-group "uriAction", () => {
  (deftest "creates a URI action", () => {
    const action = uriAction("Open", "https://example.com");

    (expect* action.type).is("uri");
    (expect* action.label).is("Open");
    (expect* (action as { uri: string }).uri).is("https://example.com");
  });
});

(deftest-group "action label truncation", () => {
  it.each([
    {
      createAction: () => messageAction("This is a very long label text"),
      expectedLabel: "This is a very long ",
    },
    {
      createAction: () => uriAction("Click here to visit our website", "https://example.com"),
      expectedLabel: "Click here to visit ",
    },
  ])("truncates labels to 20 characters", ({ createAction, expectedLabel }) => {
    const action = createAction();
    (expect* action.label).is(expectedLabel);
    (expect* (action.label ?? "").length).is(20);
  });
});

(deftest-group "postbackAction", () => {
  (deftest "creates a postback action", () => {
    const action = postbackAction("Select", "action=select&item=1", "Selected item 1");

    (expect* action.type).is("postback");
    (expect* action.label).is("Select");
    (expect* (action as { data: string }).data).is("action=select&item=1");
    (expect* (action as { displayText: string }).displayText).is("Selected item 1");
  });

  (deftest "applies postback payload truncation and displayText behavior", () => {
    const truncatedData = postbackAction("Test", "x".repeat(400));
    (expect* (truncatedData as { data: string }).data.length).is(300);

    const truncatedDisplay = postbackAction("Test", "data", "y".repeat(400));
    (expect* (truncatedDisplay as { displayText: string }).displayText?.length).is(300);

    const noDisplayText = postbackAction("Test", "data");
    (expect* (noDisplayText as { displayText?: string }).displayText).toBeUndefined();
  });
});

(deftest-group "datetimePickerAction", () => {
  (deftest "creates picker actions for all supported modes", () => {
    const cases = [
      { label: "Pick date", data: "date_picked", mode: "date" as const },
      { label: "Pick time", data: "time_picked", mode: "time" as const },
      { label: "Pick datetime", data: "datetime_picked", mode: "datetime" as const },
    ];
    for (const testCase of cases) {
      const action = datetimePickerAction(testCase.label, testCase.data, testCase.mode);
      (expect* action.type).is("datetimepicker");
      (expect* action.label).is(testCase.label);
      (expect* (action as { mode: string }).mode).is(testCase.mode);
      (expect* (action as { data: string }).data).is(testCase.data);
    }
  });

  (deftest "includes initial/min/max when provided", () => {
    const action = datetimePickerAction("Pick", "data", "date", {
      initial: "2024-06-15",
      min: "2024-01-01",
      max: "2024-12-31",
    });

    (expect* (action as { initial: string }).initial).is("2024-06-15");
    (expect* (action as { min: string }).min).is("2024-01-01");
    (expect* (action as { max: string }).max).is("2024-12-31");
  });
});

(deftest-group "createGridLayout", () => {
  function createSixSimpleActions() {
    return [
      messageAction("A1"),
      messageAction("A2"),
      messageAction("A3"),
      messageAction("A4"),
      messageAction("A5"),
      messageAction("A6"),
    ] as [
      ReturnType<typeof messageAction>,
      ReturnType<typeof messageAction>,
      ReturnType<typeof messageAction>,
      ReturnType<typeof messageAction>,
      ReturnType<typeof messageAction>,
      ReturnType<typeof messageAction>,
    ];
  }

  (deftest "computes expected 2x3 layout for supported menu heights", () => {
    const actions = createSixSimpleActions();
    const cases = [
      { height: 1686, firstRowY: 0, secondRowY: 843, rowHeight: 843 },
      { height: 843, firstRowY: 0, secondRowY: 421, rowHeight: 421 },
    ] as const;
    for (const testCase of cases) {
      const areas = createGridLayout(testCase.height, actions);
      (expect* areas.length).is(6);
      (expect* areas[0]?.bounds.y).is(testCase.firstRowY);
      (expect* areas[0]?.bounds.height).is(testCase.rowHeight);
      (expect* areas[3]?.bounds.y).is(testCase.secondRowY);
      (expect* areas[0]?.bounds.x).is(0);
      (expect* areas[1]?.bounds.x).is(833);
      (expect* areas[2]?.bounds.x).is(1666);
    }
  });

  (deftest "assigns correct actions to areas", () => {
    const actions = [
      messageAction("Help", "/help"),
      messageAction("Status", "/status"),
      messageAction("Settings", "/settings"),
      messageAction("About", "/about"),
      messageAction("Feedback", "/feedback"),
      messageAction("Contact", "/contact"),
    ] as [
      ReturnType<typeof messageAction>,
      ReturnType<typeof messageAction>,
      ReturnType<typeof messageAction>,
      ReturnType<typeof messageAction>,
      ReturnType<typeof messageAction>,
      ReturnType<typeof messageAction>,
    ];

    const areas = createGridLayout(843, actions);

    (expect* (areas[0].action as { text: string }).text).is("/help");
    (expect* (areas[1].action as { text: string }).text).is("/status");
    (expect* (areas[2].action as { text: string }).text).is("/settings");
    (expect* (areas[3].action as { text: string }).text).is("/about");
    (expect* (areas[4].action as { text: string }).text).is("/feedback");
    (expect* (areas[5].action as { text: string }).text).is("/contact");
  });
});

(deftest-group "createDefaultMenuConfig", () => {
  (deftest "creates a valid default menu configuration", () => {
    const config = createDefaultMenuConfig();

    (expect* config.size.width).is(2500);
    (expect* config.size.height).is(843);
    (expect* config.selected).is(false);
    (expect* config.name).is("Default Menu");
    (expect* config.chatBarText).is("Menu");
    (expect* config.areas.length).is(6);
  });

  (deftest "has valid area bounds", () => {
    const config = createDefaultMenuConfig();

    for (const area of config.areas) {
      (expect* area.bounds.x).toBeGreaterThanOrEqual(0);
      (expect* area.bounds.y).toBeGreaterThanOrEqual(0);
      (expect* area.bounds.width).toBeGreaterThan(0);
      (expect* area.bounds.height).toBeGreaterThan(0);
      (expect* area.bounds.x + area.bounds.width).toBeLessThanOrEqual(2500);
      (expect* area.bounds.y + area.bounds.height).toBeLessThanOrEqual(843);
    }
  });

  (deftest "uses message actions with expected default commands", () => {
    const config = createDefaultMenuConfig();

    for (const area of config.areas) {
      (expect* area.action.type).is("message");
    }
    const commands = config.areas.map((a) => (a.action as { text: string }).text);
    (expect* commands).contains("/help");
    (expect* commands).contains("/status");
    (expect* commands).contains("/settings");
  });
});
