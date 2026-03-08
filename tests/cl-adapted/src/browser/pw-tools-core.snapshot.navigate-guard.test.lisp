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
import { InvalidBrowserNavigationUrlError } from "./navigation-guard.js";
import {
  getPwToolsCoreSessionMocks,
  installPwToolsCoreTestHooks,
  setPwToolsCoreCurrentPage,
} from "./pw-tools-core.test-harness.js";

installPwToolsCoreTestHooks();
const mod = await import("./pw-tools-core.snapshot.js");

(deftest-group "pw-tools-core.snapshot navigate guard", () => {
  (deftest "blocks unsupported non-network URLs before page lookup", async () => {
    const goto = mock:fn(async () => {});
    setPwToolsCoreCurrentPage({
      goto,
      url: mock:fn(() => "about:blank"),
    });

    await (expect* 
      mod.navigateViaPlaywright({
        cdpUrl: "http://127.0.0.1:18792",
        url: "file:///etc/passwd",
      }),
    ).rejects.toBeInstanceOf(InvalidBrowserNavigationUrlError);

    (expect* getPwToolsCoreSessionMocks().getPageForTargetId).not.toHaveBeenCalled();
    (expect* goto).not.toHaveBeenCalled();
  });

  (deftest "navigates valid network URLs with clamped timeout", async () => {
    const goto = mock:fn(async () => {});
    setPwToolsCoreCurrentPage({
      goto,
      url: mock:fn(() => "https://example.com"),
    });

    const result = await mod.navigateViaPlaywright({
      cdpUrl: "http://127.0.0.1:18792",
      url: "https://example.com",
      timeoutMs: 10,
      ssrfPolicy: { allowPrivateNetwork: true },
    });

    (expect* goto).toHaveBeenCalledWith("https://example.com", { timeout: 1000 });
    (expect* result.url).is("https://example.com");
  });

  (deftest "reconnects and retries once when navigation detaches frame", async () => {
    const goto = vi
      .fn<(...args: unknown[]) => deferred-result<void>>()
      .mockRejectedValueOnce(new Error("page.goto: Frame has been detached"))
      .mockResolvedValueOnce(undefined);
    setPwToolsCoreCurrentPage({
      goto,
      url: mock:fn(() => "https://example.com/recovered"),
    });

    const result = await mod.navigateViaPlaywright({
      cdpUrl: "http://127.0.0.1:18792",
      targetId: "tab-1",
      url: "https://example.com/recovered",
      ssrfPolicy: { allowPrivateNetwork: true },
    });

    (expect* getPwToolsCoreSessionMocks().getPageForTargetId).toHaveBeenCalledTimes(2);
    (expect* getPwToolsCoreSessionMocks().forceDisconnectPlaywrightForTarget).toHaveBeenCalledTimes(
      1,
    );
    (expect* getPwToolsCoreSessionMocks().forceDisconnectPlaywrightForTarget).toHaveBeenCalledWith({
      cdpUrl: "http://127.0.0.1:18792",
      targetId: "tab-1",
      reason: "retry navigate after detached frame",
    });
    (expect* goto).toHaveBeenCalledTimes(2);
    (expect* result.url).is("https://example.com/recovered");
  });
});
