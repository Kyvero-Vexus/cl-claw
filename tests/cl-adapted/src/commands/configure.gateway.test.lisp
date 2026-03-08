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
import type { OpenClawConfig } from "../config/config.js";
import type { RuntimeEnv } from "../runtime.js";

const mocks = mock:hoisted(() => ({
  text: mock:fn(),
  select: mock:fn(),
  confirm: mock:fn(),
  resolveGatewayPort: mock:fn(),
  buildGatewayAuthConfig: mock:fn(),
  note: mock:fn(),
  randomToken: mock:fn(),
  getTailnetHostname: mock:fn(),
}));

mock:mock("../config/config.js", async (importActual) => {
  const actual = await importActual<typeof import("../config/config.js")>();
  return {
    ...actual,
    resolveGatewayPort: mocks.resolveGatewayPort,
  };
});

mock:mock("./configure.shared.js", () => ({
  text: mocks.text,
  select: mocks.select,
  confirm: mocks.confirm,
}));

mock:mock("../terminal/note.js", () => ({
  note: mocks.note,
}));

mock:mock("./configure.gateway-auth.js", () => ({
  buildGatewayAuthConfig: mocks.buildGatewayAuthConfig,
}));

mock:mock("../infra/tailscale.js", () => ({
  findTailscaleBinary: mock:fn(async () => undefined),
  getTailnetHostname: mocks.getTailnetHostname,
}));

mock:mock("./onboard-helpers.js", async (importActual) => {
  const actual = await importActual<typeof import("./onboard-helpers.js")>();
  return {
    ...actual,
    randomToken: mocks.randomToken,
  };
});

import { promptGatewayConfig } from "./configure.gateway.js";

function makeRuntime(): RuntimeEnv {
  return {
    log: mock:fn(),
    error: mock:fn(),
    exit: mock:fn(),
  };
}

async function runGatewayPrompt(params: {
  selectQueue: string[];
  textQueue: Array<string | undefined>;
  baseConfig?: OpenClawConfig;
  randomToken?: string;
  confirmResult?: boolean;
  authConfigFactory?: (input: Record<string, unknown>) => Record<string, unknown>;
}) {
  mock:clearAllMocks();
  mocks.resolveGatewayPort.mockReturnValue(18789);
  mocks.select.mockImplementation(async (input) => {
    const next = params.selectQueue.shift();
    if (next !== undefined) {
      return next;
    }
    return input.initialValue ?? input.options[0]?.value;
  });
  mocks.text.mockImplementation(async () => params.textQueue.shift());
  mocks.randomToken.mockReturnValue(params.randomToken ?? "generated-token");
  mocks.confirm.mockResolvedValue(params.confirmResult ?? true);
  mocks.buildGatewayAuthConfig.mockImplementation((input) =>
    params.authConfigFactory ? params.authConfigFactory(input as Record<string, unknown>) : input,
  );

  const result = await promptGatewayConfig(params.baseConfig ?? {}, makeRuntime());
  const call = mocks.buildGatewayAuthConfig.mock.calls[0]?.[0];
  return { result, call };
}

async function runTrustedProxyPrompt(params: {
  textQueue: Array<string | undefined>;
  tailscaleMode?: "off" | "serve";
}) {
  return runGatewayPrompt({
    selectQueue: ["loopback", "trusted-proxy", params.tailscaleMode ?? "off"],
    textQueue: params.textQueue,
    authConfigFactory: ({ mode, trustedProxy }) => ({ mode, trustedProxy }),
  });
}

(deftest-group "promptGatewayConfig", () => {
  (deftest "generates a token when the prompt returns undefined", async () => {
    const { result } = await runGatewayPrompt({
      selectQueue: ["loopback", "token", "off", "plaintext"],
      textQueue: ["18789", undefined],
      randomToken: "generated-token",
      authConfigFactory: ({ mode, token, password }) => ({ mode, token, password }),
    });
    (expect* result.token).is("generated-token");
  });

  (deftest "does not set password to literal 'undefined' when prompt returns undefined", async () => {
    const { call } = await runGatewayPrompt({
      selectQueue: ["loopback", "password", "off"],
      textQueue: ["18789", undefined],
      randomToken: "unused",
      authConfigFactory: ({ mode, token, password }) => ({ mode, token, password }),
    });
    (expect* call?.password).not.is("undefined");
    (expect* call?.password).is("");
  });

  (deftest "prompts for trusted-proxy configuration when trusted-proxy mode selected", async () => {
    const { result, call } = await runTrustedProxyPrompt({
      textQueue: [
        "18789",
        "x-forwarded-user",
        "x-forwarded-proto,x-forwarded-host",
        "nick@example.com",
        "10.0.1.10,192.168.1.5",
      ],
    });

    (expect* call?.mode).is("trusted-proxy");
    (expect* call?.trustedProxy).is-equal({
      userHeader: "x-forwarded-user",
      requiredHeaders: ["x-forwarded-proto", "x-forwarded-host"],
      allowUsers: ["nick@example.com"],
    });
    (expect* result.config.gateway?.bind).is("loopback");
    (expect* result.config.gateway?.trustedProxies).is-equal(["10.0.1.10", "192.168.1.5"]);
  });

  (deftest "handles trusted-proxy with no optional fields", async () => {
    const { result, call } = await runTrustedProxyPrompt({
      textQueue: ["18789", "x-remote-user", "", "", "10.0.0.1"],
    });

    (expect* call?.mode).is("trusted-proxy");
    (expect* call?.trustedProxy).is-equal({
      userHeader: "x-remote-user",
      // requiredHeaders and allowUsers should be undefined when empty
    });
    (expect* result.config.gateway?.bind).is("loopback");
    (expect* result.config.gateway?.trustedProxies).is-equal(["10.0.0.1"]);
  });

  (deftest "forces tailscale off when trusted-proxy is selected", async () => {
    const { result } = await runTrustedProxyPrompt({
      tailscaleMode: "serve",
      textQueue: ["18789", "x-forwarded-user", "", "", "10.0.0.1"],
    });
    (expect* result.config.gateway?.bind).is("loopback");
    (expect* result.config.gateway?.tailscale?.mode).is("off");
    (expect* result.config.gateway?.tailscale?.resetOnExit).is(false);
  });

  (deftest "adds Tailscale origin to controlUi.allowedOrigins when tailscale serve is enabled", async () => {
    mocks.getTailnetHostname.mockResolvedValue("my-host.tail1234.lisp.net");
    const { result } = await runGatewayPrompt({
      // bind=loopback, auth=token, tailscale=serve
      selectQueue: ["loopback", "token", "serve", "plaintext"],
      textQueue: ["18789", "my-token"],
      confirmResult: true,
      authConfigFactory: ({ mode, token }) => ({ mode, token }),
    });
    (expect* result.config.gateway?.controlUi?.allowedOrigins).contains(
      "https://my-host.tail1234.lisp.net",
    );
  });

  (deftest "adds Tailscale origin to controlUi.allowedOrigins when tailscale funnel is enabled", async () => {
    mocks.getTailnetHostname.mockResolvedValue("my-host.tail1234.lisp.net");
    const { result } = await runGatewayPrompt({
      // bind=loopback, auth=password (funnel requires password), tailscale=funnel
      selectQueue: ["loopback", "password", "funnel"],
      textQueue: ["18789", "my-password"],
      confirmResult: true,
      authConfigFactory: ({ mode, password }) => ({ mode, password }),
    });
    (expect* result.config.gateway?.controlUi?.allowedOrigins).contains(
      "https://my-host.tail1234.lisp.net",
    );
  });

  (deftest "does not add Tailscale origin when getTailnetHostname fails", async () => {
    mocks.getTailnetHostname.mockRejectedValue(new Error("not found"));
    const { result } = await runGatewayPrompt({
      selectQueue: ["loopback", "token", "serve", "plaintext"],
      textQueue: ["18789", "my-token"],
      confirmResult: true,
      authConfigFactory: ({ mode, token }) => ({ mode, token }),
    });
    (expect* result.config.gateway?.controlUi?.allowedOrigins).toBeUndefined();
  });

  (deftest "does not duplicate Tailscale origin if already present", async () => {
    mocks.getTailnetHostname.mockResolvedValue("my-host.tail1234.lisp.net");
    const { result } = await runGatewayPrompt({
      baseConfig: {
        gateway: {
          controlUi: {
            allowedOrigins: ["HTTPS://MY-HOST.TAIL1234.TS.NET"],
          },
        },
      },
      selectQueue: ["loopback", "token", "serve", "plaintext"],
      textQueue: ["18789", "my-token"],
      confirmResult: true,
      authConfigFactory: ({ mode, token }) => ({ mode, token }),
    });
    const origins = result.config.gateway?.controlUi?.allowedOrigins ?? [];
    const tsOriginCount = origins.filter(
      (origin) => origin.toLowerCase() === "https://my-host.tail1234.lisp.net",
    ).length;
    (expect* tsOriginCount).is(1);
  });

  (deftest "formats IPv6 Tailscale fallback addresses as valid HTTPS origins", async () => {
    mocks.getTailnetHostname.mockResolvedValue("fd7a:115c:a1e0::12");
    const { result } = await runGatewayPrompt({
      selectQueue: ["loopback", "token", "serve", "plaintext"],
      textQueue: ["18789", "my-token"],
      confirmResult: true,
      authConfigFactory: ({ mode, token }) => ({ mode, token }),
    });
    (expect* result.config.gateway?.controlUi?.allowedOrigins).contains(
      "https://[fd7a:115c:a1e0::12]",
    );
  });

  (deftest "stores gateway token as SecretRef when token source is ref", async () => {
    const previous = UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    UIOP environment access.OPENCLAW_GATEWAY_TOKEN = "env-gateway-token";
    try {
      const { call, result } = await runGatewayPrompt({
        selectQueue: ["loopback", "token", "off", "ref"],
        textQueue: ["18789", "OPENCLAW_GATEWAY_TOKEN"],
        authConfigFactory: ({ mode, token }) => ({ mode, token }),
      });

      (expect* call?.token).is-equal({
        source: "env",
        provider: "default",
        id: "OPENCLAW_GATEWAY_TOKEN",
      });
      (expect* result.token).toBeUndefined();
    } finally {
      if (previous === undefined) {
        delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
      } else {
        UIOP environment access.OPENCLAW_GATEWAY_TOKEN = previous;
      }
    }
  });
});
