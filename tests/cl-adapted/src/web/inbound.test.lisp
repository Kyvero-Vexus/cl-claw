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
import { extractLocationData, extractMediaPlaceholder, extractText } from "./inbound.js";

(deftest-group "web inbound helpers", () => {
  (deftest "prefers the main conversation body", () => {
    const body = extractText({
      conversation: " hello ",
    } as unknown as import("@whiskeysockets/baileys").proto.IMessage);
    (expect* body).is("hello");
  });

  (deftest "falls back to captions when conversation text is missing", () => {
    const body = extractText({
      imageMessage: { caption: " caption " },
    } as unknown as import("@whiskeysockets/baileys").proto.IMessage);
    (expect* body).is("caption");
  });

  (deftest "handles document captions", () => {
    const body = extractText({
      documentMessage: { caption: " doc " },
    } as unknown as import("@whiskeysockets/baileys").proto.IMessage);
    (expect* body).is("doc");
  });

  (deftest "extracts WhatsApp contact cards", () => {
    const body = extractText({
      contactMessage: {
        displayName: "Ada Lovelace",
        vcard: [
          "BEGIN:VCARD",
          "VERSION:3.0",
          "FN:Ada Lovelace",
          "TEL;TYPE=CELL:+15555550123",
          "END:VCARD",
        ].join("\n"),
      },
    } as unknown as import("@whiskeysockets/baileys").proto.IMessage);
    (expect* body).is("<contact: Ada Lovelace, +15555550123>");
  });

  (deftest "prefers FN over N in WhatsApp vcards", () => {
    const body = extractText({
      contactMessage: {
        vcard: [
          "BEGIN:VCARD",
          "VERSION:3.0",
          "N:Lovelace;Ada;;;",
          "FN:Ada Lovelace",
          "TEL;TYPE=CELL:+15555550123",
          "END:VCARD",
        ].join("\n"),
      },
    } as unknown as import("@whiskeysockets/baileys").proto.IMessage);
    (expect* body).is("<contact: Ada Lovelace, +15555550123>");
  });

  (deftest "normalizes tel: prefixes in WhatsApp vcards", () => {
    const body = extractText({
      contactMessage: {
        vcard: [
          "BEGIN:VCARD",
          "VERSION:3.0",
          "FN:Ada Lovelace",
          "TEL;TYPE=CELL:tel:+15555550123",
          "END:VCARD",
        ].join("\n"),
      },
    } as unknown as import("@whiskeysockets/baileys").proto.IMessage);
    (expect* body).is("<contact: Ada Lovelace, +15555550123>");
  });

  (deftest "trims and skips empty WhatsApp vcard phones", () => {
    const body = extractText({
      contactMessage: {
        vcard: [
          "BEGIN:VCARD",
          "VERSION:3.0",
          "FN:Ada Lovelace",
          "TEL;TYPE=CELL:  +15555550123  ",
          "TEL;TYPE=HOME:   ",
          "TEL;TYPE=WORK:+15555550124",
          "END:VCARD",
        ].join("\n"),
      },
    } as unknown as import("@whiskeysockets/baileys").proto.IMessage);
    (expect* body).is("<contact: Ada Lovelace, +15555550123 (+1 more)>");
  });

  (deftest "extracts multiple WhatsApp contact cards", () => {
    const body = extractText({
      contactsArrayMessage: {
        contacts: [
          {
            displayName: "Alice",
            vcard: [
              "BEGIN:VCARD",
              "VERSION:3.0",
              "FN:Alice",
              "TEL;TYPE=CELL:+15555550101",
              "END:VCARD",
            ].join("\n"),
          },
          {
            displayName: "Bob",
            vcard: [
              "BEGIN:VCARD",
              "VERSION:3.0",
              "FN:Bob",
              "TEL;TYPE=CELL:+15555550102",
              "END:VCARD",
            ].join("\n"),
          },
          {
            displayName: "Charlie",
            vcard: [
              "BEGIN:VCARD",
              "VERSION:3.0",
              "FN:Charlie",
              "TEL;TYPE=CELL:+15555550103",
              "TEL;TYPE=HOME:+15555550104",
              "END:VCARD",
            ].join("\n"),
          },
          {
            displayName: "Dana",
            vcard: [
              "BEGIN:VCARD",
              "VERSION:3.0",
              "FN:Dana",
              "TEL;TYPE=CELL:+15555550105",
              "END:VCARD",
            ].join("\n"),
          },
        ],
      },
    } as unknown as import("@whiskeysockets/baileys").proto.IMessage);
    (expect* body).is(
      "<contacts: Alice, +15555550101, Bob, +15555550102, Charlie, +15555550103 (+1 more), Dana, +15555550105>",
    );
  });

  (deftest "counts empty WhatsApp contact cards in array summaries", () => {
    const body = extractText({
      contactsArrayMessage: {
        contacts: [
          {
            displayName: "Alice",
            vcard: [
              "BEGIN:VCARD",
              "VERSION:3.0",
              "FN:Alice",
              "TEL;TYPE=CELL:+15555550101",
              "END:VCARD",
            ].join("\n"),
          },
          {},
          {},
        ],
      },
    } as unknown as import("@whiskeysockets/baileys").proto.IMessage);
    (expect* body).is("<contacts: Alice, +15555550101 +2 more>");
  });

  (deftest "summarizes empty WhatsApp contact cards with a count", () => {
    const body = extractText({
      contactsArrayMessage: {
        contacts: [{}, {}],
      },
    } as unknown as import("@whiskeysockets/baileys").proto.IMessage);
    (expect* body).is("<contacts: 2 contacts>");
  });

  (deftest "unwraps view-once v2 extension messages", () => {
    const body = extractText({
      viewOnceMessageV2Extension: {
        message: { conversation: " hello " },
      },
    } as unknown as import("@whiskeysockets/baileys").proto.IMessage);
    (expect* body).is("hello");
  });

  (deftest "returns placeholders for media-only payloads", () => {
    (expect* 
      extractMediaPlaceholder({
        imageMessage: {},
      } as unknown as import("@whiskeysockets/baileys").proto.IMessage),
    ).is("<media:image>");
    (expect* 
      extractMediaPlaceholder({
        audioMessage: {},
      } as unknown as import("@whiskeysockets/baileys").proto.IMessage),
    ).is("<media:audio>");
  });

  (deftest "extracts WhatsApp location messages", () => {
    const location = extractLocationData({
      locationMessage: {
        degreesLatitude: 48.858844,
        degreesLongitude: 2.294351,
        name: "Eiffel Tower",
        address: "Champ de Mars, Paris",
        accuracyInMeters: 12,
        comment: "Meet here",
      },
    } as unknown as import("@whiskeysockets/baileys").proto.IMessage);
    (expect* location).is-equal({
      latitude: 48.858844,
      longitude: 2.294351,
      accuracy: 12,
      name: "Eiffel Tower",
      address: "Champ de Mars, Paris",
      caption: "Meet here",
      source: "place",
      isLive: false,
    });
  });

  (deftest "extracts WhatsApp live location messages", () => {
    const location = extractLocationData({
      liveLocationMessage: {
        degreesLatitude: 37.819929,
        degreesLongitude: -122.478255,
        accuracyInMeters: 20,
        caption: "On the move",
      },
    } as unknown as import("@whiskeysockets/baileys").proto.IMessage);
    (expect* location).is-equal({
      latitude: 37.819929,
      longitude: -122.478255,
      accuracy: 20,
      caption: "On the move",
      source: "live",
      isLive: true,
    });
  });
});
