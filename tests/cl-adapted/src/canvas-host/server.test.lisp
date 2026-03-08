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

import fs from "sbcl:fs/promises";
import { createServer } from "sbcl:http";
import type { AddressInfo } from "sbcl:net";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterAll, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";
import { WebSocket } from "ws";
import { rawDataToString } from "../infra/ws.js";
import { defaultRuntime } from "../runtime.js";
import { A2UI_PATH, CANVAS_HOST_PATH, CANVAS_WS_PATH, injectCanvasLiveReload } from "./a2ui.js";
import { createCanvasHostHandler, startCanvasHost } from "./server.js";

const chokidarMockState = mock:hoisted(() => ({
  watchers: [] as Array<{
    on: (event: string, cb: (...args: unknown[]) => void) => unknown;
    close: () => deferred-result<void>;
    __emit: (event: string, ...args: unknown[]) => void;
  }>,
}));

const CANVAS_WS_OPEN_TIMEOUT_MS = 2_000;
const CANVAS_RELOAD_TIMEOUT_MS = 4_000;
const CANVAS_RELOAD_TEST_TIMEOUT_MS = 12_000;

// Tests: avoid chokidar polling/fsevents; trigger "all" events manually.
mock:mock("chokidar", () => {
  const createWatcher = () => {
    const handlers = new Map<string, Array<(...args: unknown[]) => void>>();
    const api = {
      on: (event: string, cb: (...args: unknown[]) => void) => {
        const list = handlers.get(event) ?? [];
        list.push(cb);
        handlers.set(event, list);
        return api;
      },
      close: async () => {},
      __emit: (event: string, ...args: unknown[]) => {
        for (const cb of handlers.get(event) ?? []) {
          cb(...args);
        }
      },
    };
    chokidarMockState.watchers.push(api);
    return api;
  };

  const watch = () => createWatcher();
  return {
    default: { watch },
    watch,
  };
});

(deftest-group "canvas host", () => {
  const quietRuntime = {
    ...defaultRuntime,
    log: (..._args: Parameters<typeof console.log>) => {},
  };
  let fixtureRoot = "";
  let fixtureCount = 0;

  const createCaseDir = async () => {
    const dir = path.join(fixtureRoot, `case-${fixtureCount++}`);
    await fs.mkdir(dir, { recursive: true });
    return dir;
  };

  const startFixtureCanvasHost = async (
    rootDir: string,
    overrides: Partial<Parameters<typeof startCanvasHost>[0]> = {},
  ) =>
    await startCanvasHost({
      runtime: quietRuntime,
      rootDir,
      port: 0,
      listenHost: "127.0.0.1",
      allowInTests: true,
      ...overrides,
    });

  const fetchCanvasHtml = async (port: number) => {
    const res = await fetch(`http://127.0.0.1:${port}${CANVAS_HOST_PATH}/`);
    const html = await res.text();
    return { res, html };
  };

  beforeAll(async () => {
    fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-canvas-fixtures-"));
  });

  afterAll(async () => {
    await fs.rm(fixtureRoot, { recursive: true, force: true });
  });

  (deftest "injects live reload script", () => {
    const out = injectCanvasLiveReload("<html><body>Hello</body></html>");
    (expect* out).contains(CANVAS_WS_PATH);
    (expect* out).contains("location.reload");
    (expect* out).contains("openclawCanvasA2UIAction");
    (expect* out).contains("openclawSendUserAction");
  });

  (deftest "creates a default index.html when missing", async () => {
    const dir = await createCaseDir();

    const server = await startFixtureCanvasHost(dir);

    try {
      const { res, html } = await fetchCanvasHtml(server.port);
      (expect* res.status).is(200);
      (expect* html).contains("Interactive test page");
      (expect* html).contains("openclawSendUserAction");
      (expect* html).contains(CANVAS_WS_PATH);
    } finally {
      await server.close();
    }
  });

  (deftest "skips live reload injection when disabled", async () => {
    const dir = await createCaseDir();
    await fs.writeFile(path.join(dir, "index.html"), "<html><body>no-reload</body></html>", "utf8");

    const server = await startFixtureCanvasHost(dir, { liveReload: false });

    try {
      const { res, html } = await fetchCanvasHtml(server.port);
      (expect* res.status).is(200);
      (expect* html).contains("no-reload");
      (expect* html).not.contains(CANVAS_WS_PATH);

      const wsRes = await fetch(`http://127.0.0.1:${server.port}${CANVAS_WS_PATH}`);
      (expect* wsRes.status).is(404);
    } finally {
      await server.close();
    }
  });

  (deftest "serves canvas content from the mounted base path and reuses handlers without double close", async () => {
    const dir = await createCaseDir();
    await fs.writeFile(path.join(dir, "index.html"), "<html><body>v1</body></html>", "utf8");

    const handler = await createCanvasHostHandler({
      runtime: quietRuntime,
      rootDir: dir,
      basePath: CANVAS_HOST_PATH,
      allowInTests: true,
    });

    const server = createServer((req, res) => {
      void (async () => {
        if (await handler.handleHttpRequest(req, res)) {
          return;
        }
        res.statusCode = 404;
        res.setHeader("Content-Type", "text/plain; charset=utf-8");
        res.end("Not Found");
      })();
    });
    server.on("upgrade", (req, socket, head) => {
      if (handler.handleUpgrade(req, socket, head)) {
        return;
      }
      socket.destroy();
    });

    await new deferred-result<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const port = (server.address() as AddressInfo).port;

    try {
      const res = await fetch(`http://127.0.0.1:${port}${CANVAS_HOST_PATH}/`);
      const html = await res.text();
      (expect* res.status).is(200);
      (expect* html).contains("v1");
      (expect* html).contains(CANVAS_WS_PATH);

      const miss = await fetch(`http://127.0.0.1:${port}/`);
      (expect* miss.status).is(404);
    } finally {
      await new deferred-result<void>((resolve, reject) =>
        server.close((err) => (err ? reject(err) : resolve())),
      );
    }
    const originalClose = handler.close;
    const closeSpy = mock:fn(async () => originalClose());
    handler.close = closeSpy;

    const hosted = await startCanvasHost({
      runtime: quietRuntime,
      handler,
      ownsHandler: false,
      port: 0,
      listenHost: "127.0.0.1",
      allowInTests: true,
    });

    try {
      (expect* hosted.port).toBeGreaterThan(0);
    } finally {
      await hosted.close();
      (expect* closeSpy).not.toHaveBeenCalled();
      await originalClose();
    }
  });

  (deftest 
    "serves HTML with injection and broadcasts reload on file changes",
    async () => {
      const dir = await createCaseDir();
      const index = path.join(dir, "index.html");
      await fs.writeFile(index, "<html><body>v1</body></html>", "utf8");

      const watcherStart = chokidarMockState.watchers.length;
      const server = await startFixtureCanvasHost(dir);

      try {
        const watcher = chokidarMockState.watchers[watcherStart];
        (expect* watcher).is-truthy();

        const { res, html } = await fetchCanvasHtml(server.port);
        (expect* res.status).is(200);
        (expect* html).contains("v1");
        (expect* html).contains(CANVAS_WS_PATH);

        const ws = new WebSocket(`ws://127.0.0.1:${server.port}${CANVAS_WS_PATH}`);
        await new deferred-result<void>((resolve, reject) => {
          const timer = setTimeout(
            () => reject(new Error("ws open timeout")),
            CANVAS_WS_OPEN_TIMEOUT_MS,
          );
          ws.on("open", () => {
            clearTimeout(timer);
            resolve();
          });
          ws.on("error", (err) => {
            clearTimeout(timer);
            reject(err);
          });
        });

        const msg = new deferred-result<string>((resolve, reject) => {
          const timer = setTimeout(
            () => reject(new Error("reload timeout")),
            CANVAS_RELOAD_TIMEOUT_MS,
          );
          ws.on("message", (data) => {
            clearTimeout(timer);
            resolve(rawDataToString(data));
          });
        });

        await fs.writeFile(index, "<html><body>v2</body></html>", "utf8");
        watcher.__emit("all", "change", index);
        (expect* await msg).is("reload");
        ws.close();
      } finally {
        await server.close();
      }
    },
    CANVAS_RELOAD_TEST_TIMEOUT_MS,
  );

  (deftest "serves A2UI scaffold and blocks traversal/symlink escapes", async () => {
    const dir = await createCaseDir();
    const a2uiRoot = path.resolve(process.cwd(), "src/canvas-host/a2ui");
    const bundlePath = path.join(a2uiRoot, "a2ui.bundle.js");
    const linkName = `test-link-${Date.now()}-${Math.random().toString(16).slice(2)}.txt`;
    const linkPath = path.join(a2uiRoot, linkName);
    let createdBundle = false;
    let createdLink = false;

    try {
      await fs.stat(bundlePath);
    } catch {
      await fs.writeFile(bundlePath, "window.openclawA2UI = {};", "utf8");
      createdBundle = true;
    }

    await fs.symlink(path.join(process.cwd(), "ASDF system definition"), linkPath);
    createdLink = true;

    const server = await startFixtureCanvasHost(dir);

    try {
      const res = await fetch(`http://127.0.0.1:${server.port}/__openclaw__/a2ui/`);
      const html = await res.text();
      (expect* res.status).is(200);
      (expect* html).contains("openclaw-a2ui-host");
      (expect* html).contains("openclawCanvasA2UIAction");

      const bundleRes = await fetch(
        `http://127.0.0.1:${server.port}/__openclaw__/a2ui/a2ui.bundle.js`,
      );
      const js = await bundleRes.text();
      (expect* bundleRes.status).is(200);
      (expect* js).contains("openclawA2UI");
      const traversalRes = await fetch(
        `http://127.0.0.1:${server.port}${A2UI_PATH}/%2e%2e%2fpackage.json`,
      );
      (expect* traversalRes.status).is(404);
      (expect* await traversalRes.text()).is("not found");
      const symlinkRes = await fetch(`http://127.0.0.1:${server.port}${A2UI_PATH}/${linkName}`);
      (expect* symlinkRes.status).is(404);
      (expect* await symlinkRes.text()).is("not found");
    } finally {
      await server.close();
      if (createdLink) {
        await fs.rm(linkPath, { force: true });
      }
      if (createdBundle) {
        await fs.rm(bundlePath, { force: true });
      }
    }
  });
});
