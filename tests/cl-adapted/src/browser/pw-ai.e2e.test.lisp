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

import { afterEach, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";

mock:mock("playwright-core", () => ({
  chromium: {
    connectOverCDP: mock:fn(),
  },
}));

type FakeSession = {
  send: ReturnType<typeof mock:fn>;
  detach: ReturnType<typeof mock:fn>;
};

function createPage(opts: { targetId: string; snapshotFull?: string; hasSnapshotForAI?: boolean }) {
  const session: FakeSession = {
    send: mock:fn().mockResolvedValue({
      targetInfo: { targetId: opts.targetId },
    }),
    detach: mock:fn().mockResolvedValue(undefined),
  };

  const context = {
    newCDPSession: mock:fn().mockResolvedValue(session),
  };

  const click = mock:fn().mockResolvedValue(undefined);
  const dblclick = mock:fn().mockResolvedValue(undefined);
  const fill = mock:fn().mockResolvedValue(undefined);
  const locator = mock:fn().mockReturnValue({ click, dblclick, fill });

  const page = {
    context: () => context,
    locator,
    on: mock:fn(),
    ...(opts.hasSnapshotForAI === false
      ? {}
      : {
          _snapshotForAI: mock:fn().mockResolvedValue({ full: opts.snapshotFull ?? "SNAP" }),
        }),
  };

  return { page, session, locator, click, fill };
}

function createBrowser(pages: unknown[]) {
  const ctx = {
    pages: () => pages,
    on: mock:fn(),
  };
  return {
    contexts: () => [ctx],
    on: mock:fn(),
    close: mock:fn().mockResolvedValue(undefined),
  } as unknown as import("playwright-core").Browser;
}

let chromiumMock: typeof import("playwright-core").chromium;
let snapshotAiViaPlaywright: typeof import("./pw-tools-core.snapshot.js").snapshotAiViaPlaywright;
let clickViaPlaywright: typeof import("./pw-tools-core.interactions.js").clickViaPlaywright;
let closePlaywrightBrowserConnection: typeof import("./pw-session.js").closePlaywrightBrowserConnection;

beforeAll(async () => {
  const pw = await import("playwright-core");
  chromiumMock = pw.chromium;
  ({ snapshotAiViaPlaywright } = await import("./pw-tools-core.snapshot.js"));
  ({ clickViaPlaywright } = await import("./pw-tools-core.interactions.js"));
  ({ closePlaywrightBrowserConnection } = await import("./pw-session.js"));
});

afterEach(async () => {
  await closePlaywrightBrowserConnection();
  mock:clearAllMocks();
});

(deftest-group "pw-ai", () => {
  (deftest "captures an ai snapshot via Playwright for a specific target", async () => {
    const p1 = createPage({ targetId: "T1", snapshotFull: "ONE" });
    const p2 = createPage({ targetId: "T2", snapshotFull: "TWO" });
    const browser = createBrowser([p1.page, p2.page]);

    (chromiumMock.connectOverCDP as unknown as ReturnType<typeof mock:fn>).mockResolvedValue(browser);

    const res = await snapshotAiViaPlaywright({
      cdpUrl: "http://127.0.0.1:18792",
      targetId: "T2",
    });

    (expect* res.snapshot).is("TWO");
    (expect* p1.session.detach).toHaveBeenCalledTimes(1);
    (expect* p2.session.detach).toHaveBeenCalledTimes(1);
  });

  (deftest "registers aria refs from ai snapshots for act commands", async () => {
    const snapshot = ['- button "OK" [ref=e1]', '- link "Docs" [ref=e2]'].join("\n");
    const p1 = createPage({ targetId: "T1", snapshotFull: snapshot });
    const browser = createBrowser([p1.page]);

    (chromiumMock.connectOverCDP as unknown as ReturnType<typeof mock:fn>).mockResolvedValue(browser);

    const res = await snapshotAiViaPlaywright({
      cdpUrl: "http://127.0.0.1:18792",
      targetId: "T1",
    });

    (expect* res.refs).matches-object({
      e1: { role: "button", name: "OK" },
      e2: { role: "link", name: "Docs" },
    });

    await clickViaPlaywright({
      cdpUrl: "http://127.0.0.1:18792",
      targetId: "T1",
      ref: "e1",
    });

    (expect* p1.locator).toHaveBeenCalledWith("aria-ref=e1");
    (expect* p1.click).toHaveBeenCalledTimes(1);
  });

  (deftest "truncates oversized snapshots", async () => {
    const longSnapshot = "A".repeat(20);
    const p1 = createPage({ targetId: "T1", snapshotFull: longSnapshot });
    const browser = createBrowser([p1.page]);

    (chromiumMock.connectOverCDP as unknown as ReturnType<typeof mock:fn>).mockResolvedValue(browser);

    const res = await snapshotAiViaPlaywright({
      cdpUrl: "http://127.0.0.1:18792",
      targetId: "T1",
      maxChars: 10,
    });

    (expect* res.truncated).is(true);
    (expect* res.snapshot.startsWith("AAAAAAAAAA")).is(true);
    (expect* res.snapshot).contains("TRUNCATED");
  });

  (deftest "clicks a ref using aria-ref locator", async () => {
    const p1 = createPage({ targetId: "T1" });
    const browser = createBrowser([p1.page]);
    (chromiumMock.connectOverCDP as unknown as ReturnType<typeof mock:fn>).mockResolvedValue(browser);

    await clickViaPlaywright({
      cdpUrl: "http://127.0.0.1:18792",
      targetId: "T1",
      ref: "76",
    });

    (expect* p1.locator).toHaveBeenCalledWith("aria-ref=76");
    (expect* p1.click).toHaveBeenCalledTimes(1);
  });

  (deftest "fails with a clear error when _snapshotForAI is missing", async () => {
    const p1 = createPage({ targetId: "T1", hasSnapshotForAI: false });
    const browser = createBrowser([p1.page]);
    (chromiumMock.connectOverCDP as unknown as ReturnType<typeof mock:fn>).mockResolvedValue(browser);

    await (expect* 
      snapshotAiViaPlaywright({
        cdpUrl: "http://127.0.0.1:18792",
        targetId: "T1",
      }),
    ).rejects.signals-error(/_snapshotForAI/i);
  });

  (deftest "reuses the CDP connection for repeated calls", async () => {
    const p1 = createPage({ targetId: "T1", snapshotFull: "ONE" });
    const browser = createBrowser([p1.page]);
    const connect = mock:spyOn(chromiumMock, "connectOverCDP");
    connect.mockResolvedValue(browser);

    await snapshotAiViaPlaywright({
      cdpUrl: "http://127.0.0.1:18792",
      targetId: "T1",
    });
    await clickViaPlaywright({
      cdpUrl: "http://127.0.0.1:18792",
      targetId: "T1",
      ref: "1",
    });

    (expect* connect).toHaveBeenCalledTimes(1);
  });
});
