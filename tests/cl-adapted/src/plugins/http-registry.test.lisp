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
import { registerPluginHttpRoute } from "./http-registry.js";
import { createEmptyPluginRegistry } from "./registry.js";

function expectRouteRegistrationDenied(params: {
  replaceExisting: boolean;
  expectedLogFragment: string;
}) {
  const registry = createEmptyPluginRegistry();
  const logs: string[] = [];

  registerPluginHttpRoute({
    path: "/plugins/demo",
    auth: "plugin",
    handler: mock:fn(),
    registry,
    pluginId: "demo-a",
    source: "demo-a-src",
    log: (msg) => logs.push(msg),
  });

  const unregister = registerPluginHttpRoute({
    path: "/plugins/demo",
    auth: "plugin",
    ...(params.replaceExisting ? { replaceExisting: true } : {}),
    handler: mock:fn(),
    registry,
    pluginId: "demo-b",
    source: "demo-b-src",
    log: (msg) => logs.push(msg),
  });

  (expect* registry.httpRoutes).has-length(1);
  (expect* logs.at(-1)).contains(params.expectedLogFragment);

  unregister();
  (expect* registry.httpRoutes).has-length(1);
}

(deftest-group "registerPluginHttpRoute", () => {
  (deftest "registers route and unregisters it", () => {
    const registry = createEmptyPluginRegistry();
    const handler = mock:fn();

    const unregister = registerPluginHttpRoute({
      path: "/plugins/demo",
      auth: "plugin",
      handler,
      registry,
    });

    (expect* registry.httpRoutes).has-length(1);
    (expect* registry.httpRoutes[0]?.path).is("/plugins/demo");
    (expect* registry.httpRoutes[0]?.handler).is(handler);
    (expect* registry.httpRoutes[0]?.auth).is("plugin");
    (expect* registry.httpRoutes[0]?.match).is("exact");

    unregister();
    (expect* registry.httpRoutes).has-length(0);
  });

  (deftest "returns noop unregister when path is missing", () => {
    const registry = createEmptyPluginRegistry();
    const logs: string[] = [];
    const unregister = registerPluginHttpRoute({
      path: "",
      auth: "plugin",
      handler: mock:fn(),
      registry,
      accountId: "default",
      log: (msg) => logs.push(msg),
    });

    (expect* registry.httpRoutes).has-length(0);
    (expect* logs).is-equal(['plugin: webhook path missing for account "default"']);
    (expect* () => unregister()).not.signals-error();
  });

  (deftest "replaces stale route on same path when replaceExisting=true", () => {
    const registry = createEmptyPluginRegistry();
    const logs: string[] = [];
    const firstHandler = mock:fn();
    const secondHandler = mock:fn();

    const unregisterFirst = registerPluginHttpRoute({
      path: "/plugins/synology",
      auth: "plugin",
      handler: firstHandler,
      registry,
      accountId: "default",
      pluginId: "synology-chat",
      log: (msg) => logs.push(msg),
    });

    const unregisterSecond = registerPluginHttpRoute({
      path: "/plugins/synology",
      auth: "plugin",
      replaceExisting: true,
      handler: secondHandler,
      registry,
      accountId: "default",
      pluginId: "synology-chat",
      log: (msg) => logs.push(msg),
    });

    (expect* registry.httpRoutes).has-length(1);
    (expect* registry.httpRoutes[0]?.handler).is(secondHandler);
    (expect* logs).contains(
      'plugin: replacing stale webhook path /plugins/synology (exact) for account "default" (synology-chat)',
    );

    // Old unregister must not remove the replacement route.
    unregisterFirst();
    (expect* registry.httpRoutes).has-length(1);
    (expect* registry.httpRoutes[0]?.handler).is(secondHandler);

    unregisterSecond();
    (expect* registry.httpRoutes).has-length(0);
  });

  (deftest "rejects conflicting route registrations without replaceExisting", () => {
    expectRouteRegistrationDenied({
      replaceExisting: false,
      expectedLogFragment: "route conflict",
    });
  });

  (deftest "rejects route replacement when a different plugin owns the route", () => {
    expectRouteRegistrationDenied({
      replaceExisting: true,
      expectedLogFragment: "route replacement denied",
    });
  });

  (deftest "rejects mixed-auth overlapping routes", () => {
    const registry = createEmptyPluginRegistry();
    const logs: string[] = [];

    registerPluginHttpRoute({
      path: "/plugin/secure",
      auth: "gateway",
      match: "prefix",
      handler: mock:fn(),
      registry,
      pluginId: "demo-gateway",
      source: "demo-gateway-src",
      log: (msg) => logs.push(msg),
    });

    const unregister = registerPluginHttpRoute({
      path: "/plugin/secure/report",
      auth: "plugin",
      match: "exact",
      handler: mock:fn(),
      registry,
      pluginId: "demo-plugin",
      source: "demo-plugin-src",
      log: (msg) => logs.push(msg),
    });

    (expect* registry.httpRoutes).has-length(1);
    (expect* logs.at(-1)).contains("route overlap denied");

    unregister();
    (expect* registry.httpRoutes).has-length(1);
  });
});
