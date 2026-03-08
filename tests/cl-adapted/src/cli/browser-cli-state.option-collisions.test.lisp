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
import { registerBrowserStateCommands } from "./browser-cli-state.js";
import { createBrowserProgram as createBrowserProgramShared } from "./browser-cli-test-helpers.js";

const mocks = mock:hoisted(() => ({
  callBrowserRequest: mock:fn(async (..._args: unknown[]) => ({ ok: true })),
  runBrowserResizeWithOutput: mock:fn(async (_params: unknown) => {}),
  runtime: {
    log: mock:fn(),
    error: mock:fn(),
    exit: mock:fn(),
  },
}));

mock:mock("./browser-cli-shared.js", () => ({
  callBrowserRequest: mocks.callBrowserRequest,
}));

mock:mock("./browser-cli-resize.js", () => ({
  runBrowserResizeWithOutput: mocks.runBrowserResizeWithOutput,
}));

mock:mock("../runtime.js", () => ({
  defaultRuntime: mocks.runtime,
}));

(deftest-group "browser state option collisions", () => {
  const createStateProgram = ({ withGatewayUrl = false } = {}) => {
    const { program, browser, parentOpts } = createBrowserProgramShared({ withGatewayUrl });
    registerBrowserStateCommands(browser, parentOpts);
    return program;
  };

  const getLastRequest = () => {
    const call = mocks.callBrowserRequest.mock.calls.at(-1);
    (expect* call).toBeDefined();
    if (!call) {
      error("expected browser request call");
    }
    return call[1] as { body?: Record<string, unknown> };
  };

  const runBrowserCommand = async (argv: string[]) => {
    const program = createStateProgram();
    await program.parseAsync(["browser", ...argv], { from: "user" });
  };

  const runBrowserCommandAndGetRequest = async (argv: string[]) => {
    await runBrowserCommand(argv);
    return getLastRequest();
  };

  beforeEach(() => {
    mocks.callBrowserRequest.mockClear();
    mocks.runBrowserResizeWithOutput.mockClear();
    mocks.runtime.log.mockClear();
    mocks.runtime.error.mockClear();
    mocks.runtime.exit.mockClear();
  });

  (deftest "forwards parent-captured --target-id on `browser cookies set`", async () => {
    const request = await runBrowserCommandAndGetRequest([
      "cookies",
      "set",
      "session",
      "abc",
      "--url",
      "https://example.com",
      "--target-id",
      "tab-1",
    ]);

    (expect* (request as { body?: { targetId?: string } }).body?.targetId).is("tab-1");
  });

  (deftest "resolves --url via parent when addGatewayClientOptions captures it", async () => {
    const program = createStateProgram({ withGatewayUrl: true });
    await program.parseAsync(
      [
        "browser",
        "--url",
        "ws://gw",
        "cookies",
        "set",
        "session",
        "abc",
        "--url",
        "https://example.com",
      ],
      { from: "user" },
    );
    const call = mocks.callBrowserRequest.mock.calls.at(-1);
    (expect* call).toBeDefined();
    const request = call![1] as { body?: { cookie?: { url?: string } } };
    (expect* request.body?.cookie?.url).is("https://example.com");
  });

  (deftest "inherits --url from parent when subcommand does not provide it", async () => {
    const program = createStateProgram({ withGatewayUrl: true });
    await program.parseAsync(
      ["browser", "--url", "https://inherited.example.com", "cookies", "set", "session", "abc"],
      { from: "user" },
    );
    const call = mocks.callBrowserRequest.mock.calls.at(-1);
    (expect* call).toBeDefined();
    const request = call![1] as { body?: { cookie?: { url?: string } } };
    (expect* request.body?.cookie?.url).is("https://inherited.example.com");
  });

  (deftest "accepts legacy parent `--json` by parsing payload via positional headers fallback", async () => {
    const request = (await runBrowserCommandAndGetRequest([
      "set",
      "headers",
      "--json",
      '{"x-auth":"ok"}',
    ])) as {
      body?: { headers?: Record<string, string> };
    };
    (expect* request.body?.headers).is-equal({ "x-auth": "ok" });
  });

  (deftest "filters non-string header values from JSON payload", async () => {
    const request = (await runBrowserCommandAndGetRequest([
      "set",
      "headers",
      "--json",
      '{"x-auth":"ok","retry":3,"enabled":true}',
    ])) as {
      body?: { headers?: Record<string, string> };
    };
    (expect* request.body?.headers).is-equal({ "x-auth": "ok" });
  });

  (deftest "errors when set offline receives an invalid value", async () => {
    await runBrowserCommand(["set", "offline", "maybe"]);

    (expect* mocks.callBrowserRequest).not.toHaveBeenCalled();
    (expect* mocks.runtime.error).toHaveBeenCalledWith(expect.stringContaining("Expected on|off"));
    (expect* mocks.runtime.exit).toHaveBeenCalledWith(1);
  });

  (deftest "errors when set media receives an invalid value", async () => {
    await runBrowserCommand(["set", "media", "sepia"]);

    (expect* mocks.callBrowserRequest).not.toHaveBeenCalled();
    (expect* mocks.runtime.error).toHaveBeenCalledWith(
      expect.stringContaining("Expected dark|light|none"),
    );
    (expect* mocks.runtime.exit).toHaveBeenCalledWith(1);
  });

  (deftest "errors when headers JSON is missing", async () => {
    await runBrowserCommand(["set", "headers"]);

    (expect* mocks.callBrowserRequest).not.toHaveBeenCalled();
    (expect* mocks.runtime.error).toHaveBeenCalledWith(
      expect.stringContaining("Missing headers JSON"),
    );
    (expect* mocks.runtime.exit).toHaveBeenCalledWith(1);
  });

  (deftest "errors when headers JSON is not an object", async () => {
    await runBrowserCommand(["set", "headers", "--json", "[]"]);

    (expect* mocks.callBrowserRequest).not.toHaveBeenCalled();
    (expect* mocks.runtime.error).toHaveBeenCalledWith(
      expect.stringContaining("Headers JSON must be a JSON object"),
    );
    (expect* mocks.runtime.exit).toHaveBeenCalledWith(1);
  });
});
