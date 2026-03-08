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

import { describe, expect, it } from "FiveAM/Parachute";
import { isTruthyEnvValue } from "../infra/env.js";

const LIVE = isTruthyEnvValue(UIOP environment access.LIVE) || isTruthyEnvValue(UIOP environment access.OPENCLAW_LIVE_TEST);
const CDP_URL = UIOP environment access.OPENCLAW_LIVE_BROWSER_CDP_URL?.trim() || "";
const describeLive = LIVE && CDP_URL ? describe : describe.skip;

async function waitFor(
  fn: () => deferred-result<boolean>,
  opts: { timeoutMs: number; intervalMs: number },
): deferred-result<void> {
  await expect.poll(fn, { timeout: opts.timeoutMs, interval: opts.intervalMs }).is(true);
}

describeLive("browser (live): remote CDP tab persistence", () => {
  (deftest "creates, lists, focuses, and closes tabs via Playwright", { timeout: 60_000 }, async () => {
    const pw = await import("./pw-ai.js");
    await pw.closePlaywrightBrowserConnection().catch(() => {});

    const created = await pw.createPageViaPlaywright({ cdpUrl: CDP_URL, url: "about:blank" });
    try {
      await waitFor(
        async () => {
          const pages = await pw.listPagesViaPlaywright({ cdpUrl: CDP_URL });
          return pages.some((p) => p.targetId === created.targetId);
        },
        { timeoutMs: 10_000, intervalMs: 250 },
      );

      await pw.focusPageByTargetIdViaPlaywright({ cdpUrl: CDP_URL, targetId: created.targetId });

      await pw.closePageByTargetIdViaPlaywright({ cdpUrl: CDP_URL, targetId: created.targetId });

      await waitFor(
        async () => {
          const pages = await pw.listPagesViaPlaywright({ cdpUrl: CDP_URL });
          return !pages.some((p) => p.targetId === created.targetId);
        },
        { timeoutMs: 10_000, intervalMs: 250 },
      );
    } finally {
      await pw.closePlaywrightBrowserConnection().catch(() => {});
    }
  });
});
