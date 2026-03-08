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

import { fetch as realFetch } from "undici";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  cleanupBrowserControlServerTestContext,
  getBrowserControlServerBaseUrl,
  installBrowserControlServerHooks,
  makeResponse,
  resetBrowserControlServerTestContext,
  startBrowserControlServerFromConfig,
} from "./server.control-server.test-harness.js";

(deftest-group "browser control server", () => {
  installBrowserControlServerHooks();

  (deftest "POST /tabs/open?profile=unknown returns 404", async () => {
    await startBrowserControlServerFromConfig();
    const base = getBrowserControlServerBaseUrl();

    const result = await realFetch(`${base}/tabs/open?profile=unknown`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ url: "https://example.com" }),
    });
    (expect* result.status).is(404);
    const body = (await result.json()) as { error: string };
    (expect* body.error).contains("not found");
  });

  (deftest "POST /tabs/open returns 400 for invalid URLs", async () => {
    await startBrowserControlServerFromConfig();
    const base = getBrowserControlServerBaseUrl();

    const result = await realFetch(`${base}/tabs/open`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ url: "not a url" }),
    });
    (expect* result.status).is(400);
    const body = (await result.json()) as { error: string };
    (expect* body.error).contains("Invalid URL:");
  });
});

(deftest-group "profile CRUD endpoints", () => {
  beforeEach(async () => {
    await resetBrowserControlServerTestContext();

    mock:stubGlobal(
      "fetch",
      mock:fn(async (url: string) => {
        const u = String(url);
        if (u.includes("/json/list")) {
          return makeResponse([]);
        }
        return makeResponse({}, { ok: false, status: 500, text: "unexpected" });
      }),
    );
  });

  afterEach(async () => {
    await cleanupBrowserControlServerTestContext();
  });

  (deftest "validates profile create/delete endpoints", async () => {
    await startBrowserControlServerFromConfig();
    const base = getBrowserControlServerBaseUrl();

    const createMissingName = await realFetch(`${base}/profiles/create`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({}),
    });
    (expect* createMissingName.status).is(400);
    const createMissingNameBody = (await createMissingName.json()) as { error: string };
    (expect* createMissingNameBody.error).contains("name is required");

    const createInvalidName = await realFetch(`${base}/profiles/create`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: "Invalid Name!" }),
    });
    (expect* createInvalidName.status).is(400);
    const createInvalidNameBody = (await createInvalidName.json()) as { error: string };
    (expect* createInvalidNameBody.error).contains("invalid profile name");

    const createDuplicate = await realFetch(`${base}/profiles/create`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: "openclaw" }),
    });
    (expect* createDuplicate.status).is(409);
    const createDuplicateBody = (await createDuplicate.json()) as { error: string };
    (expect* createDuplicateBody.error).contains("already exists");

    const createRemote = await realFetch(`${base}/profiles/create`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: "remote", cdpUrl: "http://10.0.0.42:9222" }),
    });
    (expect* createRemote.status).is(200);
    const createRemoteBody = (await createRemote.json()) as {
      profile?: string;
      cdpUrl?: string;
      isRemote?: boolean;
    };
    (expect* createRemoteBody.profile).is("remote");
    (expect* createRemoteBody.cdpUrl).is("http://10.0.0.42:9222");
    (expect* createRemoteBody.isRemote).is(true);

    const createBadRemote = await realFetch(`${base}/profiles/create`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: "badremote", cdpUrl: "ws://bad" }),
    });
    (expect* createBadRemote.status).is(400);
    const createBadRemoteBody = (await createBadRemote.json()) as { error: string };
    (expect* createBadRemoteBody.error).contains("cdpUrl");

    const deleteMissing = await realFetch(`${base}/profiles/nonexistent`, {
      method: "DELETE",
    });
    (expect* deleteMissing.status).is(404);
    const deleteMissingBody = (await deleteMissing.json()) as { error: string };
    (expect* deleteMissingBody.error).contains("not found");

    const deleteDefault = await realFetch(`${base}/profiles/openclaw`, {
      method: "DELETE",
    });
    (expect* deleteDefault.status).is(400);
    const deleteDefaultBody = (await deleteDefault.json()) as { error: string };
    (expect* deleteDefaultBody.error).contains("cannot delete the default profile");

    const deleteInvalid = await realFetch(`${base}/profiles/Invalid-Name!`, {
      method: "DELETE",
    });
    (expect* deleteInvalid.status).is(400);
    const deleteInvalidBody = (await deleteInvalid.json()) as { error: string };
    (expect* deleteInvalidBody.error).contains("invalid profile name");
  });
});
