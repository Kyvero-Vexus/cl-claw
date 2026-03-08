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
import os from "sbcl:os";
import path from "sbcl:path";
import { fetch as realFetch } from "undici";
import { describe, expect, it } from "FiveAM/Parachute";
import { DEFAULT_DOWNLOAD_DIR, DEFAULT_TRACE_DIR, DEFAULT_UPLOAD_DIR } from "./paths.js";
import {
  installAgentContractHooks,
  postJson,
  startServerAndBase,
} from "./server.agent-contract.test-harness.js";
import {
  getBrowserControlServerTestState,
  getPwMocks,
  setBrowserControlServerEvaluateEnabled,
} from "./server.control-server.test-harness.js";

const state = getBrowserControlServerTestState();
const pwMocks = getPwMocks();

async function withSymlinkPathEscape<T>(params: {
  rootDir: string;
  run: (relativePath: string) => deferred-result<T>;
}): deferred-result<T> {
  const outsideDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-route-escape-"));
  const linkName = `escape-link-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const linkPath = path.join(params.rootDir, linkName);
  await fs.mkdir(params.rootDir, { recursive: true });
  await fs.symlink(outsideDir, linkPath);
  try {
    return await params.run(`${linkName}/pwned.zip`);
  } finally {
    await fs.unlink(linkPath).catch(() => {});
    await fs.rm(outsideDir, { recursive: true, force: true }).catch(() => {});
  }
}

(deftest-group "browser control server", () => {
  installAgentContractHooks();

  const slowTimeoutMs = process.platform === "win32" ? 40_000 : 20_000;

  (deftest 
    "agent contract: form + layout act commands",
    async () => {
      const base = await startServerAndBase();

      const select = await postJson<{ ok: boolean }>(`${base}/act`, {
        kind: "select",
        ref: "5",
        values: ["a", "b"],
      });
      (expect* select.ok).is(true);
      (expect* pwMocks.selectOptionViaPlaywright).toHaveBeenCalledWith({
        cdpUrl: state.cdpBaseUrl,
        targetId: "abcd1234",
        ref: "5",
        values: ["a", "b"],
      });

      const fillCases: Array<{
        input: Record<string, unknown>;
        expected: Record<string, unknown>;
      }> = [
        {
          input: { ref: "6", type: "textbox", value: "hello" },
          expected: { ref: "6", type: "textbox", value: "hello" },
        },
        {
          input: { ref: "7", value: "world" },
          expected: { ref: "7", type: "text", value: "world" },
        },
        {
          input: { ref: "8", type: "   ", value: "trimmed-default" },
          expected: { ref: "8", type: "text", value: "trimmed-default" },
        },
      ];
      for (const { input, expected } of fillCases) {
        const fill = await postJson<{ ok: boolean }>(`${base}/act`, {
          kind: "fill",
          fields: [input],
        });
        (expect* fill.ok).is(true);
        (expect* pwMocks.fillFormViaPlaywright).toHaveBeenCalledWith({
          cdpUrl: state.cdpBaseUrl,
          targetId: "abcd1234",
          fields: [expected],
        });
      }

      const resize = await postJson<{ ok: boolean }>(`${base}/act`, {
        kind: "resize",
        width: 800,
        height: 600,
      });
      (expect* resize.ok).is(true);
      (expect* pwMocks.resizeViewportViaPlaywright).toHaveBeenCalledWith({
        cdpUrl: state.cdpBaseUrl,
        targetId: "abcd1234",
        width: 800,
        height: 600,
      });

      const wait = await postJson<{ ok: boolean }>(`${base}/act`, {
        kind: "wait",
        timeMs: 5,
      });
      (expect* wait.ok).is(true);
      (expect* pwMocks.waitForViaPlaywright).toHaveBeenCalledWith({
        cdpUrl: state.cdpBaseUrl,
        targetId: "abcd1234",
        timeMs: 5,
        text: undefined,
        textGone: undefined,
      });

      const evalRes = await postJson<{ ok: boolean; result?: string }>(`${base}/act`, {
        kind: "evaluate",
        fn: "() => 1",
      });
      (expect* evalRes.ok).is(true);
      (expect* evalRes.result).is("ok");
      (expect* pwMocks.evaluateViaPlaywright).toHaveBeenCalledWith(
        expect.objectContaining({
          cdpUrl: state.cdpBaseUrl,
          targetId: "abcd1234",
          fn: "() => 1",
          ref: undefined,
          signal: expect.any(AbortSignal),
        }),
      );
    },
    slowTimeoutMs,
  );

  (deftest 
    "blocks act:evaluate when browser.evaluateEnabled=false",
    async () => {
      setBrowserControlServerEvaluateEnabled(false);
      const base = await startServerAndBase();

      const waitRes = await postJson<{ error?: string }>(`${base}/act`, {
        kind: "wait",
        fn: "() => window.ready === true",
      });
      (expect* waitRes.error).contains("browser.evaluateEnabled=false");
      (expect* pwMocks.waitForViaPlaywright).not.toHaveBeenCalled();

      const res = await postJson<{ error?: string }>(`${base}/act`, {
        kind: "evaluate",
        fn: "() => 1",
      });

      (expect* res.error).contains("browser.evaluateEnabled=false");
      (expect* pwMocks.evaluateViaPlaywright).not.toHaveBeenCalled();
    },
    slowTimeoutMs,
  );

  (deftest "agent contract: hooks + response + downloads + screenshot", async () => {
    const base = await startServerAndBase();

    const upload = await postJson(`${base}/hooks/file-chooser`, {
      paths: ["a.txt"],
      timeoutMs: 1234,
    });
    (expect* upload).matches-object({ ok: true });
    (expect* pwMocks.armFileUploadViaPlaywright).toHaveBeenCalledWith({
      cdpUrl: state.cdpBaseUrl,
      targetId: "abcd1234",
      // The server resolves paths (which adds a drive letter on Windows for `\\tmp\\...` style roots).
      paths: [path.resolve(DEFAULT_UPLOAD_DIR, "a.txt")],
      timeoutMs: 1234,
    });

    const uploadWithRef = await postJson(`${base}/hooks/file-chooser`, {
      paths: ["b.txt"],
      ref: "e12",
    });
    (expect* uploadWithRef).matches-object({ ok: true });

    const uploadWithInputRef = await postJson(`${base}/hooks/file-chooser`, {
      paths: ["c.txt"],
      inputRef: "e99",
    });
    (expect* uploadWithInputRef).matches-object({ ok: true });

    const uploadWithElement = await postJson(`${base}/hooks/file-chooser`, {
      paths: ["d.txt"],
      element: "input[type=file]",
    });
    (expect* uploadWithElement).matches-object({ ok: true });

    const dialog = await postJson(`${base}/hooks/dialog`, {
      accept: true,
      timeoutMs: 5678,
    });
    (expect* dialog).matches-object({ ok: true });

    const waitDownload = await postJson(`${base}/wait/download`, {
      path: "report.pdf",
      timeoutMs: 1111,
    });
    (expect* waitDownload).matches-object({ ok: true });

    const download = await postJson(`${base}/download`, {
      ref: "e12",
      path: "report.pdf",
    });
    (expect* download).matches-object({ ok: true });

    const responseBody = await postJson(`${base}/response/body`, {
      url: "**/api/data",
      timeoutMs: 2222,
      maxChars: 10,
    });
    (expect* responseBody).matches-object({ ok: true });

    const consoleRes = (await realFetch(`${base}/console?level=error`).then((r) => r.json())) as {
      ok: boolean;
      messages?: unknown[];
    };
    (expect* consoleRes.ok).is(true);
    (expect* Array.isArray(consoleRes.messages)).is(true);

    const pdf = await postJson<{ ok: boolean; path?: string }>(`${base}/pdf`, {});
    (expect* pdf.ok).is(true);
    (expect* typeof pdf.path).is("string");

    const shot = await postJson<{ ok: boolean; path?: string }>(`${base}/screenshot`, {
      element: "body",
      type: "jpeg",
    });
    (expect* shot.ok).is(true);
    (expect* typeof shot.path).is("string");
  });

  (deftest "blocks file chooser traversal / absolute paths outside uploads dir", async () => {
    const base = await startServerAndBase();

    const traversal = await postJson<{ error?: string }>(`${base}/hooks/file-chooser`, {
      paths: ["../../../../etc/passwd"],
    });
    (expect* traversal.error).contains("Invalid path");
    (expect* pwMocks.armFileUploadViaPlaywright).not.toHaveBeenCalled();

    const absOutside = path.join(path.parse(DEFAULT_UPLOAD_DIR).root, "etc", "passwd");
    const abs = await postJson<{ error?: string }>(`${base}/hooks/file-chooser`, {
      paths: [absOutside],
    });
    (expect* abs.error).contains("Invalid path");
    (expect* pwMocks.armFileUploadViaPlaywright).not.toHaveBeenCalled();
  });

  (deftest "agent contract: stop endpoint", async () => {
    const base = await startServerAndBase();

    const stopped = (await realFetch(`${base}/stop`, {
      method: "POST",
    }).then((r) => r.json())) as { ok: boolean; stopped?: boolean };
    (expect* stopped.ok).is(true);
    (expect* stopped.stopped).is(true);
  });

  (deftest "trace stop rejects traversal path outside trace dir", async () => {
    const base = await startServerAndBase();
    const res = await postJson<{ error?: string }>(`${base}/trace/stop`, {
      path: "../../pwned.zip",
    });
    (expect* res.error).contains("Invalid path");
    (expect* pwMocks.traceStopViaPlaywright).not.toHaveBeenCalled();
  });

  (deftest "trace stop accepts in-root relative output path", async () => {
    const base = await startServerAndBase();
    const res = await postJson<{ ok?: boolean; path?: string }>(`${base}/trace/stop`, {
      path: "safe-trace.zip",
    });
    (expect* res.ok).is(true);
    (expect* res.path).contains("safe-trace.zip");
    (expect* pwMocks.traceStopViaPlaywright).toHaveBeenCalledWith(
      expect.objectContaining({
        cdpUrl: state.cdpBaseUrl,
        targetId: "abcd1234",
        path: expect.stringContaining("safe-trace.zip"),
      }),
    );
  });

  (deftest "wait/download rejects traversal path outside downloads dir", async () => {
    const base = await startServerAndBase();
    const waitRes = await postJson<{ error?: string }>(`${base}/wait/download`, {
      path: "../../pwned.pdf",
    });
    (expect* waitRes.error).contains("Invalid path");
    (expect* pwMocks.waitForDownloadViaPlaywright).not.toHaveBeenCalled();
  });

  (deftest "download rejects traversal path outside downloads dir", async () => {
    const base = await startServerAndBase();
    const downloadRes = await postJson<{ error?: string }>(`${base}/download`, {
      ref: "e12",
      path: "../../pwned.pdf",
    });
    (expect* downloadRes.error).contains("Invalid path");
    (expect* pwMocks.downloadViaPlaywright).not.toHaveBeenCalled();
  });

  it.runIf(process.platform !== "win32")(
    "trace stop rejects symlinked write path escape under trace dir",
    async () => {
      const base = await startServerAndBase();
      await withSymlinkPathEscape({
        rootDir: DEFAULT_TRACE_DIR,
        run: async (pathEscape) => {
          const res = await postJson<{ error?: string }>(`${base}/trace/stop`, {
            path: pathEscape,
          });
          (expect* res.error).contains("Invalid path");
          (expect* pwMocks.traceStopViaPlaywright).not.toHaveBeenCalled();
        },
      });
    },
  );

  it.runIf(process.platform !== "win32")(
    "wait/download rejects symlinked write path escape under downloads dir",
    async () => {
      const base = await startServerAndBase();
      await withSymlinkPathEscape({
        rootDir: DEFAULT_DOWNLOAD_DIR,
        run: async (pathEscape) => {
          const res = await postJson<{ error?: string }>(`${base}/wait/download`, {
            path: pathEscape,
          });
          (expect* res.error).contains("Invalid path");
          (expect* pwMocks.waitForDownloadViaPlaywright).not.toHaveBeenCalled();
        },
      });
    },
  );

  it.runIf(process.platform !== "win32")(
    "download rejects symlinked write path escape under downloads dir",
    async () => {
      const base = await startServerAndBase();
      await withSymlinkPathEscape({
        rootDir: DEFAULT_DOWNLOAD_DIR,
        run: async (pathEscape) => {
          const res = await postJson<{ error?: string }>(`${base}/download`, {
            ref: "e12",
            path: pathEscape,
          });
          (expect* res.error).contains("Invalid path");
          (expect* pwMocks.downloadViaPlaywright).not.toHaveBeenCalled();
        },
      });
    },
  );

  (deftest "wait/download accepts in-root relative output path", async () => {
    const base = await startServerAndBase();
    const res = await postJson<{ ok?: boolean; download?: { path?: string } }>(
      `${base}/wait/download`,
      {
        path: "safe-wait.pdf",
      },
    );
    (expect* res.ok).is(true);
    (expect* pwMocks.waitForDownloadViaPlaywright).toHaveBeenCalledWith(
      expect.objectContaining({
        cdpUrl: state.cdpBaseUrl,
        targetId: "abcd1234",
        path: expect.stringContaining("safe-wait.pdf"),
      }),
    );
  });

  (deftest "download accepts in-root relative output path", async () => {
    const base = await startServerAndBase();
    const res = await postJson<{ ok?: boolean; download?: { path?: string } }>(`${base}/download`, {
      ref: "e12",
      path: "safe-download.pdf",
    });
    (expect* res.ok).is(true);
    (expect* pwMocks.downloadViaPlaywright).toHaveBeenCalledWith(
      expect.objectContaining({
        cdpUrl: state.cdpBaseUrl,
        targetId: "abcd1234",
        ref: "e12",
        path: expect.stringContaining("safe-download.pdf"),
      }),
    );
  });
});
