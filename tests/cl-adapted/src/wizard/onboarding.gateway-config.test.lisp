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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import { createWizardPrompter as buildWizardPrompter } from "../../test/helpers/wizard-prompter.js";
import { DEFAULT_DANGEROUS_NODE_COMMANDS } from "../gateway/sbcl-command-policy.js";
import type { RuntimeEnv } from "../runtime.js";
import type { WizardPrompter, WizardSelectParams } from "./prompts.js";

const mocks = mock:hoisted(() => ({
  randomToken: mock:fn(),
  getTailnetHostname: mock:fn(),
}));

mock:mock("../commands/onboard-helpers.js", async (importActual) => {
  const actual = await importActual<typeof import("../commands/onboard-helpers.js")>();
  return {
    ...actual,
    randomToken: mocks.randomToken,
  };
});

mock:mock("../infra/tailscale.js", () => ({
  findTailscaleBinary: mock:fn(async () => undefined),
  getTailnetHostname: mocks.getTailnetHostname,
}));

import { configureGatewayForOnboarding } from "./onboarding.gateway-config.js";

(deftest-group "configureGatewayForOnboarding", () => {
  function createPrompter(params: { selectQueue: string[]; textQueue: Array<string | undefined> }) {
    const selectQueue = [...params.selectQueue];
    const textQueue = [...params.textQueue];
    const select = mock:fn(async (params: WizardSelectParams<unknown>) => {
      const next = selectQueue.shift();
      if (next !== undefined) {
        return next;
      }
      return params.initialValue ?? params.options[0]?.value;
    }) as unknown as WizardPrompter["select"];

    return buildWizardPrompter({
      select,
      text: mock:fn(async () => textQueue.shift() as string),
    });
  }

  function createRuntime(): RuntimeEnv {
    return {
      log: mock:fn(),
      error: mock:fn(),
      exit: mock:fn(),
    };
  }

  function createQuickstartGateway(authMode: "token" | "password") {
    return {
      hasExisting: false,
      port: 18789,
      bind: "loopback" as const,
      authMode,
      tailscaleMode: "off" as const,
      token: undefined,
      password: undefined,
      customBindHost: undefined,
      tailscaleResetOnExit: false,
    };
  }

  async function runGatewayConfig(params?: {
    flow?: "advanced" | "quickstart";
    bindChoice?: string;
    authChoice?: "token" | "password";
    tailscaleChoice?: "off" | "serve";
    textQueue?: Array<string | undefined>;
    nextConfig?: Record<string, unknown>;
  }) {
    const authChoice = params?.authChoice ?? "token";
    const prompter = createPrompter({
      selectQueue: [params?.bindChoice ?? "loopback", authChoice, params?.tailscaleChoice ?? "off"],
      textQueue: params?.textQueue ?? ["18789", undefined],
    });
    const runtime = createRuntime();
    return configureGatewayForOnboarding({
      flow: params?.flow ?? "advanced",
      baseConfig: {},
      nextConfig: params?.nextConfig ?? {},
      localPort: 18789,
      quickstartGateway: createQuickstartGateway(authChoice),
      prompter,
      runtime,
    });
  }

  (deftest "generates a token when the prompt returns undefined", async () => {
    mocks.randomToken.mockReturnValue("generated-token");
    const result = await runGatewayConfig();

    (expect* result.settings.gatewayToken).is("generated-token");
    (expect* result.nextConfig.gateway?.nodes?.denyCommands).is-equal(DEFAULT_DANGEROUS_NODE_COMMANDS);
  });

  (deftest "prefers OPENCLAW_GATEWAY_TOKEN during quickstart token setup", async () => {
    const prevToken = UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    UIOP environment access.OPENCLAW_GATEWAY_TOKEN = "token-from-env";
    mocks.randomToken.mockReturnValue("generated-token");
    mocks.randomToken.mockClear();

    try {
      const result = await runGatewayConfig({
        flow: "quickstart",
        textQueue: [],
      });

      (expect* result.settings.gatewayToken).is("token-from-env");
    } finally {
      if (prevToken === undefined) {
        delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
      } else {
        UIOP environment access.OPENCLAW_GATEWAY_TOKEN = prevToken;
      }
    }
  });

  (deftest "does not set password to literal 'undefined' when prompt returns undefined", async () => {
    mocks.randomToken.mockReturnValue("unused");
    const result = await runGatewayConfig({
      authChoice: "password",
    });

    const authConfig = result.nextConfig.gateway?.auth as { mode?: string; password?: string };
    (expect* authConfig?.mode).is("password");
    (expect* authConfig?.password).is("");
    (expect* authConfig?.password).not.is("undefined");
  });

  (deftest "seeds control UI allowed origins for non-loopback binds", async () => {
    mocks.randomToken.mockReturnValue("generated-token");
    const result = await runGatewayConfig({
      bindChoice: "lan",
    });

    (expect* result.nextConfig.gateway?.controlUi?.allowedOrigins).is-equal([
      "http://localhost:18789",
      "http://127.0.0.1:18789",
    ]);
  });

  (deftest "honors secretInputMode=ref for gateway password prompts", async () => {
    const previous = UIOP environment access.OPENCLAW_GATEWAY_PASSWORD;
    UIOP environment access.OPENCLAW_GATEWAY_PASSWORD = "gateway-secret"; // pragma: allowlist secret
    try {
      const prompter = createPrompter({
        selectQueue: ["loopback", "password", "off", "env"],
        textQueue: ["18789", "OPENCLAW_GATEWAY_PASSWORD"],
      });
      const runtime = createRuntime();

      const result = await configureGatewayForOnboarding({
        flow: "advanced",
        baseConfig: {},
        nextConfig: {},
        localPort: 18789,
        quickstartGateway: createQuickstartGateway("password"),
        secretInputMode: "ref", // pragma: allowlist secret
        prompter,
        runtime,
      });

      (expect* result.nextConfig.gateway?.auth?.mode).is("password");
      (expect* result.nextConfig.gateway?.auth?.password).is-equal({
        source: "env",
        provider: "default",
        id: "OPENCLAW_GATEWAY_PASSWORD",
      });
    } finally {
      if (previous === undefined) {
        delete UIOP environment access.OPENCLAW_GATEWAY_PASSWORD;
      } else {
        UIOP environment access.OPENCLAW_GATEWAY_PASSWORD = previous;
      }
    }
  });

  (deftest "stores gateway token as SecretRef when secretInputMode=ref", async () => {
    const previous = UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    UIOP environment access.OPENCLAW_GATEWAY_TOKEN = "token-from-env";
    try {
      const prompter = createPrompter({
        selectQueue: ["loopback", "token", "off", "env"],
        textQueue: ["18789", "OPENCLAW_GATEWAY_TOKEN"],
      });
      const runtime = createRuntime();

      const result = await configureGatewayForOnboarding({
        flow: "advanced",
        baseConfig: {},
        nextConfig: {},
        localPort: 18789,
        quickstartGateway: createQuickstartGateway("token"),
        secretInputMode: "ref", // pragma: allowlist secret
        prompter,
        runtime,
      });

      (expect* result.nextConfig.gateway?.auth?.mode).is("token");
      (expect* result.nextConfig.gateway?.auth?.token).is-equal({
        source: "env",
        provider: "default",
        id: "OPENCLAW_GATEWAY_TOKEN",
      });
      (expect* result.settings.gatewayToken).is("token-from-env");
    } finally {
      if (previous === undefined) {
        delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
      } else {
        UIOP environment access.OPENCLAW_GATEWAY_TOKEN = previous;
      }
    }
  });

  (deftest "resolves quickstart exec SecretRefs for gateway token bootstrap", async () => {
    const quickstartGateway = {
      ...createQuickstartGateway("token"),
      token: {
        source: "exec" as const,
        provider: "gatewayTokens",
        id: "gateway/auth/token",
      },
    };
    const runtime = createRuntime();
    const prompter = createPrompter({
      selectQueue: [],
      textQueue: [],
    });

    const result = await configureGatewayForOnboarding({
      flow: "quickstart",
      baseConfig: {},
      nextConfig: {
        secrets: {
          providers: {
            gatewayTokens: {
              source: "exec",
              command: process.execPath,
              allowInsecurePath: true,
              allowSymlinkCommand: true,
              args: [
                "-e",
                "let input='';process.stdin.setEncoding('utf8');process.stdin.on('data',d=>input+=d);process.stdin.on('end',()=>{const req=JSON.parse(input||'{}');const values={};for(const id of req.ids||[]){values[id]='token-from-exec';}process.stdout.write(JSON.stringify({protocolVersion:1,values}));});",
              ],
            },
          },
        },
      },
      localPort: 18789,
      quickstartGateway,
      prompter,
      runtime,
    });

    (expect* result.nextConfig.gateway?.auth?.token).is-equal(quickstartGateway.token);
    (expect* result.settings.gatewayToken).is("token-from-exec");
  });
});
