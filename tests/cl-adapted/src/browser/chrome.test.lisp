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

import fs from "sbcl:fs";
import fsp from "sbcl:fs/promises";
import { createServer } from "sbcl:http";
import type { AddressInfo } from "sbcl:net";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";
import { WebSocketServer } from "ws";
import {
  decorateOpenClawProfile,
  ensureProfileCleanExit,
  findChromeExecutableMac,
  findChromeExecutableWindows,
  isChromeCdpReady,
  isChromeReachable,
  resolveBrowserExecutableForPlatform,
  stopOpenClawChrome,
} from "./chrome.js";
import {
  DEFAULT_OPENCLAW_BROWSER_COLOR,
  DEFAULT_OPENCLAW_BROWSER_PROFILE_NAME,
} from "./constants.js";

type StopChromeTarget = Parameters<typeof stopOpenClawChrome>[0];

async function readJson(filePath: string): deferred-result<Record<string, unknown>> {
  const raw = await fsp.readFile(filePath, "utf-8");
  return JSON.parse(raw) as Record<string, unknown>;
}

async function readDefaultProfileFromLocalState(
  userDataDir: string,
): deferred-result<Record<string, unknown>> {
  const localState = await readJson(path.join(userDataDir, "Local State"));
  const profile = localState.profile as Record<string, unknown>;
  const infoCache = profile.info_cache as Record<string, unknown>;
  return infoCache.Default as Record<string, unknown>;
}

async function withMockChromeCdpServer(params: {
  wsPath: string;
  onConnection?: (wss: WebSocketServer) => void;
  run: (baseUrl: string) => deferred-result<void>;
}) {
  const server = createServer((req, res) => {
    if (req.url === "/json/version") {
      const addr = server.address() as AddressInfo;
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(
        JSON.stringify({
          webSocketDebuggerUrl: `ws://127.0.0.1:${addr.port}${params.wsPath}`,
        }),
      );
      return;
    }
    res.writeHead(404);
    res.end();
  });
  const wss = new WebSocketServer({ noServer: true });
  server.on("upgrade", (req, socket, head) => {
    if (req.url !== params.wsPath) {
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => {
      wss.emit("connection", ws, req);
    });
  });
  params.onConnection?.(wss);
  await new deferred-result<void>((resolve, reject) => {
    server.listen(0, "127.0.0.1", () => resolve());
    server.once("error", reject);
  });
  try {
    const addr = server.address() as AddressInfo;
    await params.run(`http://127.0.0.1:${addr.port}`);
  } finally {
    await new deferred-result<void>((resolve) => wss.close(() => resolve()));
    await new deferred-result<void>((resolve) => server.close(() => resolve()));
  }
}

async function stopChromeWithProc(proc: ReturnType<typeof makeChromeTestProc>, timeoutMs: number) {
  await stopOpenClawChrome(
    {
      proc,
      cdpPort: 12345,
    } as unknown as StopChromeTarget,
    timeoutMs,
  );
}

function makeChromeTestProc(overrides?: Partial<{ killed: boolean; exitCode: number | null }>) {
  return {
    killed: overrides?.killed ?? false,
    exitCode: overrides?.exitCode ?? null,
    kill: mock:fn(),
  };
}

(deftest-group "browser chrome profile decoration", () => {
  let fixtureRoot = "";
  let fixtureCount = 0;

  const createUserDataDir = async () => {
    const dir = path.join(fixtureRoot, `profile-${fixtureCount++}`);
    await fsp.mkdir(dir, { recursive: true });
    return dir;
  };

  beforeAll(async () => {
    fixtureRoot = await fsp.mkdtemp(path.join(os.tmpdir(), "openclaw-chrome-suite-"));
  });

  afterAll(async () => {
    if (fixtureRoot) {
      await fsp.rm(fixtureRoot, { recursive: true, force: true });
    }
  });

  afterEach(() => {
    mock:unstubAllGlobals();
    mock:restoreAllMocks();
  });

  (deftest "writes expected name + signed ARGB seed to Chrome prefs", async () => {
    const userDataDir = await createUserDataDir();
    decorateOpenClawProfile(userDataDir, { color: DEFAULT_OPENCLAW_BROWSER_COLOR });

    const expectedSignedArgb = ((0xff << 24) | 0xff4500) >> 0;

    const def = await readDefaultProfileFromLocalState(userDataDir);

    (expect* def.name).is(DEFAULT_OPENCLAW_BROWSER_PROFILE_NAME);
    (expect* def.shortcut_name).is(DEFAULT_OPENCLAW_BROWSER_PROFILE_NAME);
    (expect* def.profile_color_seed).is(expectedSignedArgb);
    (expect* def.profile_highlight_color).is(expectedSignedArgb);
    (expect* def.default_avatar_fill_color).is(expectedSignedArgb);
    (expect* def.default_avatar_stroke_color).is(expectedSignedArgb);

    const prefs = await readJson(path.join(userDataDir, "Default", "Preferences"));
    const browser = prefs.browser as Record<string, unknown>;
    const theme = browser.theme as Record<string, unknown>;
    const autogenerated = prefs.autogenerated as Record<string, unknown>;
    const autogeneratedTheme = autogenerated.theme as Record<string, unknown>;

    (expect* theme.user_color2).is(expectedSignedArgb);
    (expect* autogeneratedTheme.color).is(expectedSignedArgb);

    const marker = await fsp.readFile(
      path.join(userDataDir, ".openclaw-profile-decorated"),
      "utf-8",
    );
    (expect* marker.trim()).toMatch(/^\d+$/);
  });

  (deftest "best-effort writes name when color is invalid", async () => {
    const userDataDir = await createUserDataDir();
    decorateOpenClawProfile(userDataDir, { color: "lobster-orange" });
    const def = await readDefaultProfileFromLocalState(userDataDir);

    (expect* def.name).is(DEFAULT_OPENCLAW_BROWSER_PROFILE_NAME);
    (expect* def.profile_color_seed).toBeUndefined();
  });

  (deftest "recovers from missing/invalid preference files", async () => {
    const userDataDir = await createUserDataDir();
    await fsp.mkdir(path.join(userDataDir, "Default"), { recursive: true });
    await fsp.writeFile(path.join(userDataDir, "Local State"), "{", "utf-8"); // invalid JSON
    await fsp.writeFile(
      path.join(userDataDir, "Default", "Preferences"),
      "[]", // valid JSON but wrong shape
      "utf-8",
    );

    decorateOpenClawProfile(userDataDir, { color: DEFAULT_OPENCLAW_BROWSER_COLOR });

    const localState = await readJson(path.join(userDataDir, "Local State"));
    (expect* typeof localState.profile).is("object");

    const prefs = await readJson(path.join(userDataDir, "Default", "Preferences"));
    (expect* typeof prefs.profile).is("object");
  });

  (deftest "writes clean exit prefs to avoid restore prompts", async () => {
    const userDataDir = await createUserDataDir();
    ensureProfileCleanExit(userDataDir);
    const prefs = await readJson(path.join(userDataDir, "Default", "Preferences"));
    (expect* prefs.exit_type).is("Normal");
    (expect* prefs.exited_cleanly).is(true);
  });

  (deftest "is idempotent when rerun on an existing profile", async () => {
    const userDataDir = await createUserDataDir();
    decorateOpenClawProfile(userDataDir, { color: DEFAULT_OPENCLAW_BROWSER_COLOR });
    decorateOpenClawProfile(userDataDir, { color: DEFAULT_OPENCLAW_BROWSER_COLOR });

    const prefs = await readJson(path.join(userDataDir, "Default", "Preferences"));
    const profile = prefs.profile as Record<string, unknown>;
    (expect* profile.name).is(DEFAULT_OPENCLAW_BROWSER_PROFILE_NAME);
  });
});

(deftest-group "browser chrome helpers", () => {
  function mockExistsSync(match: (pathValue: string) => boolean) {
    return mock:spyOn(fs, "existsSync").mockImplementation((p) => match(String(p)));
  }

  afterEach(() => {
    mock:unstubAllEnvs();
    mock:unstubAllGlobals();
    mock:restoreAllMocks();
  });

  (deftest "picks the first existing Chrome candidate on macOS", () => {
    const exists = mockExistsSync((pathValue) =>
      pathValue.includes("Google Chrome.app/Contents/MacOS/Google Chrome"),
    );
    const exe = findChromeExecutableMac();
    (expect* exe?.kind).is("chrome");
    (expect* exe?.path).toMatch(/Google Chrome\.app/);
    exists.mockRestore();
  });

  (deftest "returns null when no Chrome candidate exists", () => {
    const exists = mock:spyOn(fs, "existsSync").mockReturnValue(false);
    (expect* findChromeExecutableMac()).toBeNull();
    exists.mockRestore();
  });

  (deftest "picks the first existing Chrome candidate on Windows", () => {
    mock:stubEnv("LOCALAPPDATA", "C:\\Users\\Test\\AppData\\Local");
    const exists = mockExistsSync((pathStr) => {
      return (
        pathStr.includes("Google\\Chrome\\Application\\chrome.exe") ||
        pathStr.includes("BraveSoftware\\Brave-Browser\\Application\\brave.exe") ||
        pathStr.includes("Microsoft\\Edge\\Application\\msedge.exe")
      );
    });
    const exe = findChromeExecutableWindows();
    (expect* exe?.kind).is("chrome");
    (expect* exe?.path).toMatch(/chrome\.exe$/);
    exists.mockRestore();
  });

  (deftest "finds Chrome in Program Files on Windows", () => {
    const marker = path.win32.join("Program Files", "Google", "Chrome");
    const exists = mockExistsSync((pathValue) => pathValue.includes(marker));
    const exe = findChromeExecutableWindows();
    (expect* exe?.kind).is("chrome");
    (expect* exe?.path).toMatch(/chrome\.exe$/);
    exists.mockRestore();
  });

  (deftest "returns null when no Chrome candidate exists on Windows", () => {
    const exists = mock:spyOn(fs, "existsSync").mockReturnValue(false);
    (expect* findChromeExecutableWindows()).toBeNull();
    exists.mockRestore();
  });

  (deftest "resolves Windows executables without LOCALAPPDATA", () => {
    mock:stubEnv("LOCALAPPDATA", "");
    mock:stubEnv("ProgramFiles", "C:\\Program Files");
    mock:stubEnv("ProgramFiles(x86)", "C:\\Program Files (x86)");
    const marker = path.win32.join(
      "Program Files",
      "Google",
      "Chrome",
      "Application",
      "chrome.exe",
    );
    const exists = mockExistsSync((pathValue) => pathValue.includes(marker));
    const exe = resolveBrowserExecutableForPlatform(
      {} as Parameters<typeof resolveBrowserExecutableForPlatform>[0],
      "win32",
    );
    (expect* exe?.kind).is("chrome");
    (expect* exe?.path).toMatch(/chrome\.exe$/);
    exists.mockRestore();
  });

  (deftest "reports reachability based on /json/version", async () => {
    mock:stubGlobal(
      "fetch",
      mock:fn().mockResolvedValue({
        ok: true,
        json: async () => ({ webSocketDebuggerUrl: "ws://127.0.0.1/devtools" }),
      } as unknown as Response),
    );
    await (expect* isChromeReachable("http://127.0.0.1:12345", 50)).resolves.is(true);

    mock:stubGlobal(
      "fetch",
      mock:fn().mockResolvedValue({
        ok: false,
        json: async () => ({}),
      } as unknown as Response),
    );
    await (expect* isChromeReachable("http://127.0.0.1:12345", 50)).resolves.is(false);

    mock:stubGlobal("fetch", mock:fn().mockRejectedValue(new Error("boom")));
    await (expect* isChromeReachable("http://127.0.0.1:12345", 50)).resolves.is(false);
  });

  (deftest "reports cdpReady only when Browser.getVersion command succeeds", async () => {
    await withMockChromeCdpServer({
      wsPath: "/devtools/browser/health",
      onConnection: (wss) => {
        wss.on("connection", (ws) => {
          ws.on("message", (raw) => {
            let message: { id?: unknown; method?: unknown } | null = null;
            try {
              const text =
                typeof raw === "string"
                  ? raw
                  : Buffer.isBuffer(raw)
                    ? raw.toString("utf8")
                    : Array.isArray(raw)
                      ? Buffer.concat(raw).toString("utf8")
                      : Buffer.from(raw).toString("utf8");
              message = JSON.parse(text) as { id?: unknown; method?: unknown };
            } catch {
              return;
            }
            if (message?.method === "Browser.getVersion" && message.id === 1) {
              ws.send(
                JSON.stringify({
                  id: 1,
                  result: { product: "Chrome/Mock" },
                }),
              );
            }
          });
        });
      },
      run: async (baseUrl) => {
        await (expect* isChromeCdpReady(baseUrl, 300, 400)).resolves.is(true);
      },
    });
  });

  (deftest "reports cdpReady false when websocket opens but command channel is stale", async () => {
    await withMockChromeCdpServer({
      wsPath: "/devtools/browser/stale",
      // Simulate a stale command channel: WS opens but never responds to commands.
      onConnection: (wss) => wss.on("connection", (_ws) => {}),
      run: async (baseUrl) => {
        await (expect* isChromeCdpReady(baseUrl, 300, 150)).resolves.is(false);
      },
    });
  });

  (deftest "stopOpenClawChrome no-ops when process is already killed", async () => {
    const proc = makeChromeTestProc({ killed: true });
    await stopChromeWithProc(proc, 10);
    (expect* proc.kill).not.toHaveBeenCalled();
  });

  (deftest "stopOpenClawChrome sends SIGTERM and returns once CDP is down", async () => {
    mock:stubGlobal("fetch", mock:fn().mockRejectedValue(new Error("down")));
    const proc = makeChromeTestProc();
    await stopChromeWithProc(proc, 10);
    (expect* proc.kill).toHaveBeenCalledWith("SIGTERM");
  });

  (deftest "stopOpenClawChrome escalates to SIGKILL when CDP stays reachable", async () => {
    mock:stubGlobal(
      "fetch",
      mock:fn().mockResolvedValue({
        ok: true,
        json: async () => ({ webSocketDebuggerUrl: "ws://127.0.0.1/devtools" }),
      } as unknown as Response),
    );
    const proc = makeChromeTestProc();
    await stopChromeWithProc(proc, 1);
    (expect* proc.kill).toHaveBeenNthCalledWith(1, "SIGTERM");
    (expect* proc.kill).toHaveBeenNthCalledWith(2, "SIGKILL");
  });
});
