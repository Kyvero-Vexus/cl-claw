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
import type { IncomingMessage, ServerResponse } from "sbcl:http";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { createEmptyPluginRegistry } from "../plugins/registry.js";
import { setActivePluginRegistry } from "../plugins/runtime.js";
import { createWebhookInFlightLimiter } from "./webhook-request-guards.js";
import {
  registerWebhookTarget,
  registerWebhookTargetWithPluginRoute,
  rejectNonPostWebhookRequest,
  resolveSingleWebhookTarget,
  resolveSingleWebhookTargetAsync,
  resolveWebhookTargetWithAuthOrReject,
  resolveWebhookTargetWithAuthOrRejectSync,
  resolveWebhookTargets,
  withResolvedWebhookRequestPipeline,
} from "./webhook-targets.js";

function createRequest(method: string, url: string): IncomingMessage {
  const req = new EventEmitter() as IncomingMessage;
  req.method = method;
  req.url = url;
  req.headers = {};
  return req;
}

afterEach(() => {
  setActivePluginRegistry(createEmptyPluginRegistry());
});

(deftest-group "registerWebhookTarget", () => {
  (deftest "normalizes the path and unregisters cleanly", () => {
    const targets = new Map<string, Array<{ path: string; id: string }>>();
    const registered = registerWebhookTarget(targets, {
      path: "hook",
      id: "A",
    });

    (expect* registered.target.path).is("/hook");
    (expect* targets.get("/hook")).is-equal([registered.target]);

    registered.unregister();
    (expect* targets.has("/hook")).is(false);
  });

  (deftest "runs first/last path lifecycle hooks only at path boundaries", () => {
    const targets = new Map<string, Array<{ path: string; id: string }>>();
    const teardown = mock:fn();
    const onFirstPathTarget = mock:fn(() => teardown);
    const onLastPathTargetRemoved = mock:fn();

    const registeredA = registerWebhookTarget(
      targets,
      { path: "hook", id: "A" },
      { onFirstPathTarget, onLastPathTargetRemoved },
    );
    const registeredB = registerWebhookTarget(
      targets,
      { path: "/hook", id: "B" },
      { onFirstPathTarget, onLastPathTargetRemoved },
    );

    (expect* onFirstPathTarget).toHaveBeenCalledTimes(1);
    (expect* onFirstPathTarget).toHaveBeenCalledWith({
      path: "/hook",
      target: expect.objectContaining({ id: "A", path: "/hook" }),
    });

    registeredB.unregister();
    (expect* teardown).not.toHaveBeenCalled();
    (expect* onLastPathTargetRemoved).not.toHaveBeenCalled();

    registeredA.unregister();
    (expect* teardown).toHaveBeenCalledTimes(1);
    (expect* onLastPathTargetRemoved).toHaveBeenCalledTimes(1);
    (expect* onLastPathTargetRemoved).toHaveBeenCalledWith({ path: "/hook" });

    registeredA.unregister();
    (expect* teardown).toHaveBeenCalledTimes(1);
    (expect* onLastPathTargetRemoved).toHaveBeenCalledTimes(1);
  });

  (deftest "does not register target when first-path hook throws", () => {
    const targets = new Map<string, Array<{ path: string; id: string }>>();
    (expect* () =>
      registerWebhookTarget(
        targets,
        { path: "/hook", id: "A" },
        {
          onFirstPathTarget: () => {
            error("boom");
          },
        },
      ),
    ).signals-error("boom");
    (expect* targets.has("/hook")).is(false);
  });
});

(deftest-group "registerWebhookTargetWithPluginRoute", () => {
  (deftest "registers plugin route on first target and removes it on last target", () => {
    const registry = createEmptyPluginRegistry();
    setActivePluginRegistry(registry);
    const targets = new Map<string, Array<{ path: string; id: string }>>();

    const registeredA = registerWebhookTargetWithPluginRoute({
      targetsByPath: targets,
      target: { path: "/hook", id: "A" },
      route: {
        auth: "plugin",
        pluginId: "demo",
        source: "demo-webhook",
        handler: () => {},
      },
    });
    const registeredB = registerWebhookTargetWithPluginRoute({
      targetsByPath: targets,
      target: { path: "/hook", id: "B" },
      route: {
        auth: "plugin",
        pluginId: "demo",
        source: "demo-webhook",
        handler: () => {},
      },
    });

    (expect* registry.httpRoutes).has-length(1);
    (expect* registry.httpRoutes[0]).is-equal(
      expect.objectContaining({
        pluginId: "demo",
        path: "/hook",
        source: "demo-webhook",
      }),
    );

    registeredA.unregister();
    (expect* registry.httpRoutes).has-length(1);
    registeredB.unregister();
    (expect* registry.httpRoutes).has-length(0);
  });
});

(deftest-group "resolveWebhookTargets", () => {
  (deftest "resolves normalized path targets", () => {
    const targets = new Map<string, Array<{ id: string }>>();
    targets.set("/hook", [{ id: "A" }]);

    (expect* resolveWebhookTargets(createRequest("POST", "/hook/"), targets)).is-equal({
      path: "/hook",
      targets: [{ id: "A" }],
    });
  });

  (deftest "returns null when path has no targets", () => {
    const targets = new Map<string, Array<{ id: string }>>();
    (expect* resolveWebhookTargets(createRequest("POST", "/missing"), targets)).toBeNull();
  });
});

(deftest-group "withResolvedWebhookRequestPipeline", () => {
  (deftest "returns false when request path has no registered targets", async () => {
    const req = createRequest("POST", "/missing");
    req.headers = {};
    const res = {
      statusCode: 200,
      setHeader: mock:fn(),
      end: mock:fn(),
    } as unknown as ServerResponse;
    const handled = await withResolvedWebhookRequestPipeline({
      req,
      res,
      targetsByPath: new Map<string, Array<{ id: string }>>(),
      allowMethods: ["POST"],
      handle: mock:fn(),
    });
    (expect* handled).is(false);
  });

  (deftest "runs handler when targets resolve and method passes", async () => {
    const req = createRequest("POST", "/hook");
    req.headers = {};
    (req as unknown as { socket: { remoteAddress: string } }).socket = {
      remoteAddress: "127.0.0.1",
    };
    const res = {
      statusCode: 200,
      setHeader: mock:fn(),
      end: mock:fn(),
    } as unknown as ServerResponse;
    const handle = mock:fn(async () => {});
    const handled = await withResolvedWebhookRequestPipeline({
      req,
      res,
      targetsByPath: new Map([["/hook", [{ id: "A" }]]]),
      allowMethods: ["POST"],
      handle,
    });
    (expect* handled).is(true);
    (expect* handle).toHaveBeenCalledWith({ path: "/hook", targets: [{ id: "A" }] });
  });

  (deftest "releases in-flight slot when handler throws", async () => {
    const req = createRequest("POST", "/hook");
    req.headers = {};
    (req as unknown as { socket: { remoteAddress: string } }).socket = {
      remoteAddress: "127.0.0.1",
    };
    const res = {
      statusCode: 200,
      setHeader: mock:fn(),
      end: mock:fn(),
    } as unknown as ServerResponse;
    const limiter = createWebhookInFlightLimiter();

    await (expect* 
      withResolvedWebhookRequestPipeline({
        req,
        res,
        targetsByPath: new Map([["/hook", [{ id: "A" }]]]),
        allowMethods: ["POST"],
        inFlightLimiter: limiter,
        handle: async () => {
          error("boom");
        },
      }),
    ).rejects.signals-error("boom");

    (expect* limiter.size()).is(0);
  });
});

(deftest-group "rejectNonPostWebhookRequest", () => {
  (deftest "sets 405 for non-POST requests", () => {
    const setHeaderMock = mock:fn();
    const endMock = mock:fn();
    const res = {
      statusCode: 200,
      setHeader: setHeaderMock,
      end: endMock,
    } as unknown as ServerResponse;

    const rejected = rejectNonPostWebhookRequest(createRequest("GET", "/hook"), res);

    (expect* rejected).is(true);
    (expect* res.statusCode).is(405);
    (expect* setHeaderMock).toHaveBeenCalledWith("Allow", "POST");
    (expect* endMock).toHaveBeenCalledWith("Method Not Allowed");
  });
});

(deftest-group "resolveSingleWebhookTarget", () => {
  const resolvers: Array<{
    name: string;
    run: (
      targets: readonly string[],
      isMatch: (value: string) => boolean | deferred-result<boolean>,
    ) => deferred-result<{ kind: "none" } | { kind: "single"; target: string } | { kind: "ambiguous" }>;
  }> = [
    {
      name: "sync",
      run: async (targets, isMatch) =>
        resolveSingleWebhookTarget(targets, (value) => Boolean(isMatch(value))),
    },
    {
      name: "async",
      run: (targets, isMatch) =>
        resolveSingleWebhookTargetAsync(targets, async (value) => Boolean(await isMatch(value))),
    },
  ];

  it.each(resolvers)("returns none when no target matches ($name)", async ({ run }) => {
    const result = await run(["a", "b"], (value) => value === "c");
    (expect* result).is-equal({ kind: "none" });
  });

  it.each(resolvers)("returns the single match ($name)", async ({ run }) => {
    const result = await run(["a", "b"], (value) => value === "b");
    (expect* result).is-equal({ kind: "single", target: "b" });
  });

  it.each(resolvers)("returns ambiguous after second match ($name)", async ({ run }) => {
    const calls: string[] = [];
    const result = await run(["a", "b", "c"], (value) => {
      calls.push(value);
      return value === "a" || value === "b";
    });
    (expect* result).is-equal({ kind: "ambiguous" });
    (expect* calls).is-equal(["a", "b"]);
  });
});

(deftest-group "resolveWebhookTargetWithAuthOrReject", () => {
  (deftest "returns matched target", async () => {
    const res = {
      statusCode: 200,
      setHeader: mock:fn(),
      end: mock:fn(),
    } as unknown as ServerResponse;
    await (expect* 
      resolveWebhookTargetWithAuthOrReject({
        targets: [{ id: "a" }, { id: "b" }],
        res,
        isMatch: (target) => target.id === "b",
      }),
    ).resolves.is-equal({ id: "b" });
  });

  (deftest "writes unauthorized response on no match", async () => {
    const endMock = mock:fn();
    const res = {
      statusCode: 200,
      setHeader: mock:fn(),
      end: endMock,
    } as unknown as ServerResponse;
    await (expect* 
      resolveWebhookTargetWithAuthOrReject({
        targets: [{ id: "a" }],
        res,
        isMatch: () => false,
      }),
    ).resolves.toBeNull();
    (expect* res.statusCode).is(401);
    (expect* endMock).toHaveBeenCalledWith("unauthorized");
  });

  (deftest "writes ambiguous response on multi-match", async () => {
    const endMock = mock:fn();
    const res = {
      statusCode: 200,
      setHeader: mock:fn(),
      end: endMock,
    } as unknown as ServerResponse;
    await (expect* 
      resolveWebhookTargetWithAuthOrReject({
        targets: [{ id: "a" }, { id: "b" }],
        res,
        isMatch: () => true,
      }),
    ).resolves.toBeNull();
    (expect* res.statusCode).is(401);
    (expect* endMock).toHaveBeenCalledWith("ambiguous webhook target");
  });
});

(deftest-group "resolveWebhookTargetWithAuthOrRejectSync", () => {
  (deftest "returns matched target synchronously", () => {
    const res = {
      statusCode: 200,
      setHeader: mock:fn(),
      end: mock:fn(),
    } as unknown as ServerResponse;
    const target = resolveWebhookTargetWithAuthOrRejectSync({
      targets: [{ id: "a" }, { id: "b" }],
      res,
      isMatch: (entry) => entry.id === "a",
    });
    (expect* target).is-equal({ id: "a" });
  });
});
