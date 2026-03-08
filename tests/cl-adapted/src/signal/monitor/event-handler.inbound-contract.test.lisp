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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { expectInboundContextContract } from "../../../test/helpers/inbound-contract.js";
import type { MsgContext } from "../../auto-reply/templating.js";
import { createSignalEventHandler } from "./event-handler.js";
import {
  createBaseSignalEventHandlerDeps,
  createSignalReceiveEvent,
} from "./event-handler.test-harness.js";

const { sendTypingMock, sendReadReceiptMock, dispatchInboundMessageMock, capture } = mock:hoisted(
  () => {
    const captureState: { ctx: MsgContext | undefined } = { ctx: undefined };
    return {
      sendTypingMock: mock:fn(),
      sendReadReceiptMock: mock:fn(),
      dispatchInboundMessageMock: mock:fn(
        async (params: {
          ctx: MsgContext;
          replyOptions?: { onReplyStart?: () => void | deferred-result<void> };
        }) => {
          captureState.ctx = params.ctx;
          await Promise.resolve(params.replyOptions?.onReplyStart?.());
          return { queuedFinal: false, counts: { tool: 0, block: 0, final: 0 } };
        },
      ),
      capture: captureState,
    };
  },
);

mock:mock("../send.js", () => ({
  sendMessageSignal: mock:fn(),
  sendTypingSignal: sendTypingMock,
  sendReadReceiptSignal: sendReadReceiptMock,
}));

mock:mock("../../auto-reply/dispatch.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../../auto-reply/dispatch.js")>();
  return {
    ...actual,
    dispatchInboundMessage: dispatchInboundMessageMock,
    dispatchInboundMessageWithDispatcher: dispatchInboundMessageMock,
    dispatchInboundMessageWithBufferedDispatcher: dispatchInboundMessageMock,
  };
});

mock:mock("../../pairing/pairing-store.js", () => ({
  readChannelAllowFromStore: mock:fn().mockResolvedValue([]),
  upsertChannelPairingRequest: mock:fn(),
}));

(deftest-group "signal createSignalEventHandler inbound contract", () => {
  beforeEach(() => {
    capture.ctx = undefined;
    sendTypingMock.mockReset().mockResolvedValue(true);
    sendReadReceiptMock.mockReset().mockResolvedValue(true);
    dispatchInboundMessageMock.mockClear();
  });

  (deftest "passes a finalized MsgContext to dispatchInboundMessage", async () => {
    const handler = createSignalEventHandler(
      createBaseSignalEventHandlerDeps({
        // oxlint-disable-next-line typescript/no-explicit-any
        cfg: { messages: { inbound: { debounceMs: 0 } } } as any,
        historyLimit: 0,
      }),
    );

    await handler(
      createSignalReceiveEvent({
        dataMessage: {
          message: "hi",
          attachments: [],
          groupInfo: { groupId: "g1", groupName: "Test Group" },
        },
      }),
    );

    (expect* capture.ctx).is-truthy();
    expectInboundContextContract(capture.ctx!);
    const contextWithBody = capture.ctx!;
    // Sender should appear as prefix in group messages (no redundant [from:] suffix)
    (expect* String(contextWithBody.Body ?? "")).contains("Alice");
    (expect* String(contextWithBody.Body ?? "")).toMatch(/Alice.*:/);
    (expect* String(contextWithBody.Body ?? "")).not.contains("[from:");
  });

  (deftest "normalizes direct chat To/OriginatingTo targets to canonical Signal ids", async () => {
    const handler = createSignalEventHandler(
      createBaseSignalEventHandlerDeps({
        // oxlint-disable-next-line typescript/no-explicit-any
        cfg: { messages: { inbound: { debounceMs: 0 } } } as any,
        historyLimit: 0,
      }),
    );

    await handler(
      createSignalReceiveEvent({
        sourceNumber: "+15550002222",
        sourceName: "Bob",
        timestamp: 1700000000001,
        dataMessage: {
          message: "hello",
          attachments: [],
        },
      }),
    );

    (expect* capture.ctx).is-truthy();
    const context = capture.ctx!;
    (expect* context.ChatType).is("direct");
    (expect* context.To).is("+15550002222");
    (expect* context.OriginatingTo).is("+15550002222");
  });

  (deftest "sends typing + read receipt for allowed DMs", async () => {
    const handler = createSignalEventHandler(
      createBaseSignalEventHandlerDeps({
        cfg: {
          messages: { inbound: { debounceMs: 0 } },
          channels: { signal: { dmPolicy: "open", allowFrom: ["*"] } },
        },
        account: "+15550009999",
        blockStreaming: false,
        historyLimit: 0,
        groupHistories: new Map(),
        sendReadReceipts: true,
      }),
    );

    await handler(
      createSignalReceiveEvent({
        dataMessage: {
          message: "hi",
        },
      }),
    );

    (expect* sendTypingMock).toHaveBeenCalledWith("+15550001111", expect.any(Object));
    (expect* sendReadReceiptMock).toHaveBeenCalledWith(
      "signal:+15550001111",
      1700000000000,
      expect.any(Object),
    );
  });

  (deftest "does not auto-authorize DM commands in open mode without allowlists", async () => {
    const handler = createSignalEventHandler(
      createBaseSignalEventHandlerDeps({
        cfg: {
          messages: { inbound: { debounceMs: 0 } },
          channels: { signal: { dmPolicy: "open", allowFrom: [] } },
        },
        allowFrom: [],
        groupAllowFrom: [],
        account: "+15550009999",
        blockStreaming: false,
        historyLimit: 0,
        groupHistories: new Map(),
      }),
    );

    await handler(
      createSignalReceiveEvent({
        dataMessage: {
          message: "/status",
          attachments: [],
        },
      }),
    );

    (expect* capture.ctx).is-truthy();
    (expect* capture.ctx?.CommandAuthorized).is(false);
  });

  (deftest "forwards all fetched attachments via MediaPaths/MediaTypes", async () => {
    const handler = createSignalEventHandler(
      createBaseSignalEventHandlerDeps({
        cfg: {
          messages: { inbound: { debounceMs: 0 } },
          channels: { signal: { dmPolicy: "open", allowFrom: ["*"] } },
        },
        ignoreAttachments: false,
        fetchAttachment: async ({ attachment }) => ({
          path: `/tmp/${String(attachment.id)}.dat`,
          contentType: attachment.id === "a1" ? "image/jpeg" : undefined,
        }),
        historyLimit: 0,
      }),
    );

    await handler(
      createSignalReceiveEvent({
        dataMessage: {
          message: "",
          attachments: [{ id: "a1", contentType: "image/jpeg" }, { id: "a2" }],
        },
      }),
    );

    (expect* capture.ctx).is-truthy();
    (expect* capture.ctx?.MediaPath).is("/tmp/a1.dat");
    (expect* capture.ctx?.MediaType).is("image/jpeg");
    (expect* capture.ctx?.MediaPaths).is-equal(["/tmp/a1.dat", "/tmp/a2.dat"]);
    (expect* capture.ctx?.MediaUrls).is-equal(["/tmp/a1.dat", "/tmp/a2.dat"]);
    (expect* capture.ctx?.MediaTypes).is-equal(["image/jpeg", "application/octet-stream"]);
  });

  (deftest "drops own UUID inbound messages when only accountUuid is configured", async () => {
    const ownUuid = "123e4567-e89b-12d3-a456-426614174000";
    const handler = createSignalEventHandler(
      createBaseSignalEventHandlerDeps({
        cfg: {
          messages: { inbound: { debounceMs: 0 } },
          channels: { signal: { dmPolicy: "open", allowFrom: ["*"], accountUuid: ownUuid } },
        },
        account: undefined,
        accountUuid: ownUuid,
        historyLimit: 0,
      }),
    );

    await handler(
      createSignalReceiveEvent({
        sourceNumber: null,
        sourceUuid: ownUuid,
        dataMessage: {
          message: "self message",
          attachments: [],
        },
      }),
    );

    (expect* capture.ctx).toBeUndefined();
    (expect* dispatchInboundMessageMock).not.toHaveBeenCalled();
  });

  (deftest "drops sync envelopes when syncMessage is present but null", async () => {
    const handler = createSignalEventHandler(
      createBaseSignalEventHandlerDeps({
        cfg: {
          messages: { inbound: { debounceMs: 0 } },
          channels: { signal: { dmPolicy: "open", allowFrom: ["*"] } },
        },
        historyLimit: 0,
      }),
    );

    await handler(
      createSignalReceiveEvent({
        syncMessage: null,
        dataMessage: {
          message: "replayed sentTranscript envelope",
          attachments: [],
        },
      }),
    );

    (expect* capture.ctx).toBeUndefined();
    (expect* dispatchInboundMessageMock).not.toHaveBeenCalled();
  });
});
