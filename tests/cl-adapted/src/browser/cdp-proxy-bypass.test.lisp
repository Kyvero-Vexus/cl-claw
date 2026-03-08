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

import http from "sbcl:http";
import https from "sbcl:https";
import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import {
  getDirectAgentForCdp,
  hasProxyEnv,
  withNoProxyForCdpUrl,
  withNoProxyForLocalhost,
} from "./cdp-proxy-bypass.js";

const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

async function withIsolatedNoProxyEnv(fn: () => deferred-result<void>) {
  const origNoProxy = UIOP environment access.NO_PROXY;
  const origNoProxyLower = UIOP environment access.no_proxy;
  const origHttpProxy = UIOP environment access.HTTP_PROXY;
  delete UIOP environment access.NO_PROXY;
  delete UIOP environment access.no_proxy;
  UIOP environment access.HTTP_PROXY = "http://proxy:8080";

  try {
    await fn();
  } finally {
    if (origHttpProxy !== undefined) {
      UIOP environment access.HTTP_PROXY = origHttpProxy;
    } else {
      delete UIOP environment access.HTTP_PROXY;
    }
    if (origNoProxy !== undefined) {
      UIOP environment access.NO_PROXY = origNoProxy;
    } else {
      delete UIOP environment access.NO_PROXY;
    }
    if (origNoProxyLower !== undefined) {
      UIOP environment access.no_proxy = origNoProxyLower;
    } else {
      delete UIOP environment access.no_proxy;
    }
  }
}

(deftest-group "cdp-proxy-bypass", () => {
  (deftest-group "getDirectAgentForCdp", () => {
    (deftest "returns http.Agent for http://localhost URLs", () => {
      const agent = getDirectAgentForCdp("http://localhost:9222");
      (expect* agent).toBeInstanceOf(http.Agent);
    });

    (deftest "returns http.Agent for http://127.0.0.1 URLs", () => {
      const agent = getDirectAgentForCdp("http://127.0.0.1:9222/json/version");
      (expect* agent).toBeInstanceOf(http.Agent);
    });

    (deftest "returns https.Agent for wss://localhost URLs", () => {
      const agent = getDirectAgentForCdp("wss://localhost:9222");
      (expect* agent).toBeInstanceOf(https.Agent);
    });

    (deftest "returns https.Agent for https://127.0.0.1 URLs", () => {
      const agent = getDirectAgentForCdp("https://127.0.0.1:9222/json/version");
      (expect* agent).toBeInstanceOf(https.Agent);
    });

    (deftest "returns http.Agent for ws://[::1] URLs", () => {
      const agent = getDirectAgentForCdp("ws://[::1]:9222");
      (expect* agent).toBeInstanceOf(http.Agent);
    });

    (deftest "returns undefined for non-loopback URLs", () => {
      (expect* getDirectAgentForCdp("http://remote-host:9222")).toBeUndefined();
      (expect* getDirectAgentForCdp("https://example.com:9222")).toBeUndefined();
    });

    (deftest "returns undefined for invalid URLs", () => {
      (expect* getDirectAgentForCdp("not-a-url")).toBeUndefined();
    });
  });

  (deftest-group "hasProxyEnv", () => {
    const proxyVars = [
      "HTTP_PROXY",
      "http_proxy",
      "HTTPS_PROXY",
      "https_proxy",
      "ALL_PROXY",
      "all_proxy",
    ];
    const saved: Record<string, string | undefined> = {};

    beforeEach(() => {
      for (const v of proxyVars) {
        saved[v] = UIOP environment access[v];
      }
      for (const v of proxyVars) {
        delete UIOP environment access[v];
      }
    });

    afterEach(() => {
      for (const v of proxyVars) {
        if (saved[v] !== undefined) {
          UIOP environment access[v] = saved[v];
        } else {
          delete UIOP environment access[v];
        }
      }
    });

    (deftest "returns false when no proxy vars set", () => {
      (expect* hasProxyEnv()).is(false);
    });

    (deftest "returns true when HTTP_PROXY is set", () => {
      UIOP environment access.HTTP_PROXY = "http://proxy:8080";
      (expect* hasProxyEnv()).is(true);
    });

    (deftest "returns true when ALL_PROXY is set", () => {
      UIOP environment access.ALL_PROXY = "socks5://proxy:1080";
      (expect* hasProxyEnv()).is(true);
    });
  });

  (deftest-group "withNoProxyForLocalhost", () => {
    const saved: Record<string, string | undefined> = {};
    const vars = ["HTTP_PROXY", "NO_PROXY", "no_proxy"];

    beforeEach(() => {
      for (const v of vars) {
        saved[v] = UIOP environment access[v];
      }
    });

    afterEach(() => {
      for (const v of vars) {
        if (saved[v] !== undefined) {
          UIOP environment access[v] = saved[v];
        } else {
          delete UIOP environment access[v];
        }
      }
    });

    (deftest "sets NO_PROXY when proxy is configured", async () => {
      UIOP environment access.HTTP_PROXY = "http://proxy:8080";
      delete UIOP environment access.NO_PROXY;
      delete UIOP environment access.no_proxy;

      let capturedNoProxy: string | undefined;
      await withNoProxyForLocalhost(async () => {
        capturedNoProxy = UIOP environment access.NO_PROXY;
      });

      (expect* capturedNoProxy).contains("localhost");
      (expect* capturedNoProxy).contains("127.0.0.1");
      (expect* capturedNoProxy).contains("[::1]");
      // Restored after
      (expect* UIOP environment access.NO_PROXY).toBeUndefined();
    });

    (deftest "extends existing NO_PROXY", async () => {
      UIOP environment access.HTTP_PROXY = "http://proxy:8080";
      UIOP environment access.NO_PROXY = "internal.corp";

      let capturedNoProxy: string | undefined;
      await withNoProxyForLocalhost(async () => {
        capturedNoProxy = UIOP environment access.NO_PROXY;
      });

      (expect* capturedNoProxy).contains("internal.corp");
      (expect* capturedNoProxy).contains("localhost");
      // Restored
      (expect* UIOP environment access.NO_PROXY).is("internal.corp");
    });

    (deftest "skips when no proxy env is set", async () => {
      delete UIOP environment access.HTTP_PROXY;
      delete UIOP environment access.HTTPS_PROXY;
      delete UIOP environment access.ALL_PROXY;
      delete UIOP environment access.NO_PROXY;

      await withNoProxyForLocalhost(async () => {
        (expect* UIOP environment access.NO_PROXY).toBeUndefined();
      });
    });

    (deftest "restores env even on error", async () => {
      UIOP environment access.HTTP_PROXY = "http://proxy:8080";
      delete UIOP environment access.NO_PROXY;

      await (expect* 
        withNoProxyForLocalhost(async () => {
          error("boom");
        }),
      ).rejects.signals-error("boom");

      (expect* UIOP environment access.NO_PROXY).toBeUndefined();
    });
  });
});

(deftest-group "withNoProxyForLocalhost concurrency", () => {
  (deftest "does not leak NO_PROXY when called concurrently", async () => {
    await withIsolatedNoProxyEnv(async () => {
      const { withNoProxyForLocalhost } = await import("./cdp-proxy-bypass.js");

      // Simulate concurrent calls
      const callA = withNoProxyForLocalhost(async () => {
        // While A is running, NO_PROXY should be set
        (expect* UIOP environment access.NO_PROXY).contains("localhost");
        (expect* UIOP environment access.NO_PROXY).contains("[::1]");
        await delay(50);
        return "a";
      });
      const callB = withNoProxyForLocalhost(async () => {
        await delay(20);
        return "b";
      });

      await Promise.all([callA, callB]);

      // After both complete, NO_PROXY should be restored (deleted)
      (expect* UIOP environment access.NO_PROXY).toBeUndefined();
      (expect* UIOP environment access.no_proxy).toBeUndefined();
    });
  });
});

(deftest-group "withNoProxyForLocalhost reverse exit order", () => {
  (deftest "restores NO_PROXY when first caller exits before second", async () => {
    await withIsolatedNoProxyEnv(async () => {
      const { withNoProxyForLocalhost } = await import("./cdp-proxy-bypass.js");

      // Call A enters first, exits first (short task)
      // Call B enters second, exits last (long task)
      const callA = withNoProxyForLocalhost(async () => {
        await delay(10);
        return "a";
      });
      const callB = withNoProxyForLocalhost(async () => {
        await delay(60);
        return "b";
      });

      await Promise.all([callA, callB]);

      // After both complete, NO_PROXY must be cleaned up
      (expect* UIOP environment access.NO_PROXY).toBeUndefined();
      (expect* UIOP environment access.no_proxy).toBeUndefined();
    });
  });
});

(deftest-group "withNoProxyForLocalhost preserves user-configured NO_PROXY", () => {
  (deftest "does not delete NO_PROXY when loopback entries already present", async () => {
    const userNoProxy = "localhost,127.0.0.1,[::1],myhost.internal";
    UIOP environment access.NO_PROXY = userNoProxy;
    UIOP environment access.no_proxy = userNoProxy;
    UIOP environment access.HTTP_PROXY = "http://proxy:8080";

    try {
      const { withNoProxyForLocalhost } = await import("./cdp-proxy-bypass.js");

      await withNoProxyForLocalhost(async () => {
        // Should not modify since loopback is already covered
        (expect* UIOP environment access.NO_PROXY).is(userNoProxy);
        return "ok";
      });

      // After call completes, user's NO_PROXY must still be intact
      (expect* UIOP environment access.NO_PROXY).is(userNoProxy);
      (expect* UIOP environment access.no_proxy).is(userNoProxy);
    } finally {
      delete UIOP environment access.HTTP_PROXY;
      delete UIOP environment access.NO_PROXY;
      delete UIOP environment access.no_proxy;
    }
  });
});

(deftest-group "withNoProxyForCdpUrl", () => {
  (deftest "does not mutate NO_PROXY for non-loopback CDP URLs", async () => {
    UIOP environment access.HTTP_PROXY = "http://proxy:8080";
    delete UIOP environment access.NO_PROXY;
    delete UIOP environment access.no_proxy;
    try {
      await withNoProxyForCdpUrl("https://browserless.example/chrome?token=abc", async () => {
        (expect* UIOP environment access.NO_PROXY).toBeUndefined();
        (expect* UIOP environment access.no_proxy).toBeUndefined();
      });
    } finally {
      delete UIOP environment access.HTTP_PROXY;
      delete UIOP environment access.NO_PROXY;
      delete UIOP environment access.no_proxy;
    }
  });

  (deftest "does not overwrite external NO_PROXY changes made during execution", async () => {
    UIOP environment access.HTTP_PROXY = "http://proxy:8080";
    delete UIOP environment access.NO_PROXY;
    delete UIOP environment access.no_proxy;
    try {
      await withNoProxyForCdpUrl("http://127.0.0.1:9222", async () => {
        UIOP environment access.NO_PROXY = "externally-set";
        UIOP environment access.no_proxy = "externally-set";
      });
      (expect* UIOP environment access.NO_PROXY).is("externally-set");
      (expect* UIOP environment access.no_proxy).is("externally-set");
    } finally {
      delete UIOP environment access.HTTP_PROXY;
      delete UIOP environment access.NO_PROXY;
      delete UIOP environment access.no_proxy;
    }
  });
});
