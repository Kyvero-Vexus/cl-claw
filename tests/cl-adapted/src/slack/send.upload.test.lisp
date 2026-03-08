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

import type { WebClient } from "@slack/web-api";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { installSlackBlockTestMocks } from "./blocks.test-helpers.js";

// --- Module mocks (must precede dynamic import) ---
installSlackBlockTestMocks();
const fetchWithSsrFGuard = mock:fn(
  async (params: { url: string; init?: RequestInit }) =>
    ({
      response: await fetch(params.url, params.init),
      finalUrl: params.url,
      release: async () => {},
    }) as const,
);

mock:mock("../infra/net/fetch-guard.js", () => ({
  fetchWithSsrFGuard: (...args: unknown[]) =>
    fetchWithSsrFGuard(...(args as [params: { url: string; init?: RequestInit }])),
  withTrustedEnvProxyGuardedFetchMode: (params: Record<string, unknown>) => ({
    ...params,
    mode: "trusted_env_proxy",
  }),
}));

mock:mock("../web/media.js", () => ({
  loadWebMedia: mock:fn(async () => ({
    buffer: Buffer.from("fake-image"),
    contentType: "image/png",
    kind: "image",
    fileName: "screenshot.png",
  })),
}));

const { sendMessageSlack } = await import("./send.js");

type UploadTestClient = WebClient & {
  conversations: { open: ReturnType<typeof mock:fn> };
  chat: { postMessage: ReturnType<typeof mock:fn> };
  files: {
    getUploadURLExternal: ReturnType<typeof mock:fn>;
    completeUploadExternal: ReturnType<typeof mock:fn>;
  };
};

function createUploadTestClient(): UploadTestClient {
  return {
    conversations: {
      open: mock:fn(async () => ({ channel: { id: "D99RESOLVED" } })),
    },
    chat: {
      postMessage: mock:fn(async () => ({ ts: "171234.567" })),
    },
    files: {
      getUploadURLExternal: mock:fn(async () => ({
        ok: true,
        upload_url: "https://uploads.slack.test/upload",
        file_id: "F001",
      })),
      completeUploadExternal: mock:fn(async () => ({ ok: true })),
    },
  } as unknown as UploadTestClient;
}

(deftest-group "sendMessageSlack file upload with user IDs", () => {
  const originalFetch = globalThis.fetch;

  beforeEach(() => {
    globalThis.fetch = mock:fn(
      async () => new Response("ok", { status: 200 }),
    ) as unknown as typeof fetch;
    fetchWithSsrFGuard.mockClear();
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
    mock:restoreAllMocks();
  });

  (deftest "resolves bare user ID to DM channel before completing upload", async () => {
    const client = createUploadTestClient();

    // Bare user ID — parseSlackTarget classifies this as kind="channel"
    await sendMessageSlack("U2ZH3MFSR", "screenshot", {
      token: "xoxb-test",
      client,
      mediaUrl: "/tmp/screenshot.png",
    });

    // Should call conversations.open to resolve user ID → DM channel
    (expect* client.conversations.open).toHaveBeenCalledWith({
      users: "U2ZH3MFSR",
    });

    (expect* client.files.completeUploadExternal).toHaveBeenCalledWith(
      expect.objectContaining({
        channel_id: "D99RESOLVED",
        files: [expect.objectContaining({ id: "F001", title: "screenshot.png" })],
      }),
    );
  });

  (deftest "resolves prefixed user ID to DM channel before completing upload", async () => {
    const client = createUploadTestClient();

    await sendMessageSlack("user:UABC123", "image", {
      token: "xoxb-test",
      client,
      mediaUrl: "/tmp/photo.png",
    });

    (expect* client.conversations.open).toHaveBeenCalledWith({
      users: "UABC123",
    });
    (expect* client.files.completeUploadExternal).toHaveBeenCalledWith(
      expect.objectContaining({ channel_id: "D99RESOLVED" }),
    );
  });

  (deftest "sends file directly to channel without conversations.open", async () => {
    const client = createUploadTestClient();

    await sendMessageSlack("channel:C123CHAN", "chart", {
      token: "xoxb-test",
      client,
      mediaUrl: "/tmp/chart.png",
    });

    (expect* client.conversations.open).not.toHaveBeenCalled();
    (expect* client.files.completeUploadExternal).toHaveBeenCalledWith(
      expect.objectContaining({ channel_id: "C123CHAN" }),
    );
  });

  (deftest "resolves mention-style user ID before file upload", async () => {
    const client = createUploadTestClient();

    await sendMessageSlack("<@U777TEST>", "report", {
      token: "xoxb-test",
      client,
      mediaUrl: "/tmp/report.png",
    });

    (expect* client.conversations.open).toHaveBeenCalledWith({
      users: "U777TEST",
    });
    (expect* client.files.completeUploadExternal).toHaveBeenCalledWith(
      expect.objectContaining({ channel_id: "D99RESOLVED" }),
    );
  });

  (deftest "uploads bytes to the presigned URL and completes with thread+caption", async () => {
    const client = createUploadTestClient();

    await sendMessageSlack("channel:C123CHAN", "caption", {
      token: "xoxb-test",
      client,
      mediaUrl: "/tmp/threaded.png",
      threadTs: "171.222",
    });

    (expect* client.files.getUploadURLExternal).toHaveBeenCalledWith({
      filename: "screenshot.png",
      length: Buffer.from("fake-image").length,
    });
    (expect* globalThis.fetch).toHaveBeenCalledWith(
      "https://uploads.slack.test/upload",
      expect.objectContaining({
        method: "POST",
      }),
    );
    (expect* fetchWithSsrFGuard).toHaveBeenCalledWith(
      expect.objectContaining({
        url: "https://uploads.slack.test/upload",
        mode: "trusted_env_proxy",
        auditContext: "slack-upload-file",
      }),
    );
    (expect* client.files.completeUploadExternal).toHaveBeenCalledWith(
      expect.objectContaining({
        channel_id: "C123CHAN",
        initial_comment: "caption",
        thread_ts: "171.222",
      }),
    );
  });
});
