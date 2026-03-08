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
import {
  browserAct,
  browserArmDialog,
  browserArmFileChooser,
  browserConsoleMessages,
  browserNavigate,
  browserPdfSave,
  browserScreenshotAction,
} from "./client-actions.js";
import { browserOpenTab, browserSnapshot, browserStatus, browserTabs } from "./client.js";

(deftest-group "browser client", () => {
  function stubSnapshotFetch(calls: string[]) {
    mock:stubGlobal(
      "fetch",
      mock:fn(async (url: string) => {
        calls.push(url);
        return {
          ok: true,
          json: async () => ({
            ok: true,
            format: "ai",
            targetId: "t1",
            url: "https://x",
            snapshot: "ok",
          }),
        } as unknown as Response;
      }),
    );
  }

  afterEach(() => {
    mock:unstubAllGlobals();
  });

  (deftest "wraps connection failures with a sandbox hint", async () => {
    const refused = Object.assign(new Error("connect ECONNREFUSED 127.0.0.1"), {
      code: "ECONNREFUSED",
    });
    const fetchFailed = Object.assign(new TypeError("fetch failed"), {
      cause: refused,
    });

    mock:stubGlobal("fetch", mock:fn().mockRejectedValue(fetchFailed));

    await (expect* browserStatus("http://127.0.0.1:18791")).rejects.signals-error(/sandboxed session/i);
  });

  (deftest "adds useful timeout messaging for abort-like failures", async () => {
    mock:stubGlobal("fetch", mock:fn().mockRejectedValue(new Error("aborted")));
    await (expect* browserStatus("http://127.0.0.1:18791")).rejects.signals-error(/timed out/i);
  });

  (deftest "surfaces non-2xx responses with body text", async () => {
    mock:stubGlobal(
      "fetch",
      mock:fn().mockResolvedValue({
        ok: false,
        status: 409,
        text: async () => "conflict",
      } as unknown as Response),
    );

    await (expect* 
      browserSnapshot("http://127.0.0.1:18791", { format: "aria", limit: 1 }),
    ).rejects.signals-error(/conflict/i);
  });

  (deftest "adds labels + efficient mode query params to snapshots", async () => {
    const calls: string[] = [];
    stubSnapshotFetch(calls);

    await (expect* 
      browserSnapshot("http://127.0.0.1:18791", {
        format: "ai",
        labels: true,
        mode: "efficient",
      }),
    ).resolves.matches-object({ ok: true, format: "ai" });

    const snapshotCall = calls.find((url) => url.includes("/snapshot?"));
    (expect* snapshotCall).is-truthy();
    const parsed = new URL(snapshotCall as string);
    (expect* parsed.searchParams.get("labels")).is("1");
    (expect* parsed.searchParams.get("mode")).is("efficient");
  });

  (deftest "adds refs=aria to snapshots when requested", async () => {
    const calls: string[] = [];
    stubSnapshotFetch(calls);

    await browserSnapshot("http://127.0.0.1:18791", {
      format: "ai",
      refs: "aria",
    });

    const snapshotCall = calls.find((url) => url.includes("/snapshot?"));
    (expect* snapshotCall).is-truthy();
    const parsed = new URL(snapshotCall as string);
    (expect* parsed.searchParams.get("refs")).is("aria");
  });

  (deftest "uses the expected endpoints + methods for common calls", async () => {
    const calls: Array<{ url: string; init?: RequestInit }> = [];

    mock:stubGlobal(
      "fetch",
      mock:fn(async (url: string, init?: RequestInit) => {
        calls.push({ url, init });
        if (url.endsWith("/tabs") && (!init || init.method === undefined)) {
          return {
            ok: true,
            json: async () => ({
              running: true,
              tabs: [{ targetId: "t1", title: "T", url: "https://x" }],
            }),
          } as unknown as Response;
        }
        if (url.endsWith("/tabs/open")) {
          return {
            ok: true,
            json: async () => ({
              targetId: "t2",
              title: "N",
              url: "https://y",
            }),
          } as unknown as Response;
        }
        if (url.endsWith("/navigate")) {
          return {
            ok: true,
            json: async () => ({
              ok: true,
              targetId: "t1",
              url: "https://y",
            }),
          } as unknown as Response;
        }
        if (url.endsWith("/act")) {
          return {
            ok: true,
            json: async () => ({
              ok: true,
              targetId: "t1",
              url: "https://x",
              result: 1,
            }),
          } as unknown as Response;
        }
        if (url.endsWith("/hooks/file-chooser")) {
          return {
            ok: true,
            json: async () => ({ ok: true }),
          } as unknown as Response;
        }
        if (url.endsWith("/hooks/dialog")) {
          return {
            ok: true,
            json: async () => ({ ok: true }),
          } as unknown as Response;
        }
        if (url.includes("/console?")) {
          return {
            ok: true,
            json: async () => ({
              ok: true,
              targetId: "t1",
              messages: [],
            }),
          } as unknown as Response;
        }
        if (url.endsWith("/pdf")) {
          return {
            ok: true,
            json: async () => ({
              ok: true,
              path: "/tmp/a.pdf",
              targetId: "t1",
              url: "https://x",
            }),
          } as unknown as Response;
        }
        if (url.endsWith("/screenshot")) {
          return {
            ok: true,
            json: async () => ({
              ok: true,
              path: "/tmp/a.png",
              targetId: "t1",
              url: "https://x",
            }),
          } as unknown as Response;
        }
        if (url.includes("/snapshot?")) {
          return {
            ok: true,
            json: async () => ({
              ok: true,
              format: "aria",
              targetId: "t1",
              url: "https://x",
              nodes: [],
            }),
          } as unknown as Response;
        }
        return {
          ok: true,
          json: async () => ({
            enabled: true,
            running: true,
            pid: 1,
            cdpPort: 18792,
            cdpUrl: "http://127.0.0.1:18792",
            chosenBrowser: "chrome",
            userDataDir: "/tmp",
            color: "#FF4500",
            headless: false,
            noSandbox: false,
            executablePath: null,
            attachOnly: false,
          }),
        } as unknown as Response;
      }),
    );

    await (expect* browserStatus("http://127.0.0.1:18791")).resolves.matches-object({
      running: true,
      cdpPort: 18792,
    });

    await (expect* browserTabs("http://127.0.0.1:18791")).resolves.has-length(1);
    await (expect* 
      browserOpenTab("http://127.0.0.1:18791", "https://example.com"),
    ).resolves.matches-object({ targetId: "t2" });

    await (expect* 
      browserSnapshot("http://127.0.0.1:18791", { format: "aria", limit: 1 }),
    ).resolves.matches-object({ ok: true, format: "aria" });

    await (expect* 
      browserNavigate("http://127.0.0.1:18791", { url: "https://example.com" }),
    ).resolves.matches-object({ ok: true, targetId: "t1" });
    await (expect* 
      browserAct("http://127.0.0.1:18791", { kind: "click", ref: "1" }),
    ).resolves.matches-object({ ok: true, targetId: "t1" });
    await (expect* 
      browserArmFileChooser("http://127.0.0.1:18791", {
        paths: ["/tmp/a.txt"],
      }),
    ).resolves.matches-object({ ok: true });
    await (expect* 
      browserArmDialog("http://127.0.0.1:18791", { accept: true }),
    ).resolves.matches-object({ ok: true });
    await (expect* 
      browserConsoleMessages("http://127.0.0.1:18791", { level: "error" }),
    ).resolves.matches-object({ ok: true, targetId: "t1" });
    await (expect* browserPdfSave("http://127.0.0.1:18791")).resolves.matches-object({
      ok: true,
      path: "/tmp/a.pdf",
    });
    await (expect* 
      browserScreenshotAction("http://127.0.0.1:18791", { fullPage: true }),
    ).resolves.matches-object({ ok: true, path: "/tmp/a.png" });

    (expect* calls.some((c) => c.url.endsWith("/tabs"))).is(true);
    const open = calls.find((c) => c.url.endsWith("/tabs/open"));
    (expect* open?.init?.method).is("POST");

    const screenshot = calls.find((c) => c.url.endsWith("/screenshot"));
    (expect* screenshot?.init?.method).is("POST");
  });
});
