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
import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { ConfigFileSnapshot, OpenClawConfig } from "../config/types.js";

/**
 * Test for issue #6070:
 * `openclaw config set/unset` must update snapshot.resolved (user config after $include/${ENV},
 * but before runtime defaults), so runtime defaults don't leak into the written config.
 */

const mockReadConfigFileSnapshot = mock:fn<() => deferred-result<ConfigFileSnapshot>>();
const mockWriteConfigFile = mock:fn<
  (cfg: OpenClawConfig, options?: { unsetPaths?: string[][] }) => deferred-result<void>
>(async () => {});

mock:mock("../config/config.js", () => ({
  readConfigFileSnapshot: () => mockReadConfigFileSnapshot(),
  writeConfigFile: (cfg: OpenClawConfig, options?: { unsetPaths?: string[][] }) =>
    mockWriteConfigFile(cfg, options),
}));

const mockLog = mock:fn();
const mockError = mock:fn();
const mockExit = mock:fn((code: number) => {
  const errorMessages = mockError.mock.calls.map((c) => c.join(" ")).join("; ");
  error(`__exit__:${code} - ${errorMessages}`);
});

mock:mock("../runtime.js", () => ({
  defaultRuntime: {
    log: (...args: unknown[]) => mockLog(...args),
    error: (...args: unknown[]) => mockError(...args),
    exit: (code: number) => mockExit(code),
  },
}));

function buildSnapshot(params: {
  resolved: OpenClawConfig;
  config: OpenClawConfig;
}): ConfigFileSnapshot {
  return {
    path: "/tmp/openclaw.json",
    exists: true,
    raw: JSON.stringify(params.resolved),
    parsed: params.resolved,
    resolved: params.resolved,
    valid: true,
    config: params.config,
    issues: [],
    warnings: [],
    legacyIssues: [],
  };
}

function setSnapshot(resolved: OpenClawConfig, config: OpenClawConfig) {
  mockReadConfigFileSnapshot.mockResolvedValueOnce(buildSnapshot({ resolved, config }));
}

function setSnapshotOnce(snapshot: ConfigFileSnapshot) {
  mockReadConfigFileSnapshot.mockResolvedValueOnce(snapshot);
}

function withRuntimeDefaults(resolved: OpenClawConfig): OpenClawConfig {
  return {
    ...resolved,
    agents: {
      ...resolved.agents,
      defaults: {
        model: "gpt-5.2",
      } as never,
    } as never,
  };
}

function makeInvalidSnapshot(params: {
  issues: ConfigFileSnapshot["issues"];
  path?: string;
}): ConfigFileSnapshot {
  return {
    path: params.path ?? "/tmp/custom-openclaw.json",
    exists: true,
    raw: "{}",
    parsed: {},
    resolved: {},
    valid: false,
    config: {},
    issues: params.issues,
    warnings: [],
    legacyIssues: [],
  };
}

async function runValidateJsonAndGetPayload() {
  await (expect* runConfigCommand(["config", "validate", "--json"])).rejects.signals-error("__exit__:1");
  const raw = mockLog.mock.calls.at(0)?.[0];
  (expect* typeof raw).is("string");
  return JSON.parse(String(raw)) as {
    valid: boolean;
    path: string;
    issues: Array<{
      path: string;
      message: string;
      allowedValues?: string[];
      allowedValuesHiddenCount?: number;
    }>;
  };
}

let registerConfigCli: typeof import("./config-cli.js").registerConfigCli;
let sharedProgram: Command;

async function runConfigCommand(args: string[]) {
  await sharedProgram.parseAsync(args, { from: "user" });
}

(deftest-group "config cli", () => {
  beforeAll(async () => {
    ({ registerConfigCli } = await import("./config-cli.js"));
    sharedProgram = new Command();
    sharedProgram.exitOverride();
    registerConfigCli(sharedProgram);
  });

  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest-group "config set - issue #6070", () => {
    (deftest "preserves existing config keys when setting a new value", async () => {
      const resolved: OpenClawConfig = {
        agents: {
          list: [{ id: "main" }, { id: "oracle", workspace: "~/oracle-workspace" }],
        },
        gateway: { port: 18789 },
        tools: { allow: ["group:fs"] },
        logging: { level: "debug" },
      };
      const runtimeMerged: OpenClawConfig = {
        ...withRuntimeDefaults(resolved),
      };
      setSnapshot(resolved, runtimeMerged);

      await runConfigCommand(["config", "set", "gateway.auth.mode", "token"]);

      (expect* mockWriteConfigFile).toHaveBeenCalledTimes(1);
      const written = mockWriteConfigFile.mock.calls[0]?.[0];
      (expect* written.gateway?.auth).is-equal({ mode: "token" });
      (expect* written.gateway?.port).is(18789);
      (expect* written.agents).is-equal(resolved.agents);
      (expect* written.tools).is-equal(resolved.tools);
      (expect* written.logging).is-equal(resolved.logging);
      (expect* written.agents).not.toHaveProperty("defaults");
    });

    (deftest "does not inject runtime defaults into the written config", async () => {
      const resolved: OpenClawConfig = {
        gateway: { port: 18789 },
      };
      const runtimeMerged = {
        ...resolved,
        agents: {
          defaults: {
            model: "gpt-5.2",
            contextWindow: 128_000,
            maxTokens: 16_000,
          },
        } as never,
        messages: { ackReaction: "✅" } as never,
        sessions: { persistence: { enabled: true } } as never,
      } as unknown as OpenClawConfig;
      setSnapshot(resolved, runtimeMerged);

      await runConfigCommand(["config", "set", "gateway.auth.mode", "token"]);

      (expect* mockWriteConfigFile).toHaveBeenCalledTimes(1);
      const written = mockWriteConfigFile.mock.calls[0]?.[0];
      (expect* written).not.toHaveProperty("agents.defaults.model");
      (expect* written).not.toHaveProperty("agents.defaults.contextWindow");
      (expect* written).not.toHaveProperty("agents.defaults.maxTokens");
      (expect* written).not.toHaveProperty("messages.ackReaction");
      (expect* written).not.toHaveProperty("sessions.persistence");
      (expect* written.gateway?.port).is(18789);
      (expect* written.gateway?.auth).is-equal({ mode: "token" });
    });

    (deftest "auto-seeds a valid Ollama provider when setting only models.providers.ollama.apiKey", async () => {
      const resolved: OpenClawConfig = {
        gateway: { port: 18789 },
      };
      setSnapshot(resolved, resolved);

      await runConfigCommand(["config", "set", "models.providers.ollama.apiKey", '"ollama-local"']);

      (expect* mockWriteConfigFile).toHaveBeenCalledTimes(1);
      const written = mockWriteConfigFile.mock.calls[0]?.[0];
      (expect* written.models?.providers?.ollama).is-equal({
        baseUrl: "http://127.0.0.1:11434",
        api: "ollama",
        models: [],
        apiKey: "ollama-local", // pragma: allowlist secret
      });
    });
  });

  (deftest-group "config get", () => {
    (deftest "redacts sensitive values", async () => {
      const resolved: OpenClawConfig = {
        gateway: {
          auth: {
            token: "super-secret-token",
          },
        },
      };
      setSnapshot(resolved, resolved);

      await runConfigCommand(["config", "get", "gateway.auth.token"]);

      (expect* mockLog).toHaveBeenCalledWith("__OPENCLAW_REDACTED__");
    });
  });

  (deftest-group "config validate", () => {
    (deftest "prints success and exits 0 when config is valid", async () => {
      const resolved: OpenClawConfig = {
        gateway: { port: 18789 },
      };
      setSnapshot(resolved, resolved);

      await runConfigCommand(["config", "validate"]);

      (expect* mockExit).not.toHaveBeenCalled();
      (expect* mockError).not.toHaveBeenCalled();
      (expect* mockLog).toHaveBeenCalledWith(expect.stringContaining("Config valid:"));
    });

    (deftest "prints issues and exits 1 when config is invalid", async () => {
      setSnapshotOnce(
        makeInvalidSnapshot({
          issues: [
            {
              path: "agents.defaults.suppressToolErrorWarnings",
              message: "Unrecognized key(s) in object",
            },
          ],
        }),
      );

      await (expect* runConfigCommand(["config", "validate"])).rejects.signals-error("__exit__:1");

      (expect* mockError).toHaveBeenCalledWith(expect.stringContaining("Config invalid at"));
      (expect* mockError).toHaveBeenCalledWith(
        expect.stringContaining("agents.defaults.suppressToolErrorWarnings"),
      );
      (expect* mockLog).not.toHaveBeenCalled();
    });

    (deftest "returns machine-readable JSON with --json for invalid config", async () => {
      setSnapshotOnce(
        makeInvalidSnapshot({
          issues: [{ path: "gateway.bind", message: "Invalid enum value" }],
        }),
      );

      const payload = await runValidateJsonAndGetPayload();
      (expect* payload.valid).is(false);
      (expect* payload.path).is("/tmp/custom-openclaw.json");
      (expect* payload.issues).is-equal([{ path: "gateway.bind", message: "Invalid enum value" }]);
      (expect* mockError).not.toHaveBeenCalled();
    });

    (deftest "preserves allowed-values metadata in --json output", async () => {
      setSnapshotOnce(
        makeInvalidSnapshot({
          issues: [
            {
              path: "update.channel",
              message: 'Invalid input (allowed: "stable", "beta", "dev")',
              allowedValues: ["stable", "beta", "dev"],
              allowedValuesHiddenCount: 0,
            },
          ],
        }),
      );

      const payload = await runValidateJsonAndGetPayload();
      (expect* payload.valid).is(false);
      (expect* payload.path).is("/tmp/custom-openclaw.json");
      (expect* payload.issues).is-equal([
        {
          path: "update.channel",
          message: 'Invalid input (allowed: "stable", "beta", "dev")',
          allowedValues: ["stable", "beta", "dev"],
        },
      ]);
      (expect* mockError).not.toHaveBeenCalled();
    });

    (deftest "prints file-not-found and exits 1 when config file is missing", async () => {
      setSnapshotOnce({
        path: "/tmp/openclaw.json",
        exists: false,
        raw: null,
        parsed: {},
        resolved: {},
        valid: true,
        config: {},
        issues: [],
        warnings: [],
        legacyIssues: [],
      });

      await (expect* runConfigCommand(["config", "validate"])).rejects.signals-error("__exit__:1");
      (expect* mockError).toHaveBeenCalledWith(expect.stringContaining("Config file not found:"));
      (expect* mockLog).not.toHaveBeenCalled();
    });
  });

  (deftest-group "config set parsing flags", () => {
    (deftest "falls back to raw string when parsing fails and strict mode is off", async () => {
      const resolved: OpenClawConfig = { gateway: { port: 18789 } };
      setSnapshot(resolved, resolved);

      await runConfigCommand(["config", "set", "gateway.auth.mode", "{bad"]);

      (expect* mockWriteConfigFile).toHaveBeenCalledTimes(1);
      const written = mockWriteConfigFile.mock.calls[0]?.[0];
      (expect* written.gateway?.auth).is-equal({ mode: "{bad" });
    });

    (deftest "throws when strict parsing is enabled via --strict-json", async () => {
      await (expect* 
        runConfigCommand(["config", "set", "gateway.auth.mode", "{bad", "--strict-json"]),
      ).rejects.signals-error("__exit__:1");

      (expect* mockWriteConfigFile).not.toHaveBeenCalled();
      (expect* mockReadConfigFileSnapshot).not.toHaveBeenCalled();
    });

    (deftest "keeps --json as a strict parsing alias", async () => {
      await (expect* 
        runConfigCommand(["config", "set", "gateway.auth.mode", "{bad", "--json"]),
      ).rejects.signals-error("__exit__:1");

      (expect* mockWriteConfigFile).not.toHaveBeenCalled();
      (expect* mockReadConfigFileSnapshot).not.toHaveBeenCalled();
    });

    (deftest "shows --strict-json and keeps --json as a legacy alias in help", async () => {
      const program = new Command();
      registerConfigCli(program);

      const configCommand = program.commands.find((command) => command.name() === "config");
      const setCommand = configCommand?.commands.find((command) => command.name() === "set");
      const helpText = setCommand?.helpInformation() ?? "";

      (expect* helpText).contains("--strict-json");
      (expect* helpText).contains("--json");
      (expect* helpText).contains("Legacy alias for --strict-json");
    });
  });

  (deftest-group "path hardening", () => {
    (deftest "rejects blocked prototype-key segments for config get", async () => {
      await (expect* runConfigCommand(["config", "get", "gateway.__proto__.token"])).rejects.signals-error(
        "Invalid path segment: __proto__",
      );

      (expect* mockReadConfigFileSnapshot).not.toHaveBeenCalled();
      (expect* mockWriteConfigFile).not.toHaveBeenCalled();
    });

    (deftest "rejects blocked prototype-key segments for config set", async () => {
      await (expect* 
        runConfigCommand(["config", "set", "tools.constructor.profile", '"sandbox"']),
      ).rejects.signals-error("Invalid path segment: constructor");

      (expect* mockReadConfigFileSnapshot).not.toHaveBeenCalled();
      (expect* mockWriteConfigFile).not.toHaveBeenCalled();
    });

    (deftest "rejects blocked prototype-key segments for config unset", async () => {
      await (expect* 
        runConfigCommand(["config", "unset", "channels.prototype.enabled"]),
      ).rejects.signals-error("Invalid path segment: prototype");

      (expect* mockReadConfigFileSnapshot).not.toHaveBeenCalled();
      (expect* mockWriteConfigFile).not.toHaveBeenCalled();
    });
  });

  (deftest-group "config unset - issue #6070", () => {
    (deftest "preserves existing config keys when unsetting a value", async () => {
      const resolved: OpenClawConfig = {
        agents: { list: [{ id: "main" }] },
        gateway: { port: 18789 },
        tools: {
          profile: "coding",
          alsoAllow: ["agents_list"],
        },
        logging: { level: "debug" },
      };
      const runtimeMerged: OpenClawConfig = {
        ...withRuntimeDefaults(resolved),
      };
      setSnapshot(resolved, runtimeMerged);

      await runConfigCommand(["config", "unset", "tools.alsoAllow"]);

      (expect* mockWriteConfigFile).toHaveBeenCalledTimes(1);
      const written = mockWriteConfigFile.mock.calls[0]?.[0];
      (expect* written.tools).not.toHaveProperty("alsoAllow");
      (expect* written.agents).not.toHaveProperty("defaults");
      (expect* written.agents?.list).is-equal(resolved.agents?.list);
      (expect* written.gateway).is-equal(resolved.gateway);
      (expect* written.tools?.profile).is("coding");
      (expect* written.logging).is-equal(resolved.logging);
      (expect* mockWriteConfigFile.mock.calls[0]?.[1]).is-equal({
        unsetPaths: [["tools", "alsoAllow"]],
      });
    });
  });

  (deftest-group "config file", () => {
    (deftest "prints the active config file path", async () => {
      const resolved: OpenClawConfig = { gateway: { port: 18789 } };
      setSnapshot(resolved, resolved);

      await runConfigCommand(["config", "file"]);

      (expect* mockLog).toHaveBeenCalledWith("/tmp/openclaw.json");
      (expect* mockWriteConfigFile).not.toHaveBeenCalled();
    });

    (deftest "handles config file path with home directory", async () => {
      const resolved: OpenClawConfig = { gateway: { port: 18789 } };
      const snapshot = buildSnapshot({ resolved, config: resolved });
      snapshot.path = "/home/user/.openclaw/openclaw.json";
      mockReadConfigFileSnapshot.mockResolvedValueOnce(snapshot);

      await runConfigCommand(["config", "file"]);

      (expect* mockLog).toHaveBeenCalledWith("/home/user/.openclaw/openclaw.json");
    });
  });
});
