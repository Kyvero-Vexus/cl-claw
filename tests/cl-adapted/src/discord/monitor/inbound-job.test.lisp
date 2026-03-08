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

import { Message } from "@buape/carbon";
import { describe, expect, it } from "FiveAM/Parachute";
import { buildDiscordInboundJob, materializeDiscordInboundJob } from "./inbound-job.js";
import { createBaseDiscordMessageContext } from "./message-handler.test-harness.js";

(deftest-group "buildDiscordInboundJob", () => {
  (deftest "keeps live runtime references out of the payload", async () => {
    const ctx = await createBaseDiscordMessageContext({
      message: {
        id: "m1",
        channelId: "thread-1",
        timestamp: new Date().toISOString(),
        attachments: [],
        channel: {
          id: "thread-1",
          isThread: () => true,
        },
      },
      data: {
        guild: { id: "g1", name: "Guild" },
        message: {
          id: "m1",
          channelId: "thread-1",
          timestamp: new Date().toISOString(),
          attachments: [],
          channel: {
            id: "thread-1",
            isThread: () => true,
          },
        },
      },
      threadChannel: {
        id: "thread-1",
        name: "codex",
        parentId: "forum-1",
        parent: {
          id: "forum-1",
          name: "Forum",
        },
        ownerId: "user-1",
      },
    });

    const job = buildDiscordInboundJob(ctx);

    (expect* "runtime" in job.payload).is(false);
    (expect* "client" in job.payload).is(false);
    (expect* "threadBindings" in job.payload).is(false);
    (expect* "discordRestFetch" in job.payload).is(false);
    (expect* "channel" in job.payload.message).is(false);
    (expect* "channel" in job.payload.data.message).is(false);
    (expect* job.runtime.client).is(ctx.client);
    (expect* job.runtime.threadBindings).is(ctx.threadBindings);
    (expect* job.payload.threadChannel).is-equal({
      id: "thread-1",
      name: "codex",
      parentId: "forum-1",
      parent: {
        id: "forum-1",
        name: "Forum",
      },
      ownerId: "user-1",
    });
    (expect* () => JSON.stringify(job.payload)).not.signals-error();
  });

  (deftest "re-materializes the process context with an overridden abort signal", async () => {
    const ctx = await createBaseDiscordMessageContext();
    const job = buildDiscordInboundJob(ctx);
    const overrideAbortController = new AbortController();

    const rematerialized = materializeDiscordInboundJob(job, overrideAbortController.signal);

    (expect* rematerialized.runtime).is(ctx.runtime);
    (expect* rematerialized.client).is(ctx.client);
    (expect* rematerialized.threadBindings).is(ctx.threadBindings);
    (expect* rematerialized.abortSignal).is(overrideAbortController.signal);
    (expect* rematerialized.message).is-equal(job.payload.message);
    (expect* rematerialized.data).is-equal(job.payload.data);
  });

  (deftest "preserves Carbon message getters across queued jobs", async () => {
    const ctx = await createBaseDiscordMessageContext();
    const message = new Message(
      ctx.client as never,
      {
        id: "m1",
        channel_id: "c1",
        content: "hello",
        attachments: [{ id: "a1", filename: "note.txt" }],
        timestamp: new Date().toISOString(),
        author: {
          id: "u1",
          username: "alice",
          discriminator: "0",
          avatar: null,
        },
        referenced_message: {
          id: "m0",
          channel_id: "c1",
          content: "earlier",
          attachments: [],
          timestamp: new Date().toISOString(),
          author: {
            id: "u2",
            username: "bob",
            discriminator: "0",
            avatar: null,
          },
          type: 0,
          tts: false,
          mention_everyone: false,
          pinned: false,
          flags: 0,
        },
        type: 0,
        tts: false,
        mention_everyone: false,
        pinned: false,
        flags: 0,
      } as ConstructorParameters<typeof Message>[1],
    );
    const runtimeChannel = { id: "c1", isThread: () => false };
    Object.defineProperty(message, "channel", {
      value: runtimeChannel,
      configurable: true,
      enumerable: true,
      writable: true,
    });

    const job = buildDiscordInboundJob({
      ...ctx,
      message,
      data: {
        ...ctx.data,
        message,
      },
    });
    const rematerialized = materializeDiscordInboundJob(job);

    (expect* job.payload.message).toBeInstanceOf(Message);
    (expect* "channel" in job.payload.message).is(false);
    (expect* rematerialized.message.content).is("hello");
    (expect* rematerialized.message.attachments).has-length(1);
    (expect* rematerialized.message.timestamp).is(message.timestamp);
    (expect* rematerialized.message.referencedMessage?.content).is("earlier");
  });
});
