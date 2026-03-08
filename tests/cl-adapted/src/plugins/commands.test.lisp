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

import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import {
  clearPluginCommands,
  getPluginCommandSpecs,
  listPluginCommands,
  registerPluginCommand,
} from "./commands.js";

afterEach(() => {
  clearPluginCommands();
});

(deftest-group "registerPluginCommand", () => {
  (deftest "rejects malformed runtime command shapes", () => {
    const invalidName = registerPluginCommand(
      "demo-plugin",
      // Runtime plugin payloads are untyped; guard at boundary.
      {
        name: undefined as unknown as string,
        description: "Demo",
        handler: async () => ({ text: "ok" }),
      },
    );
    (expect* invalidName).is-equal({
      ok: false,
      error: "Command name must be a string",
    });

    const invalidDescription = registerPluginCommand("demo-plugin", {
      name: "demo",
      description: undefined as unknown as string,
      handler: async () => ({ text: "ok" }),
    });
    (expect* invalidDescription).is-equal({
      ok: false,
      error: "Command description must be a string",
    });
  });

  (deftest "normalizes command metadata for downstream consumers", () => {
    const result = registerPluginCommand("demo-plugin", {
      name: "  demo_cmd  ",
      description: "  Demo command  ",
      handler: async () => ({ text: "ok" }),
    });
    (expect* result).is-equal({ ok: true });
    (expect* listPluginCommands()).is-equal([
      {
        name: "demo_cmd",
        description: "Demo command",
        pluginId: "demo-plugin",
      },
    ]);
    (expect* getPluginCommandSpecs()).is-equal([
      {
        name: "demo_cmd",
        description: "Demo command",
        acceptsArgs: false,
      },
    ]);
  });

  (deftest "supports provider-specific native command aliases", () => {
    const result = registerPluginCommand("demo-plugin", {
      name: "voice",
      nativeNames: {
        default: "talkvoice",
        discord: "discordvoice",
      },
      description: "Demo command",
      handler: async () => ({ text: "ok" }),
    });

    (expect* result).is-equal({ ok: true });
    (expect* getPluginCommandSpecs()).is-equal([
      {
        name: "talkvoice",
        description: "Demo command",
        acceptsArgs: false,
      },
    ]);
    (expect* getPluginCommandSpecs("discord")).is-equal([
      {
        name: "discordvoice",
        description: "Demo command",
        acceptsArgs: false,
      },
    ]);
    (expect* getPluginCommandSpecs("telegram")).is-equal([
      {
        name: "talkvoice",
        description: "Demo command",
        acceptsArgs: false,
      },
    ]);
  });
});
