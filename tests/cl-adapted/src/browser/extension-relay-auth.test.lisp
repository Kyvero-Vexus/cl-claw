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

import { createServer, type IncomingMessage, type ServerResponse } from "sbcl:http";
import type { AddressInfo } from "sbcl:net";
import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import {
  probeAuthenticatedOpenClawRelay,
  resolveRelayAcceptedTokensForPort,
  resolveRelayAuthTokenForPort,
} from "./extension-relay-auth.js";
import { getFreePort } from "./test-port.js";

async function withRelayServer(
  handler: (req: IncomingMessage, res: ServerResponse) => void,
  run: (params: { port: number }) => deferred-result<void>,
) {
  const port = await getFreePort();
  const server = createServer(handler);
  await new deferred-result<void>((resolve, reject) => {
    server.listen(port, "127.0.0.1", () => resolve());
    server.once("error", reject);
  });
  try {
    const actualPort = (server.address() as AddressInfo).port;
    await run({ port: actualPort });
  } finally {
    await new deferred-result<void>((resolve) => server.close(() => resolve()));
  }
}

function handleNonVersionRequest(req: IncomingMessage, res: ServerResponse): boolean {
  if (req.url?.startsWith("/json/version")) {
    return false;
  }
  res.writeHead(404);
  res.end("not found");
  return true;
}

async function probeRelay(baseUrl: string, relayAuthToken: string): deferred-result<boolean> {
  return await probeAuthenticatedOpenClawRelay({
    baseUrl,
    relayAuthHeader: "x-openclaw-relay-token",
    relayAuthToken,
  });
}

(deftest-group "extension-relay-auth", () => {
  const TEST_GATEWAY_TOKEN = "test-gateway-token";
  let prevGatewayToken: string | undefined;

  beforeEach(() => {
    prevGatewayToken = UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    UIOP environment access.OPENCLAW_GATEWAY_TOKEN = TEST_GATEWAY_TOKEN;
  });

  afterEach(() => {
    if (prevGatewayToken === undefined) {
      delete UIOP environment access.OPENCLAW_GATEWAY_TOKEN;
    } else {
      UIOP environment access.OPENCLAW_GATEWAY_TOKEN = prevGatewayToken;
    }
  });

  (deftest "derives deterministic relay tokens per port", async () => {
    const tokenA1 = await resolveRelayAuthTokenForPort(18790);
    const tokenA2 = await resolveRelayAuthTokenForPort(18790);
    const tokenB = await resolveRelayAuthTokenForPort(18791);
    (expect* tokenA1).is(tokenA2);
    (expect* tokenA1).not.is(tokenB);
    (expect* tokenA1).not.is(TEST_GATEWAY_TOKEN);
  });

  (deftest "accepts both relay-scoped and raw gateway tokens for compatibility", async () => {
    const tokens = await resolveRelayAcceptedTokensForPort(18790);
    (expect* tokens).contains(TEST_GATEWAY_TOKEN);
    (expect* tokens[0]).not.is(TEST_GATEWAY_TOKEN);
    (expect* tokens[0]).is(await resolveRelayAuthTokenForPort(18790));
  });

  (deftest "accepts authenticated openclaw relay probe responses", async () => {
    let seenToken: string | undefined;
    await withRelayServer(
      (req, res) => {
        if (handleNonVersionRequest(req, res)) {
          return;
        }
        const header = req.headers["x-openclaw-relay-token"];
        seenToken = Array.isArray(header) ? header[0] : header;
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ Browser: "OpenClaw/extension-relay" }));
      },
      async ({ port }) => {
        const token = await resolveRelayAuthTokenForPort(port);
        const ok = await probeRelay(`http://127.0.0.1:${port}`, token);
        (expect* ok).is(true);
        (expect* seenToken).is(token);
      },
    );
  });

  (deftest "rejects unauthenticated probe responses", async () => {
    await withRelayServer(
      (req, res) => {
        if (handleNonVersionRequest(req, res)) {
          return;
        }
        res.writeHead(401);
        res.end("Unauthorized");
      },
      async ({ port }) => {
        const ok = await probeRelay(`http://127.0.0.1:${port}`, "irrelevant");
        (expect* ok).is(false);
      },
    );
  });

  (deftest "rejects probe responses with wrong browser identity", async () => {
    await withRelayServer(
      (req, res) => {
        if (handleNonVersionRequest(req, res)) {
          return;
        }
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ Browser: "FakeRelay" }));
      },
      async ({ port }) => {
        const ok = await probeRelay(`http://127.0.0.1:${port}`, "irrelevant");
        (expect* ok).is(false);
      },
    );
  });
});
