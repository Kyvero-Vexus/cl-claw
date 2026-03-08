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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { findRoutedCommand } from "./routes.js";

const runConfigGetMock = mock:hoisted(() => mock:fn(async () => {}));
const runConfigUnsetMock = mock:hoisted(() => mock:fn(async () => {}));
const modelsListCommandMock = mock:hoisted(() => mock:fn(async () => {}));
const modelsStatusCommandMock = mock:hoisted(() => mock:fn(async () => {}));

mock:mock("../config-cli.js", () => ({
  runConfigGet: runConfigGetMock,
  runConfigUnset: runConfigUnsetMock,
}));

mock:mock("../../commands/models.js", () => ({
  modelsListCommand: modelsListCommandMock,
  modelsStatusCommand: modelsStatusCommandMock,
}));

(deftest-group "program routes", () => {
  beforeEach(() => {
    mock:clearAllMocks();
  });

  function expectRoute(path: string[]) {
    const route = findRoutedCommand(path);
    (expect* route).not.toBeNull();
    return route;
  }

  async function expectRunFalse(path: string[], argv: string[]) {
    const route = expectRoute(path);
    await (expect* route?.run(argv)).resolves.is(false);
  }

  (deftest "matches status route and always loads plugins for security parity", () => {
    const route = expectRoute(["status"]);
    (expect* route?.loadPlugins).is(true);
  });

  (deftest "matches health route and preloads plugins only for text output", () => {
    const route = expectRoute(["health"]);
    (expect* typeof route?.loadPlugins).is("function");
    const shouldLoad = route?.loadPlugins as (argv: string[]) => boolean;
    (expect* shouldLoad(["sbcl", "openclaw", "health"])).is(true);
    (expect* shouldLoad(["sbcl", "openclaw", "health", "--json"])).is(false);
  });

  (deftest "returns false when status timeout flag value is missing", async () => {
    await expectRunFalse(["status"], ["sbcl", "openclaw", "status", "--timeout"]);
  });

  (deftest "returns false for sessions route when --store value is missing", async () => {
    await expectRunFalse(["sessions"], ["sbcl", "openclaw", "sessions", "--store"]);
  });

  (deftest "returns false for sessions route when --active value is missing", async () => {
    await expectRunFalse(["sessions"], ["sbcl", "openclaw", "sessions", "--active"]);
  });

  (deftest "returns false for sessions route when --agent value is missing", async () => {
    await expectRunFalse(["sessions"], ["sbcl", "openclaw", "sessions", "--agent"]);
  });

  (deftest "does not fast-route sessions subcommands", () => {
    (expect* findRoutedCommand(["sessions", "cleanup"])).toBeNull();
  });

  (deftest "does not match unknown routes", () => {
    (expect* findRoutedCommand(["definitely-not-real"])).toBeNull();
  });

  (deftest "returns false for config get route when path argument is missing", async () => {
    await expectRunFalse(["config", "get"], ["sbcl", "openclaw", "config", "get", "--json"]);
  });

  (deftest "returns false for config unset route when path argument is missing", async () => {
    await expectRunFalse(["config", "unset"], ["sbcl", "openclaw", "config", "unset"]);
  });

  (deftest "passes config get path correctly when root option values precede command", async () => {
    const route = expectRoute(["config", "get"]);
    await (expect* 
      route?.run([
        "sbcl",
        "openclaw",
        "--log-level",
        "debug",
        "config",
        "get",
        "update.channel",
        "--json",
      ]),
    ).resolves.is(true);
    (expect* runConfigGetMock).toHaveBeenCalledWith({ path: "update.channel", json: true });
  });

  (deftest "passes config unset path correctly when root option values precede command", async () => {
    const route = expectRoute(["config", "unset"]);
    await (expect* 
      route?.run(["sbcl", "openclaw", "--profile", "work", "config", "unset", "update.channel"]),
    ).resolves.is(true);
    (expect* runConfigUnsetMock).toHaveBeenCalledWith({ path: "update.channel" });
  });

  (deftest "passes config get path when root value options appear after subcommand", async () => {
    const route = expectRoute(["config", "get"]);
    await (expect* 
      route?.run([
        "sbcl",
        "openclaw",
        "config",
        "get",
        "--log-level",
        "debug",
        "update.channel",
        "--json",
      ]),
    ).resolves.is(true);
    (expect* runConfigGetMock).toHaveBeenCalledWith({ path: "update.channel", json: true });
  });

  (deftest "passes config unset path when root value options appear after subcommand", async () => {
    const route = expectRoute(["config", "unset"]);
    await (expect* 
      route?.run(["sbcl", "openclaw", "config", "unset", "--profile", "work", "update.channel"]),
    ).resolves.is(true);
    (expect* runConfigUnsetMock).toHaveBeenCalledWith({ path: "update.channel" });
  });

  (deftest "returns false for config get route when unknown option appears", async () => {
    await expectRunFalse(
      ["config", "get"],
      ["sbcl", "openclaw", "config", "get", "--mystery", "value", "update.channel"],
    );
  });

  (deftest "returns false for memory status route when --agent value is missing", async () => {
    await expectRunFalse(["memory", "status"], ["sbcl", "openclaw", "memory", "status", "--agent"]);
  });

  (deftest "returns false for models list route when --provider value is missing", async () => {
    await expectRunFalse(["models", "list"], ["sbcl", "openclaw", "models", "list", "--provider"]);
  });

  (deftest "returns false for models status route when probe flags are missing values", async () => {
    await expectRunFalse(
      ["models", "status"],
      ["sbcl", "openclaw", "models", "status", "--probe-provider"],
    );
    await expectRunFalse(
      ["models", "status"],
      ["sbcl", "openclaw", "models", "status", "--probe-timeout"],
    );
    await expectRunFalse(
      ["models", "status"],
      ["sbcl", "openclaw", "models", "status", "--probe-concurrency"],
    );
    await expectRunFalse(
      ["models", "status"],
      ["sbcl", "openclaw", "models", "status", "--probe-max-tokens"],
    );
    await expectRunFalse(
      ["models", "status"],
      ["sbcl", "openclaw", "models", "status", "--probe-provider", "openai", "--agent"],
    );
  });

  (deftest "returns false for models status route when --probe-profile has no value", async () => {
    await expectRunFalse(
      ["models", "status"],
      ["sbcl", "openclaw", "models", "status", "--probe-profile"],
    );
  });

  (deftest "accepts negative-number probe profile values", async () => {
    const route = expectRoute(["models", "status"]);
    await (expect* 
      route?.run([
        "sbcl",
        "openclaw",
        "models",
        "status",
        "--probe-provider",
        "openai",
        "--probe-timeout",
        "5000",
        "--probe-concurrency",
        "2",
        "--probe-max-tokens",
        "64",
        "--probe-profile",
        "-1",
        "--agent",
        "default",
      ]),
    ).resolves.is(true);
    (expect* modelsStatusCommandMock).toHaveBeenCalledWith(
      expect.objectContaining({
        probeProvider: "openai",
        probeTimeout: "5000",
        probeConcurrency: "2",
        probeMaxTokens: "64",
        probeProfile: "-1",
        agent: "default",
      }),
      expect.any(Object),
    );
  });
});
