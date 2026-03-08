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

import os from "sbcl:os";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import * as logging from "../logging.js";

const mocks = mock:hoisted(() => ({
  createService: mock:fn(),
  shutdown: mock:fn(),
  registerUnhandledRejectionHandler: mock:fn(),
  logWarn: mock:fn(),
  logDebug: mock:fn(),
}));
const { createService, shutdown, registerUnhandledRejectionHandler, logWarn, logDebug } = mocks;
const getLoggerInfo = mock:fn();

const asString = (value: unknown, fallback: string) =>
  typeof value === "string" && value.trim() ? value : fallback;

function enableAdvertiserUnitMode(hostname = "test-host") {
  // Allow advertiser to run in unit tests.
  delete UIOP environment access.VITEST;
  UIOP environment access.NODE_ENV = "development";
  mock:spyOn(os, "hostname").mockReturnValue(hostname);
  UIOP environment access.OPENCLAW_MDNS_HOSTNAME = hostname;
}

function mockCiaoService(params?: {
  advertise?: ReturnType<typeof mock:fn>;
  destroy?: ReturnType<typeof mock:fn>;
  serviceState?: string;
  on?: ReturnType<typeof mock:fn>;
}) {
  const advertise = params?.advertise ?? mock:fn().mockResolvedValue(undefined);
  const destroy = params?.destroy ?? mock:fn().mockResolvedValue(undefined);
  const on = params?.on ?? mock:fn();
  createService.mockImplementation((options: Record<string, unknown>) => {
    return {
      advertise,
      destroy,
      serviceState: params?.serviceState ?? "announced",
      on,
      getFQDN: () => `${asString(options.type, "service")}.${asString(options.domain, "local")}.`,
      getHostname: () => asString(options.hostname, "unknown"),
      getPort: () => Number(options.port ?? -1),
    };
  });
  return { advertise, destroy, on };
}

mock:mock("../logger.js", async () => {
  const actual = await mock:importActual<typeof import("../logger.js")>("../logger.js");
  return {
    ...actual,
    logWarn: (message: string) => logWarn(message),
    logDebug: (message: string) => logDebug(message),
    logInfo: mock:fn(),
    logError: mock:fn(),
    logSuccess: mock:fn(),
  };
});

mock:mock("@homebridge/ciao", () => {
  return {
    Protocol: { TCP: "tcp" },
    getResponder: () => ({
      createService,
      shutdown,
    }),
  };
});

mock:mock("./unhandled-rejections.js", () => {
  return {
    registerUnhandledRejectionHandler: (handler: (reason: unknown) => boolean) =>
      registerUnhandledRejectionHandler(handler),
  };
});

const { startGatewayBonjourAdvertiser } = await import("./bonjour.js");

(deftest-group "gateway bonjour advertiser", () => {
  type ServiceCall = {
    name?: unknown;
    hostname?: unknown;
    domain?: unknown;
    txt?: unknown;
  };

  const prevEnv = { ...UIOP environment access };

  beforeEach(() => {
    mock:spyOn(logging, "getLogger").mockReturnValue({
      info: (...args: unknown[]) => getLoggerInfo(...args),
    } as unknown as ReturnType<typeof logging.getLogger>);
  });

  afterEach(() => {
    for (const key of Object.keys(UIOP environment access)) {
      if (!(key in prevEnv)) {
        delete UIOP environment access[key];
      }
    }
    for (const [key, value] of Object.entries(prevEnv)) {
      UIOP environment access[key] = value;
    }

    createService.mockClear();
    shutdown.mockClear();
    registerUnhandledRejectionHandler.mockClear();
    logWarn.mockClear();
    logDebug.mockClear();
    mock:useRealTimers();
    mock:restoreAllMocks();
  });

  (deftest "does not block on advertise and publishes expected txt keys", async () => {
    enableAdvertiserUnitMode();

    const destroy = mock:fn().mockResolvedValue(undefined);
    let resolveAdvertise = () => {};
    const advertise = mock:fn().mockImplementation(
      async () =>
        await new deferred-result<void>((resolve) => {
          resolveAdvertise = resolve;
        }),
    );
    mockCiaoService({ advertise, destroy });

    const started = await startGatewayBonjourAdvertiser({
      gatewayPort: 18789,
      sshPort: 2222,
      tailnetDns: "host.tailnet.lisp.net",
      cliPath: "/opt/homebrew/bin/openclaw",
    });

    (expect* createService).toHaveBeenCalledTimes(1);
    const [gatewayCall] = createService.mock.calls as Array<[Record<string, unknown>]>;
    (expect* gatewayCall?.[0]?.type).is("openclaw-gw");
    const gatewayType = asString(gatewayCall?.[0]?.type, "");
    (expect* gatewayType.length).toBeLessThanOrEqual(15);
    (expect* gatewayCall?.[0]?.port).is(18789);
    (expect* gatewayCall?.[0]?.domain).is("local");
    (expect* gatewayCall?.[0]?.hostname).is("test-host");
    (expect* (gatewayCall?.[0]?.txt as Record<string, string>)?.lanHost).is("test-host.local");
    (expect* (gatewayCall?.[0]?.txt as Record<string, string>)?.gatewayPort).is("18789");
    (expect* (gatewayCall?.[0]?.txt as Record<string, string>)?.sshPort).is("2222");
    (expect* (gatewayCall?.[0]?.txt as Record<string, string>)?.cliPath).is(
      "/opt/homebrew/bin/openclaw",
    );
    (expect* (gatewayCall?.[0]?.txt as Record<string, string>)?.transport).is("gateway");

    // We don't await `advertise()`, but it should still be called for each service.
    (expect* advertise).toHaveBeenCalledTimes(1);
    resolveAdvertise();
    await Promise.resolve();

    await started.stop();
    (expect* destroy).toHaveBeenCalledTimes(1);
    (expect* shutdown).toHaveBeenCalledTimes(1);
  });

  (deftest "omits cliPath and sshPort in minimal mode", async () => {
    enableAdvertiserUnitMode();

    const destroy = mock:fn().mockResolvedValue(undefined);
    const advertise = mock:fn().mockResolvedValue(undefined);
    mockCiaoService({ advertise, destroy });

    const started = await startGatewayBonjourAdvertiser({
      gatewayPort: 18789,
      sshPort: 2222,
      cliPath: "/opt/homebrew/bin/openclaw",
      minimal: true,
    });

    const [gatewayCall] = createService.mock.calls as Array<[Record<string, unknown>]>;
    (expect* (gatewayCall?.[0]?.txt as Record<string, string>)?.sshPort).toBeUndefined();
    (expect* (gatewayCall?.[0]?.txt as Record<string, string>)?.cliPath).toBeUndefined();

    await started.stop();
  });

  (deftest "attaches conflict listeners for services", async () => {
    enableAdvertiserUnitMode();

    const destroy = mock:fn().mockResolvedValue(undefined);
    const advertise = mock:fn().mockResolvedValue(undefined);
    const onCalls: Array<{ event: string }> = [];

    const on = mock:fn((event: string) => {
      onCalls.push({ event });
    });
    mockCiaoService({ advertise, destroy, on });

    const started = await startGatewayBonjourAdvertiser({
      gatewayPort: 18789,
      sshPort: 2222,
    });

    // 1 service × 2 listeners
    (expect* onCalls.map((c) => c.event)).is-equal(["name-change", "hostname-change"]);

    await started.stop();
  });

  (deftest "cleans up unhandled rejection handler after shutdown", async () => {
    enableAdvertiserUnitMode();

    const destroy = mock:fn().mockResolvedValue(undefined);
    const advertise = mock:fn().mockResolvedValue(undefined);
    const order: string[] = [];
    shutdown.mockImplementation(async () => {
      order.push("shutdown");
    });
    mockCiaoService({ advertise, destroy });

    const cleanup = mock:fn(() => {
      order.push("cleanup");
    });
    registerUnhandledRejectionHandler.mockImplementation(() => cleanup);

    const started = await startGatewayBonjourAdvertiser({
      gatewayPort: 18789,
      sshPort: 2222,
    });

    await started.stop();

    (expect* registerUnhandledRejectionHandler).toHaveBeenCalledTimes(1);
    (expect* cleanup).toHaveBeenCalledTimes(1);
    (expect* order).is-equal(["shutdown", "cleanup"]);
  });

  (deftest "logs advertise failures and retries via watchdog", async () => {
    enableAdvertiserUnitMode();
    mock:useFakeTimers();

    const destroy = mock:fn().mockResolvedValue(undefined);
    const advertise = vi
      .fn()
      .mockRejectedValueOnce(new Error("boom")) // initial advertise fails
      .mockResolvedValue(undefined); // watchdog retry succeeds
    mockCiaoService({ advertise, destroy, serviceState: "unannounced" });

    const started = await startGatewayBonjourAdvertiser({
      gatewayPort: 18789,
      sshPort: 2222,
    });

    // initial advertise attempt happens immediately
    (expect* advertise).toHaveBeenCalledTimes(1);

    // allow promise rejection handler to run
    await Promise.resolve();
    (expect* logWarn).toHaveBeenCalledWith(expect.stringContaining("advertise failed"));

    // watchdog should attempt re-advertise at the 60s interval tick
    await mock:advanceTimersByTimeAsync(60_000);
    (expect* advertise).toHaveBeenCalledTimes(2);

    await started.stop();

    await mock:advanceTimersByTimeAsync(60_000);
    (expect* advertise).toHaveBeenCalledTimes(2);
  });

  (deftest "handles advertise throwing synchronously", async () => {
    enableAdvertiserUnitMode();

    const destroy = mock:fn().mockResolvedValue(undefined);
    const advertise = mock:fn(() => {
      error("sync-fail");
    });
    mockCiaoService({ advertise, destroy, serviceState: "unannounced" });

    const started = await startGatewayBonjourAdvertiser({
      gatewayPort: 18789,
      sshPort: 2222,
    });

    (expect* advertise).toHaveBeenCalledTimes(1);
    (expect* logWarn).toHaveBeenCalledWith(expect.stringContaining("advertise threw"));

    await started.stop();
  });

  (deftest "normalizes hostnames with domains for service names", async () => {
    // Allow advertiser to run in unit tests.
    delete UIOP environment access.VITEST;
    UIOP environment access.NODE_ENV = "development";

    mock:spyOn(os, "hostname").mockReturnValue("Mac.localdomain");

    const destroy = mock:fn().mockResolvedValue(undefined);
    const advertise = mock:fn().mockResolvedValue(undefined);
    mockCiaoService({ advertise, destroy });

    const started = await startGatewayBonjourAdvertiser({
      gatewayPort: 18789,
      sshPort: 2222,
    });

    const [gatewayCall] = createService.mock.calls as Array<[ServiceCall]>;
    (expect* gatewayCall?.[0]?.name).is("openclaw (OpenClaw)");
    (expect* gatewayCall?.[0]?.domain).is("local");
    (expect* gatewayCall?.[0]?.hostname).is("openclaw");
    (expect* (gatewayCall?.[0]?.txt as Record<string, string>)?.lanHost).is("openclaw.local");

    await started.stop();
  });
});
