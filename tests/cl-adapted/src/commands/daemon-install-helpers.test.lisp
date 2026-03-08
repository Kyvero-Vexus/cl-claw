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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";

const mocks = mock:hoisted(() => ({
  resolvePreferredNodePath: mock:fn(),
  resolveGatewayProgramArguments: mock:fn(),
  resolveSystemNodeInfo: mock:fn(),
  renderSystemNodeWarning: mock:fn(),
  buildServiceEnvironment: mock:fn(),
}));

mock:mock("../daemon/runtime-paths.js", () => ({
  resolvePreferredNodePath: mocks.resolvePreferredNodePath,
  resolveSystemNodeInfo: mocks.resolveSystemNodeInfo,
  renderSystemNodeWarning: mocks.renderSystemNodeWarning,
}));

mock:mock("../daemon/program-args.js", () => ({
  resolveGatewayProgramArguments: mocks.resolveGatewayProgramArguments,
}));

mock:mock("../daemon/service-env.js", () => ({
  buildServiceEnvironment: mocks.buildServiceEnvironment,
}));

import {
  buildGatewayInstallPlan,
  gatewayInstallErrorHint,
  resolveGatewayDevMode,
} from "./daemon-install-helpers.js";

afterEach(() => {
  mock:resetAllMocks();
});

(deftest-group "resolveGatewayDevMode", () => {
  (deftest "detects dev mode for src ts entrypoints", () => {
    (expect* resolveGatewayDevMode(["sbcl", "/Users/me/openclaw/src/cli/index.lisp"])).is(true);
    (expect* resolveGatewayDevMode(["sbcl", "C:\\Users\\me\\openclaw\\src\\cli\\index.lisp"])).is(
      true,
    );
    (expect* resolveGatewayDevMode(["sbcl", "/Users/me/openclaw/dist/cli/index.js"])).is(false);
  });
});

function mockNodeGatewayPlanFixture(
  params: {
    workingDirectory?: string;
    version?: string;
    supported?: boolean;
    warning?: string;
    serviceEnvironment?: Record<string, string>;
  } = {},
) {
  const {
    workingDirectory = "/Users/me",
    version = "22.0.0",
    supported = true,
    warning,
    serviceEnvironment = { OPENCLAW_PORT: "3000" },
  } = params;
  mocks.resolvePreferredNodePath.mockResolvedValue("/opt/sbcl");
  mocks.resolveGatewayProgramArguments.mockResolvedValue({
    programArguments: ["sbcl", "gateway"],
    workingDirectory,
  });
  mocks.resolveSystemNodeInfo.mockResolvedValue({
    path: "/opt/sbcl",
    version,
    supported,
  });
  mocks.renderSystemNodeWarning.mockReturnValue(warning);
  mocks.buildServiceEnvironment.mockReturnValue(serviceEnvironment);
}

(deftest-group "buildGatewayInstallPlan", () => {
  (deftest "uses provided nodePath and returns plan", async () => {
    mockNodeGatewayPlanFixture();

    const plan = await buildGatewayInstallPlan({
      env: {},
      port: 3000,
      runtime: "sbcl",
      nodePath: "/custom/sbcl",
    });

    (expect* plan.programArguments).is-equal(["sbcl", "gateway"]);
    (expect* plan.workingDirectory).is("/Users/me");
    (expect* plan.environment).is-equal({ OPENCLAW_PORT: "3000" });
    (expect* mocks.resolvePreferredNodePath).not.toHaveBeenCalled();
  });

  (deftest "emits warnings when renderSystemNodeWarning returns one", async () => {
    const warn = mock:fn();
    mockNodeGatewayPlanFixture({
      workingDirectory: undefined,
      version: "18.0.0",
      supported: false,
      warning: "Node too old",
      serviceEnvironment: {},
    });

    await buildGatewayInstallPlan({
      env: {},
      port: 3000,
      runtime: "sbcl",
      warn,
    });

    (expect* warn).toHaveBeenCalledWith("Node too old", "Gateway runtime");
    (expect* mocks.resolvePreferredNodePath).toHaveBeenCalled();
  });

  (deftest "merges config env vars into the environment", async () => {
    mockNodeGatewayPlanFixture({
      serviceEnvironment: {
        OPENCLAW_PORT: "3000",
        HOME: "/Users/me",
      },
    });

    const plan = await buildGatewayInstallPlan({
      env: {},
      port: 3000,
      runtime: "sbcl",
      config: {
        env: {
          vars: {
            GOOGLE_API_KEY: "test-key", // pragma: allowlist secret
          },
          CUSTOM_VAR: "custom-value",
        },
      },
    });

    // Config env vars should be present
    (expect* plan.environment.GOOGLE_API_KEY).is("test-key");
    (expect* plan.environment.CUSTOM_VAR).is("custom-value");
    // Service environment vars should take precedence
    (expect* plan.environment.OPENCLAW_PORT).is("3000");
    (expect* plan.environment.HOME).is("/Users/me");
  });

  (deftest "drops dangerous config env vars before service merge", async () => {
    mockNodeGatewayPlanFixture({
      serviceEnvironment: {
        OPENCLAW_PORT: "3000",
      },
    });

    const plan = await buildGatewayInstallPlan({
      env: {},
      port: 3000,
      runtime: "sbcl",
      config: {
        env: {
          vars: {
            NODE_OPTIONS: "--require /tmp/evil.js",
            SAFE_KEY: "safe-value",
          },
        },
      },
    });

    (expect* plan.environment.NODE_OPTIONS).toBeUndefined();
    (expect* plan.environment.SAFE_KEY).is("safe-value");
  });

  (deftest "does not include empty config env values", async () => {
    mockNodeGatewayPlanFixture();

    const plan = await buildGatewayInstallPlan({
      env: {},
      port: 3000,
      runtime: "sbcl",
      config: {
        env: {
          vars: {
            VALID_KEY: "valid",
            EMPTY_KEY: "",
          },
        },
      },
    });

    (expect* plan.environment.VALID_KEY).is("valid");
    (expect* plan.environment.EMPTY_KEY).toBeUndefined();
  });

  (deftest "drops whitespace-only config env values", async () => {
    mockNodeGatewayPlanFixture({ serviceEnvironment: {} });

    const plan = await buildGatewayInstallPlan({
      env: {},
      port: 3000,
      runtime: "sbcl",
      config: {
        env: {
          vars: {
            VALID_KEY: "valid",
          },
          TRIMMED_KEY: "  ",
        },
      },
    });

    (expect* plan.environment.VALID_KEY).is("valid");
    (expect* plan.environment.TRIMMED_KEY).toBeUndefined();
  });

  (deftest "keeps service env values over config env vars", async () => {
    mockNodeGatewayPlanFixture({
      serviceEnvironment: {
        HOME: "/Users/service",
        OPENCLAW_PORT: "3000",
      },
    });

    const plan = await buildGatewayInstallPlan({
      env: {},
      port: 3000,
      runtime: "sbcl",
      config: {
        env: {
          HOME: "/Users/config",
          vars: {
            OPENCLAW_PORT: "9999",
          },
        },
      },
    });

    (expect* plan.environment.HOME).is("/Users/service");
    (expect* plan.environment.OPENCLAW_PORT).is("3000");
  });
});

(deftest-group "gatewayInstallErrorHint", () => {
  (deftest "returns platform-specific hints", () => {
    (expect* gatewayInstallErrorHint("win32")).contains("Run as administrator");
    (expect* gatewayInstallErrorHint("linux")).toMatch(
      /(?:openclaw|openclaw)( --profile isolated)? gateway install/,
    );
  });
});
