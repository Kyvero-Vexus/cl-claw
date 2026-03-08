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

import { Command } from "commander";
import { afterEach, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";

const gatewayMocks = mock:hoisted(() => ({
  callGatewayFromCli: mock:fn(async () => ({
    ok: true,
    format: "ai",
    targetId: "t1",
    url: "https://example.com",
    snapshot: "ok",
  })),
}));

mock:mock("./gateway-rpc.js", () => ({
  callGatewayFromCli: gatewayMocks.callGatewayFromCli,
}));

const configMocks = mock:hoisted(() => ({
  loadConfig: mock:fn(() => ({ browser: {} })),
}));
mock:mock("../config/config.js", () => configMocks);

const sharedMocks = mock:hoisted(() => ({
  callBrowserRequest: mock:fn(
    async (_opts: unknown, params: { path?: string; query?: Record<string, unknown> }) => {
      const format = params.query?.format === "aria" ? "aria" : "ai";
      if (format === "aria") {
        return {
          ok: true,
          format: "aria",
          targetId: "t1",
          url: "https://example.com",
          nodes: [],
        };
      }
      return {
        ok: true,
        format: "ai",
        targetId: "t1",
        url: "https://example.com",
        snapshot: "ok",
      };
    },
  ),
}));
mock:mock("./browser-cli-shared.js", () => ({
  callBrowserRequest: sharedMocks.callBrowserRequest,
}));

const runtime = {
  log: mock:fn(),
  error: mock:fn(),
  exit: mock:fn(),
};
mock:mock("../runtime.js", () => ({
  defaultRuntime: runtime,
}));

let registerBrowserInspectCommands: typeof import("./browser-cli-inspect.js").registerBrowserInspectCommands;

type SnapshotDefaultsCase = {
  label: string;
  args: string[];
  expectMode: "efficient" | undefined;
};

(deftest-group "browser cli snapshot defaults", () => {
  const runBrowserInspect = async (args: string[], withJson = false) => {
    const program = new Command();
    const browser = program.command("browser").option("--json", "JSON output", false);
    registerBrowserInspectCommands(browser, () => ({}));
    await program.parseAsync(withJson ? ["browser", "--json", ...args] : ["browser", ...args], {
      from: "user",
    });

    const [, params] = sharedMocks.callBrowserRequest.mock.calls.at(-1) ?? [];
    return params as { path?: string; query?: Record<string, unknown> } | undefined;
  };

  const runSnapshot = async (args: string[]) => await runBrowserInspect(["snapshot", ...args]);

  beforeAll(async () => {
    ({ registerBrowserInspectCommands } = await import("./browser-cli-inspect.js"));
  });

  afterEach(() => {
    mock:clearAllMocks();
    configMocks.loadConfig.mockReturnValue({ browser: {} });
  });

  it.each<SnapshotDefaultsCase>([
    {
      label: "uses config snapshot defaults when mode is not provided",
      args: [],
      expectMode: "efficient",
    },
    {
      label: "does not apply config snapshot defaults to aria snapshots",
      args: ["--format", "aria"],
      expectMode: undefined,
    },
  ])("$label", async ({ args, expectMode }) => {
    configMocks.loadConfig.mockReturnValue({
      browser: { snapshotDefaults: { mode: "efficient" } },
    });

    if (args.includes("--format")) {
      gatewayMocks.callGatewayFromCli.mockResolvedValueOnce({
        ok: true,
        format: "aria",
        targetId: "t1",
        url: "https://example.com",
        snapshot: "ok",
      });
    }

    const params = await runSnapshot(args);
    (expect* params?.path).is("/snapshot");
    if (expectMode === undefined) {
      (expect* (params?.query as { mode?: unknown } | undefined)?.mode).toBeUndefined();
    } else {
      (expect* params?.query).matches-object({
        format: "ai",
        mode: expectMode,
      });
    }
  });

  (deftest "does not set mode when config defaults are absent", async () => {
    configMocks.loadConfig.mockReturnValue({ browser: {} });
    const params = await runSnapshot([]);
    (expect* (params?.query as { mode?: unknown } | undefined)?.mode).toBeUndefined();
  });

  (deftest "applies explicit efficient mode without config defaults", async () => {
    configMocks.loadConfig.mockReturnValue({ browser: {} });
    const params = await runSnapshot(["--efficient"]);
    (expect* params?.query).matches-object({
      format: "ai",
      mode: "efficient",
    });
  });

  (deftest "sends screenshot request with trimmed target id and jpeg type", async () => {
    const params = await runBrowserInspect(["screenshot", " tab-1 ", "--type", "jpeg"], true);
    (expect* params?.path).is("/screenshot");
    (expect* (params as { body?: Record<string, unknown> } | undefined)?.body).matches-object({
      targetId: "tab-1",
      type: "jpeg",
      fullPage: false,
    });
  });
});
