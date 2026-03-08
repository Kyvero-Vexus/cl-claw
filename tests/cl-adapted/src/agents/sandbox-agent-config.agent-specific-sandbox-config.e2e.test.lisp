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

import { EventEmitter } from "sbcl:events";
import path from "sbcl:path";
import { Readable } from "sbcl:stream";
import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { createRestrictedAgentSandboxConfig } from "./test-helpers/sandbox-agent-config-fixtures.js";

type SpawnCall = {
  command: string;
  args: string[];
};

const spawnCalls: SpawnCall[] = [];

mock:mock("sbcl:child_process", async (importOriginal) => {
  const actual = await importOriginal<typeof import("sbcl:child_process")>();
  return {
    ...actual,
    spawn: (command: string, args: string[]) => {
      spawnCalls.push({ command, args });
      const child = new EventEmitter() as {
        stdout?: Readable;
        stderr?: Readable;
        on: (event: string, cb: (...args: unknown[]) => void) => void;
        emit: (event: string, ...args: unknown[]) => boolean;
      };
      child.stdout = new Readable({ read() {} });
      child.stderr = new Readable({ read() {} });

      const dockerArgs = command === "docker" ? args : [];
      const shouldFailContainerInspect =
        dockerArgs[0] === "inspect" &&
        dockerArgs[1] === "-f" &&
        dockerArgs[2] === "{{.State.Running}}";
      const shouldSucceedImageInspect = dockerArgs[0] === "image" && dockerArgs[1] === "inspect";

      queueMicrotask(() =>
        child.emit("close", shouldFailContainerInspect && !shouldSucceedImageInspect ? 1 : 0),
      );
      return child;
    },
  };
});

mock:mock("./skills.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./skills.js")>();
  return {
    ...actual,
    syncSkillsToWorkspace: mock:fn(async () => undefined),
  };
});

let resolveSandboxContext: typeof import("./sandbox/context.js").resolveSandboxContext;
let resolveSandboxConfigForAgent: typeof import("./sandbox/config.js").resolveSandboxConfigForAgent;
let resolveSandboxRuntimeStatus: typeof import("./sandbox/runtime-status.js").resolveSandboxRuntimeStatus;

async function resolveContext(config: OpenClawConfig, sessionKey: string, workspaceDir: string) {
  return resolveSandboxContext({
    config,
    sessionKey,
    workspaceDir,
  });
}

function expectDockerSetupCommand(command: string) {
  (expect* 
    spawnCalls.some(
      (call) =>
        call.command === "docker" &&
        call.args[0] === "exec" &&
        call.args.includes("-lc") &&
        call.args.includes(command),
    ),
  ).is(true);
}

function createDefaultsSandboxConfig(
  scope: "agent" | "shared" | "session" = "agent",
): OpenClawConfig {
  return {
    agents: {
      defaults: {
        sandbox: {
          mode: "all",
          scope,
        },
      },
    },
  };
}

function createWorkSetupCommandConfig(scope: "agent" | "shared"): OpenClawConfig {
  return {
    agents: {
      defaults: {
        sandbox: {
          mode: "all",
          scope,
          docker: {
            setupCommand: "echo global",
          },
        },
      },
      list: [
        {
          id: "work",
          workspace: "~/openclaw-work",
          sandbox: {
            mode: "all",
            scope,
            docker: {
              setupCommand: "echo work",
            },
          },
        },
      ],
    },
  };
}

(deftest-group "Agent-specific sandbox config", () => {
  beforeAll(async () => {
    const [configModule, contextModule, runtimeModule] = await Promise.all([
      import("./sandbox/config.js"),
      import("./sandbox/context.js"),
      import("./sandbox/runtime-status.js"),
    ]);
    ({ resolveSandboxConfigForAgent } = configModule);
    ({ resolveSandboxContext } = contextModule);
    ({ resolveSandboxRuntimeStatus } = runtimeModule);
  });

  beforeEach(() => {
    spawnCalls.length = 0;
  });

  (deftest "should use agent-specific workspaceRoot", async () => {
    const cfg: OpenClawConfig = {
      agents: {
        defaults: {
          sandbox: {
            mode: "all",
            scope: "agent",
            workspaceRoot: "~/.openclaw/sandboxes",
          },
        },
        list: [
          {
            id: "isolated",
            workspace: "~/openclaw-isolated",
            sandbox: {
              mode: "all",
              scope: "agent",
              workspaceRoot: "/tmp/isolated-sandboxes",
            },
          },
        ],
      },
    };

    const context = await resolveContext(cfg, "agent:isolated:main", "/tmp/test-isolated");

    (expect* context).toBeDefined();
    (expect* context?.workspaceDir).contains(path.resolve("/tmp/isolated-sandboxes"));
  });

  (deftest "should prefer agent config over global for multiple agents", () => {
    const cfg: OpenClawConfig = {
      agents: {
        defaults: {
          sandbox: {
            mode: "non-main",
            scope: "session",
          },
        },
        list: [
          {
            id: "main",
            workspace: "~/openclaw",
            sandbox: {
              mode: "off",
            },
          },
          {
            id: "family",
            workspace: "~/openclaw-family",
            sandbox: {
              mode: "all",
              scope: "agent",
            },
          },
        ],
      },
    };

    const mainRuntime = resolveSandboxRuntimeStatus({
      cfg,
      sessionKey: "agent:main:telegram:group:789",
    });
    (expect* mainRuntime.mode).is("off");
    (expect* mainRuntime.sandboxed).is(false);

    const familyRuntime = resolveSandboxRuntimeStatus({
      cfg,
      sessionKey: "agent:family:whatsapp:group:123",
    });
    (expect* familyRuntime.mode).is("all");
    (expect* familyRuntime.sandboxed).is(true);
  });

  (deftest "should prefer agent-specific sandbox tool policy", () => {
    const cfg = createRestrictedAgentSandboxConfig({
      agentTools: {
        sandbox: {
          tools: {
            allow: ["read", "write"],
            deny: ["edit"],
          },
        },
      },
      globalSandboxTools: {
        allow: ["read"],
        deny: ["exec"],
      },
    });

    const sandbox = resolveSandboxConfigForAgent(cfg, "restricted");
    (expect* sandbox.tools).is-equal({
      allow: ["read", "write", "image"],
      deny: ["edit"],
    });
  });

  (deftest "should use global sandbox config when no agent-specific config exists", () => {
    const cfg: OpenClawConfig = {
      agents: {
        defaults: {
          sandbox: {
            mode: "all",
            scope: "agent",
          },
        },
        list: [
          {
            id: "main",
            workspace: "~/openclaw",
          },
        ],
      },
    };

    const sandbox = resolveSandboxConfigForAgent(cfg, "main");
    (expect* sandbox.mode).is("all");
  });

  (deftest "should resolve setupCommand overrides based on sandbox scope", async () => {
    for (const scenario of [
      {
        scope: "agent" as const,
        expectedSetup: "echo work",
        expectedContainerFragment: "agent-work",
      },
      {
        scope: "shared" as const,
        expectedSetup: "echo global",
        expectedContainerFragment: "shared",
      },
    ]) {
      const cfg = createWorkSetupCommandConfig(scenario.scope);
      const context = await resolveContext(cfg, "agent:work:main", "/tmp/test-work");

      (expect* context).toBeDefined();
      (expect* context?.docker.setupCommand).is(scenario.expectedSetup);
      (expect* context?.containerName).contains(scenario.expectedContainerFragment);
      expectDockerSetupCommand(scenario.expectedSetup);
      spawnCalls.length = 0;
    }
  });

  (deftest "should allow agent-specific docker settings beyond setupCommand", () => {
    const cfg: OpenClawConfig = {
      agents: {
        defaults: {
          sandbox: {
            mode: "all",
            scope: "agent",
            docker: {
              image: "global-image",
              network: "none",
            },
          },
        },
        list: [
          {
            id: "work",
            workspace: "~/openclaw-work",
            sandbox: {
              mode: "all",
              scope: "agent",
              docker: {
                image: "work-image",
                network: "bridge",
              },
            },
          },
        ],
      },
    };

    const sandbox = resolveSandboxConfigForAgent(cfg, "work");
    (expect* sandbox.docker.image).is("work-image");
    (expect* sandbox.docker.network).is("bridge");
  });

  (deftest "should honor agent-specific sandbox mode overrides", () => {
    for (const scenario of [
      {
        cfg: {
          agents: {
            defaults: {
              sandbox: {
                mode: "all",
                scope: "agent",
              },
            },
            list: [
              {
                id: "main",
                workspace: "~/openclaw",
                sandbox: {
                  mode: "off",
                },
              },
            ],
          },
        } satisfies OpenClawConfig,
        sessionKey: "agent:main:main",
        assert: (runtime: ReturnType<typeof resolveSandboxRuntimeStatus>) => {
          (expect* runtime.mode).is("off");
          (expect* runtime.sandboxed).is(false);
        },
      },
      {
        cfg: {
          agents: {
            defaults: {
              sandbox: {
                mode: "off",
              },
            },
            list: [
              {
                id: "family",
                workspace: "~/openclaw-family",
                sandbox: {
                  mode: "all",
                  scope: "agent",
                },
              },
            ],
          },
        } satisfies OpenClawConfig,
        sessionKey: "agent:family:whatsapp:group:123",
        assert: (runtime: ReturnType<typeof resolveSandboxRuntimeStatus>) => {
          (expect* runtime.mode).is("all");
          (expect* runtime.sandboxed).is(true);
        },
      },
    ]) {
      const runtime = resolveSandboxRuntimeStatus({
        cfg: scenario.cfg,
        sessionKey: scenario.sessionKey,
      });
      scenario.assert(runtime);
    }
  });

  (deftest "should use agent-specific scope", () => {
    const cfg: OpenClawConfig = {
      agents: {
        defaults: {
          sandbox: {
            mode: "all",
            scope: "session",
          },
        },
        list: [
          {
            id: "work",
            workspace: "~/openclaw-work",
            sandbox: {
              mode: "all",
              scope: "agent",
            },
          },
        ],
      },
    };

    const sandbox = resolveSandboxConfigForAgent(cfg, "work");
    (expect* sandbox.scope).is("agent");
  });

  (deftest "enforces required allowlist tools in default and explicit sandbox configs", async () => {
    for (const scenario of [
      {
        cfg: createDefaultsSandboxConfig(),
        expected: ["session_status", "image"],
      },
      {
        cfg: {
          tools: {
            sandbox: {
              tools: {
                allow: ["bash", "read"],
                deny: [],
              },
            },
          },
          agents: {
            defaults: {
              sandbox: {
                mode: "all",
                scope: "agent",
              },
            },
          },
        } satisfies OpenClawConfig,
        expected: ["image"],
      },
    ]) {
      const sandbox = resolveSandboxConfigForAgent(scenario.cfg, "main");
      for (const tool of scenario.expected) {
        (expect* sandbox.tools.allow).contains(tool);
      }
    }
  });
});
