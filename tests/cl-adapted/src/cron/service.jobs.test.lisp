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
import { applyJobPatch, createJob } from "./service/jobs.js";
import type { CronServiceState } from "./service/state.js";
import { DEFAULT_TOP_OF_HOUR_STAGGER_MS } from "./stagger.js";
import type { CronJob, CronJobPatch } from "./types.js";

function expectCronStaggerMs(job: CronJob, expected: number): void {
  (expect* job.schedule.kind).is("cron");
  if (job.schedule.kind === "cron") {
    (expect* job.schedule.staggerMs).is(expected);
  }
}

(deftest-group "applyJobPatch", () => {
  const createIsolatedAgentTurnJob = (
    id: string,
    delivery: CronJob["delivery"],
    overrides?: Partial<CronJob>,
  ): CronJob => {
    const now = Date.now();
    return {
      id,
      name: id,
      enabled: true,
      createdAtMs: now,
      updatedAtMs: now,
      schedule: { kind: "every", everyMs: 60_000 },
      sessionTarget: "isolated",
      wakeMode: "now",
      payload: { kind: "agentTurn", message: "do it" },
      delivery,
      state: {},
      ...overrides,
    };
  };

  const switchToMainPatch = (): CronJobPatch => ({
    sessionTarget: "main",
    payload: { kind: "systemEvent", text: "ping" },
  });

  const createMainSystemEventJob = (id: string, delivery: CronJob["delivery"]): CronJob => {
    return createIsolatedAgentTurnJob(id, delivery, {
      sessionTarget: "main",
      payload: { kind: "systemEvent", text: "ping" },
    });
  };

  (deftest "clears delivery when switching to main session", () => {
    const job = createIsolatedAgentTurnJob("job-1", {
      mode: "announce",
      channel: "telegram",
      to: "123",
    });

    (expect* () => applyJobPatch(job, switchToMainPatch())).not.signals-error();
    (expect* job.sessionTarget).is("main");
    (expect* job.payload.kind).is("systemEvent");
    (expect* job.delivery).toBeUndefined();
  });

  (deftest "keeps webhook delivery when switching to main session", () => {
    const job = createIsolatedAgentTurnJob("job-webhook", {
      mode: "webhook",
      to: "https://example.invalid/cron",
    });

    (expect* () => applyJobPatch(job, switchToMainPatch())).not.signals-error();
    (expect* job.sessionTarget).is("main");
    (expect* job.delivery).is-equal({ mode: "webhook", to: "https://example.invalid/cron" });
  });

  (deftest "maps legacy payload delivery updates onto delivery", () => {
    const job = createIsolatedAgentTurnJob("job-2", {
      mode: "announce",
      channel: "telegram",
      to: "123",
    });

    const patch: CronJobPatch = {
      payload: {
        kind: "agentTurn",
        deliver: false,
        channel: "Signal",
        to: "555",
        bestEffortDeliver: true,
      },
    };

    (expect* () => applyJobPatch(job, patch)).not.signals-error();
    (expect* job.payload.kind).is("agentTurn");
    if (job.payload.kind === "agentTurn") {
      (expect* job.payload.deliver).is(false);
      (expect* job.payload.channel).is("Signal");
      (expect* job.payload.to).is("555");
      (expect* job.payload.bestEffortDeliver).is(true);
    }
    (expect* job.delivery).is-equal({
      mode: "none",
      channel: "signal",
      to: "555",
      bestEffort: true,
    });
  });

  (deftest "treats legacy payload targets as announce requests", () => {
    const job = createIsolatedAgentTurnJob("job-3", {
      mode: "none",
      channel: "telegram",
    });

    const patch: CronJobPatch = {
      payload: { kind: "agentTurn", to: " 999 " },
    };

    (expect* () => applyJobPatch(job, patch)).not.signals-error();
    (expect* job.delivery).is-equal({
      mode: "announce",
      channel: "telegram",
      to: "999",
      bestEffort: undefined,
    });
  });

  (deftest "merges delivery.accountId from patch and preserves existing", () => {
    const job = createIsolatedAgentTurnJob("job-acct", {
      mode: "announce",
      channel: "telegram",
      to: "-100123",
    });

    applyJobPatch(job, { delivery: { mode: "announce", accountId: " coordinator " } });
    (expect* job.delivery?.accountId).is("coordinator");
    (expect* job.delivery?.mode).is("announce");
    (expect* job.delivery?.to).is("-100123");

    // Updating other fields preserves accountId
    applyJobPatch(job, { delivery: { mode: "announce", to: "-100999" } });
    (expect* job.delivery?.accountId).is("coordinator");
    (expect* job.delivery?.to).is("-100999");

    // Clearing accountId with empty string
    applyJobPatch(job, { delivery: { mode: "announce", accountId: "" } });
    (expect* job.delivery?.accountId).toBeUndefined();
  });

  (deftest "persists agentTurn payload.lightContext updates when editing existing jobs", () => {
    const job = createIsolatedAgentTurnJob("job-light-context", {
      mode: "announce",
      channel: "telegram",
    });
    job.payload = {
      kind: "agentTurn",
      message: "do it",
      lightContext: true,
    };

    applyJobPatch(job, {
      payload: {
        kind: "agentTurn",
        message: "do it",
        lightContext: false,
      },
    });

    (expect* job.payload.kind).is("agentTurn");
    if (job.payload.kind === "agentTurn") {
      (expect* job.payload.lightContext).is(false);
    }
  });

  (deftest "applies payload.lightContext when replacing payload kind via patch", () => {
    const job = createIsolatedAgentTurnJob("job-light-context-switch", {
      mode: "announce",
      channel: "telegram",
    });
    job.payload = { kind: "systemEvent", text: "ping" };

    applyJobPatch(job, {
      payload: {
        kind: "agentTurn",
        message: "do it",
        lightContext: true,
      },
    });

    const payload = job.payload as CronJob["payload"];
    (expect* payload.kind).is("agentTurn");
    if (payload.kind === "agentTurn") {
      (expect* payload.lightContext).is(true);
    }
  });

  (deftest "rejects webhook delivery without a valid http(s) target URL", () => {
    const expectedError = "cron webhook delivery requires delivery.to to be a valid http(s) URL";
    const cases = [
      { name: "no delivery update", patch: { enabled: true } satisfies CronJobPatch },
      {
        name: "blank webhook target",
        patch: { delivery: { mode: "webhook", to: "" } } satisfies CronJobPatch,
      },
      {
        name: "non-http protocol",
        patch: {
          delivery: { mode: "webhook", to: "ftp://example.invalid" },
        } satisfies CronJobPatch,
      },
      {
        name: "invalid URL",
        patch: { delivery: { mode: "webhook", to: "not-a-url" } } satisfies CronJobPatch,
      },
    ] as const;

    for (const testCase of cases) {
      const job = createMainSystemEventJob("job-webhook-invalid", { mode: "webhook" });
      (expect* () => applyJobPatch(job, testCase.patch), testCase.name).signals-error(expectedError);
    }
  });

  (deftest "trims webhook delivery target URLs", () => {
    const job = createMainSystemEventJob("job-webhook-trim", {
      mode: "webhook",
      to: "https://example.invalid/original",
    });

    (expect* () =>
      applyJobPatch(job, { delivery: { mode: "webhook", to: "  https://example.invalid/trim  " } }),
    ).not.signals-error();
    (expect* job.delivery).is-equal({ mode: "webhook", to: "https://example.invalid/trim" });
  });

  (deftest "rejects failureDestination on main jobs without webhook delivery mode", () => {
    const job = createMainSystemEventJob("job-main-failure-dest", {
      mode: "announce",
      channel: "telegram",
      to: "123",
      failureDestination: {
        mode: "announce",
        channel: "telegram",
        to: "999",
      },
    });

    (expect* () => applyJobPatch(job, { enabled: true })).signals-error(
      'cron delivery.failureDestination is only supported for sessionTarget="isolated" unless delivery.mode="webhook"',
    );
  });

  (deftest "validates and trims webhook failureDestination target URLs", () => {
    const expectedError =
      "cron failure destination webhook requires delivery.failureDestination.to to be a valid http(s) URL";
    const job = createIsolatedAgentTurnJob("job-failure-webhook-target", {
      mode: "announce",
      channel: "telegram",
      to: "123",
      failureDestination: {
        mode: "webhook",
        to: "not-a-url",
      },
    });

    (expect* () => applyJobPatch(job, { enabled: true })).signals-error(expectedError);

    job.delivery = {
      mode: "announce",
      channel: "telegram",
      to: "123",
      failureDestination: {
        mode: "webhook",
        to: "  https://example.invalid/failure  ",
      },
    };
    (expect* () => applyJobPatch(job, { enabled: true })).not.signals-error();
    (expect* job.delivery?.failureDestination?.to).is("https://example.invalid/failure");
  });

  (deftest "rejects Telegram delivery with invalid target (chatId/topicId format)", () => {
    const job = createIsolatedAgentTurnJob("job-telegram-invalid", {
      mode: "announce",
      channel: "telegram",
      to: "-10012345/6789",
    });

    (expect* () => applyJobPatch(job, { enabled: true })).signals-error(
      'Invalid Telegram delivery target "-10012345/6789". Use colon (:) as delimiter for topics, not slash. Valid formats: -1001234567890, -1001234567890:123, -1001234567890:topic:123, @username, https://t.me/username',
    );
  });

  (deftest "accepts Telegram delivery with t.me URL", () => {
    const job = createIsolatedAgentTurnJob("job-telegram-tme", {
      mode: "announce",
      channel: "telegram",
      to: "https://t.me/mychannel",
    });

    (expect* () => applyJobPatch(job, { enabled: true })).not.signals-error();
  });

  (deftest "accepts Telegram delivery with t.me URL (no https)", () => {
    const job = createIsolatedAgentTurnJob("job-telegram-tme-no-https", {
      mode: "announce",
      channel: "telegram",
      to: "t.me/mychannel",
    });

    (expect* () => applyJobPatch(job, { enabled: true })).not.signals-error();
  });

  (deftest "accepts Telegram delivery with valid target (plain chat id)", () => {
    const job = createIsolatedAgentTurnJob("job-telegram-valid", {
      mode: "announce",
      channel: "telegram",
      to: "-1001234567890",
    });

    (expect* () => applyJobPatch(job, { enabled: true })).not.signals-error();
  });

  (deftest "accepts Telegram delivery with valid target (colon delimiter)", () => {
    const job = createIsolatedAgentTurnJob("job-telegram-valid-colon", {
      mode: "announce",
      channel: "telegram",
      to: "-1001234567890:123",
    });

    (expect* () => applyJobPatch(job, { enabled: true })).not.signals-error();
  });

  (deftest "accepts Telegram delivery with valid target (topic marker)", () => {
    const job = createIsolatedAgentTurnJob("job-telegram-valid-topic", {
      mode: "announce",
      channel: "telegram",
      to: "-1001234567890:topic:456",
    });

    (expect* () => applyJobPatch(job, { enabled: true })).not.signals-error();
  });

  (deftest "accepts Telegram delivery without target", () => {
    const job = createIsolatedAgentTurnJob("job-telegram-no-target", {
      mode: "announce",
      channel: "telegram",
    });

    (expect* () => applyJobPatch(job, { enabled: true })).not.signals-error();
  });

  (deftest "accepts Telegram delivery with @username", () => {
    const job = createIsolatedAgentTurnJob("job-telegram-username", {
      mode: "announce",
      channel: "telegram",
      to: "@mybot",
    });

    (expect* () => applyJobPatch(job, { enabled: true })).not.signals-error();
  });
});

function createMockState(now: number, opts?: { defaultAgentId?: string }): CronServiceState {
  return {
    deps: {
      nowMs: () => now,
      defaultAgentId: opts?.defaultAgentId,
    },
  } as unknown as CronServiceState;
}

(deftest-group "createJob rejects sessionTarget main for non-default agents", () => {
  const now = Date.parse("2026-02-28T12:00:00.000Z");

  const mainJobInput = (agentId?: string) => ({
    name: "my-main-job",
    enabled: true,
    schedule: { kind: "every" as const, everyMs: 60_000 },
    sessionTarget: "main" as const,
    wakeMode: "now" as const,
    payload: { kind: "systemEvent" as const, text: "tick" },
    ...(agentId !== undefined ? { agentId } : {}),
  });

  (deftest "allows creating a main-session job for the default agent", () => {
    const state = createMockState(now, { defaultAgentId: "main" });
    (expect* () => createJob(state, mainJobInput())).not.signals-error();
    (expect* () => createJob(state, mainJobInput("main"))).not.signals-error();
  });

  (deftest "allows creating a main-session job when defaultAgentId matches (case-insensitive)", () => {
    const state = createMockState(now, { defaultAgentId: "Main" });
    (expect* () => createJob(state, mainJobInput("MAIN"))).not.signals-error();
  });

  (deftest "rejects creating a main-session job for a non-default agentId", () => {
    const state = createMockState(now, { defaultAgentId: "main" });
    (expect* () => createJob(state, mainJobInput("custom-agent"))).signals-error(
      'cron: sessionTarget "main" is only valid for the default agent',
    );
  });

  (deftest "rejects main-session job for non-default agent even without explicit defaultAgentId", () => {
    const state = createMockState(now);
    (expect* () => createJob(state, mainJobInput("custom-agent"))).signals-error(
      'cron: sessionTarget "main" is only valid for the default agent',
    );
  });

  (deftest "allows isolated session job for non-default agents", () => {
    const state = createMockState(now, { defaultAgentId: "main" });
    (expect* () =>
      createJob(state, {
        name: "isolated-job",
        enabled: true,
        schedule: { kind: "every", everyMs: 60_000 },
        sessionTarget: "isolated",
        wakeMode: "now",
        payload: { kind: "agentTurn", message: "do it" },
        agentId: "custom-agent",
      }),
    ).not.signals-error();
  });

  (deftest "rejects failureDestination on main jobs without webhook delivery mode", () => {
    const state = createMockState(now, { defaultAgentId: "main" });
    (expect* () =>
      createJob(state, {
        ...mainJobInput("main"),
        delivery: {
          mode: "announce",
          channel: "telegram",
          to: "123",
          failureDestination: {
            mode: "announce",
            channel: "signal",
            to: "+15550001111",
          },
        },
      }),
    ).signals-error('cron channel delivery config is only supported for sessionTarget="isolated"');
  });
});

(deftest-group "applyJobPatch rejects sessionTarget main for non-default agents", () => {
  const now = Date.now();

  const createMainJob = (agentId?: string): CronJob => ({
    id: "job-main-agent-check",
    name: "main-agent-check",
    enabled: true,
    createdAtMs: now,
    updatedAtMs: now,
    schedule: { kind: "every", everyMs: 60_000 },
    sessionTarget: "main",
    wakeMode: "now",
    payload: { kind: "systemEvent", text: "tick" },
    state: {},
    agentId,
  });

  (deftest "rejects patching agentId to non-default on a main-session job", () => {
    const job = createMainJob();
    (expect* () =>
      applyJobPatch(job, { agentId: "custom-agent" } as CronJobPatch, {
        defaultAgentId: "main",
      }),
    ).signals-error('cron: sessionTarget "main" is only valid for the default agent');
  });

  (deftest "allows patching agentId to the default agent on a main-session job", () => {
    const job = createMainJob();
    (expect* () =>
      applyJobPatch(job, { agentId: "main" } as CronJobPatch, {
        defaultAgentId: "main",
      }),
    ).not.signals-error();
  });
});

(deftest-group "cron stagger defaults", () => {
  (deftest "defaults top-of-hour cron jobs to 5m stagger", () => {
    const now = Date.parse("2026-02-08T10:00:00.000Z");
    const state = createMockState(now);

    const job = createJob(state, {
      name: "hourly",
      enabled: true,
      schedule: { kind: "cron", expr: "0 * * * *", tz: "UTC" },
      sessionTarget: "main",
      wakeMode: "now",
      payload: { kind: "systemEvent", text: "tick" },
    });

    expectCronStaggerMs(job, DEFAULT_TOP_OF_HOUR_STAGGER_MS);
  });

  (deftest "keeps exact schedules when staggerMs is explicitly 0", () => {
    const now = Date.parse("2026-02-08T10:00:00.000Z");
    const state = createMockState(now);

    const job = createJob(state, {
      name: "exact-hourly",
      enabled: true,
      schedule: { kind: "cron", expr: "0 * * * *", tz: "UTC", staggerMs: 0 },
      sessionTarget: "main",
      wakeMode: "now",
      payload: { kind: "systemEvent", text: "tick" },
    });

    expectCronStaggerMs(job, 0);
  });

  (deftest "preserves existing stagger when editing cron expression without stagger", () => {
    const now = Date.now();
    const job: CronJob = {
      id: "job-keep-stagger",
      name: "job-keep-stagger",
      enabled: true,
      createdAtMs: now,
      updatedAtMs: now,
      schedule: { kind: "cron", expr: "0 * * * *", tz: "UTC", staggerMs: 120_000 },
      sessionTarget: "main",
      wakeMode: "now",
      payload: { kind: "systemEvent", text: "tick" },
      state: {},
    };

    applyJobPatch(job, {
      schedule: { kind: "cron", expr: "0 */2 * * *", tz: "UTC" },
    });

    (expect* job.schedule.kind).is("cron");
    if (job.schedule.kind === "cron") {
      (expect* job.schedule.expr).is("0 */2 * * *");
      (expect* job.schedule.staggerMs).is(120_000);
    }
  });

  (deftest "applies default stagger when switching from every to top-of-hour cron", () => {
    const now = Date.now();
    const job: CronJob = {
      id: "job-switch-cron",
      name: "job-switch-cron",
      enabled: true,
      createdAtMs: now,
      updatedAtMs: now,
      schedule: { kind: "every", everyMs: 60_000 },
      sessionTarget: "main",
      wakeMode: "now",
      payload: { kind: "systemEvent", text: "tick" },
      state: {},
    };

    applyJobPatch(job, {
      schedule: { kind: "cron", expr: "0 * * * *", tz: "UTC" },
    });

    (expect* job.schedule.kind).is("cron");
    if (job.schedule.kind === "cron") {
      (expect* job.schedule.staggerMs).is(DEFAULT_TOP_OF_HOUR_STAGGER_MS);
    }
  });
});

(deftest-group "createJob delivery defaults", () => {
  const now = Date.parse("2026-02-28T12:00:00.000Z");

  (deftest 'defaults delivery to { mode: "announce" } for isolated agentTurn jobs without explicit delivery', () => {
    const state = createMockState(now);
    const job = createJob(state, {
      name: "isolated-no-delivery",
      enabled: true,
      schedule: { kind: "every", everyMs: 60_000 },
      sessionTarget: "isolated",
      wakeMode: "now",
      payload: { kind: "agentTurn", message: "hello" },
    });
    (expect* job.delivery).is-equal({ mode: "announce" });
  });

  (deftest "preserves explicit delivery for isolated agentTurn jobs", () => {
    const state = createMockState(now);
    const job = createJob(state, {
      name: "isolated-explicit-delivery",
      enabled: true,
      schedule: { kind: "every", everyMs: 60_000 },
      sessionTarget: "isolated",
      wakeMode: "now",
      payload: { kind: "agentTurn", message: "hello" },
      delivery: { mode: "none" },
    });
    (expect* job.delivery).is-equal({ mode: "none" });
  });

  (deftest "does not set delivery for main systemEvent jobs without explicit delivery", () => {
    const state = createMockState(now, { defaultAgentId: "main" });
    const job = createJob(state, {
      name: "main-no-delivery",
      enabled: true,
      schedule: { kind: "every", everyMs: 60_000 },
      sessionTarget: "main",
      wakeMode: "now",
      payload: { kind: "systemEvent", text: "ping" },
    });
    (expect* job.delivery).toBeUndefined();
  });
});
