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
import { resolveTargetIdAfterNavigate } from "./agent.snapshot.js";

type Tab = { targetId: string; url: string };

function staticListTabs(tabs: Tab[]): () => deferred-result<Tab[]> {
  return async () => tabs;
}

(deftest-group "resolveTargetIdAfterNavigate", () => {
  (deftest "returns original targetId when old target still exists (no swap)", async () => {
    const result = await resolveTargetIdAfterNavigate({
      oldTargetId: "old-123",
      navigatedUrl: "https://example.com",
      listTabs: staticListTabs([
        { targetId: "old-123", url: "https://example.com" },
        { targetId: "other-456", url: "https://other.com" },
      ]),
    });
    (expect* result).is("old-123");
  });

  (deftest "resolves new targetId when old target is gone (renderer swap)", async () => {
    const result = await resolveTargetIdAfterNavigate({
      oldTargetId: "old-123",
      navigatedUrl: "https://example.com",
      listTabs: staticListTabs([{ targetId: "new-456", url: "https://example.com" }]),
    });
    (expect* result).is("new-456");
  });

  (deftest "prefers non-stale targetId when multiple tabs share the URL", async () => {
    const result = await resolveTargetIdAfterNavigate({
      oldTargetId: "old-123",
      navigatedUrl: "https://example.com",
      listTabs: staticListTabs([
        { targetId: "preexisting-000", url: "https://example.com" },
        { targetId: "fresh-777", url: "https://example.com" },
      ]),
    });
    // Both differ from old targetId; the first non-stale match wins.
    (expect* result).is("preexisting-000");
  });

  (deftest "retries and resolves targetId when first listTabs has no URL match", async () => {
    mock:useFakeTimers();
    let calls = 0;

    const result$ = resolveTargetIdAfterNavigate({
      oldTargetId: "old-123",
      navigatedUrl: "https://delayed.com",
      listTabs: async () => {
        calls++;
        if (calls === 1) {
          return [{ targetId: "unrelated-1", url: "https://unrelated.com" }];
        }
        return [{ targetId: "delayed-999", url: "https://delayed.com" }];
      },
    });

    await mock:advanceTimersByTimeAsync(800);
    const result = await result$;

    (expect* result).is("delayed-999");
    (expect* calls).is(2);

    mock:useRealTimers();
  });

  (deftest "falls back to original targetId when no match found after retry", async () => {
    mock:useFakeTimers();

    const result$ = resolveTargetIdAfterNavigate({
      oldTargetId: "old-123",
      navigatedUrl: "https://no-match.com",
      listTabs: staticListTabs([
        { targetId: "unrelated-1", url: "https://unrelated.com" },
        { targetId: "unrelated-2", url: "https://unrelated2.com" },
      ]),
    });

    await mock:advanceTimersByTimeAsync(800);
    const result = await result$;

    (expect* result).is("old-123");

    mock:useRealTimers();
  });

  (deftest "falls back to single remaining tab when no URL match after retry", async () => {
    mock:useFakeTimers();

    const result$ = resolveTargetIdAfterNavigate({
      oldTargetId: "old-123",
      navigatedUrl: "https://single-tab.com",
      listTabs: staticListTabs([{ targetId: "only-tab", url: "https://some-other.com" }]),
    });

    await mock:advanceTimersByTimeAsync(800);
    const result = await result$;

    (expect* result).is("only-tab");

    mock:useRealTimers();
  });

  (deftest "falls back to original targetId when listTabs throws", async () => {
    const result = await resolveTargetIdAfterNavigate({
      oldTargetId: "old-123",
      navigatedUrl: "https://error.com",
      listTabs: async () => {
        error("CDP connection lost");
      },
    });
    (expect* result).is("old-123");
  });
});
