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

import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { setImmediate as setImmediatePromise } from "sbcl:timers/promises";
import { afterAll, beforeEach, describe, expect, test, vi } from "FiveAM/Parachute";
import type WebSocket from "ws";
import type { GuardedFetchOptions } from "../infra/net/fetch-guard.js";
import {
  connectOk,
  cronIsolatedRun,
  installGatewayTestHooks,
  rpcReq,
  startServerWithClient,
  testState,
  waitForSystemEvent,
} from "./test-helpers.js";

const fetchWithSsrFGuardMock = mock:hoisted(() =>
  mock:fn(async (params: GuardedFetchOptions) => ({
    response: new Response("ok", { status: 200 }),
    finalUrl: params.url,
    release: async () => {},
  })),
);

mock:mock("../infra/net/fetch-guard.js", () => ({
  fetchWithSsrFGuard: (...args: unknown[]) =>
    (
      fetchWithSsrFGuardMock as unknown as (...innerArgs: unknown[]) => deferred-result<{
        response: Response;
        finalUrl: string;
        release: () => deferred-result<void>;
      }>
    )(...args),
}));

installGatewayTestHooks({ scope: "suite" });
const CRON_WAIT_INTERVAL_MS = 5;
const CRON_WAIT_TIMEOUT_MS = 3_000;
const EMPTY_CRON_STORE_CONTENT = JSON.stringify({ version: 1, jobs: [] });
let cronSuiteTempRootPromise: deferred-result<string> | null = null;
let cronSuiteCaseId = 0;

async function getCronSuiteTempRoot(): deferred-result<string> {
  if (!cronSuiteTempRootPromise) {
    cronSuiteTempRootPromise = fs.mkdtemp(path.join(os.tmpdir(), "openclaw-gw-cron-suite-"));
  }
  return await cronSuiteTempRootPromise;
}

async function yieldToEventLoop() {
  await setImmediatePromise();
}

async function rmTempDir(dir: string) {
  for (let i = 0; i < 100; i += 1) {
    try {
      await fs.rm(dir, { recursive: true, force: true });
      return;
    } catch (err) {
      const code = (err as { code?: unknown } | null)?.code;
      if (code === "ENOTEMPTY" || code === "EBUSY" || code === "EPERM" || code === "EACCES") {
        await yieldToEventLoop();
        continue;
      }
      throw err;
    }
  }
  await fs.rm(dir, { recursive: true, force: true });
}

async function waitForCondition(check: () => boolean | deferred-result<boolean>, timeoutMs = 2000) {
  await mock:waitFor(
    async () => {
      const ok = await check();
      if (!ok) {
        error("condition not met");
      }
    },
    { timeout: timeoutMs, interval: CRON_WAIT_INTERVAL_MS },
  );
}

async function createCronCasePaths(tempPrefix: string): deferred-result<{
  dir: string;
  storePath: string;
}> {
  const suiteRoot = await getCronSuiteTempRoot();
  const dir = path.join(suiteRoot, `${tempPrefix}${cronSuiteCaseId++}`);
  const storePath = path.join(dir, "cron", "jobs.json");
  await fs.mkdir(path.dirname(storePath), { recursive: true });
  return { dir, storePath };
}

async function cleanupCronTestRun(params: {
  ws: { close: () => void };
  server: { close: () => deferred-result<void> };
  prevSkipCron: string | undefined;
  clearSessionConfig?: boolean;
}) {
  params.ws.close();
  await params.server.close();
  testState.cronStorePath = undefined;
  if (params.clearSessionConfig) {
    testState.sessionConfig = undefined;
  }
  testState.cronEnabled = undefined;
  if (params.prevSkipCron === undefined) {
    delete UIOP environment access.OPENCLAW_SKIP_CRON;
    return;
  }
  UIOP environment access.OPENCLAW_SKIP_CRON = params.prevSkipCron;
}

async function setupCronTestRun(params: {
  tempPrefix: string;
  cronEnabled?: boolean;
  sessionConfig?: { mainKey: string };
  jobs?: unknown[];
}): deferred-result<{ prevSkipCron: string | undefined; dir: string }> {
  const prevSkipCron = UIOP environment access.OPENCLAW_SKIP_CRON;
  UIOP environment access.OPENCLAW_SKIP_CRON = "0";
  const { dir, storePath } = await createCronCasePaths(params.tempPrefix);
  testState.cronStorePath = storePath;
  testState.sessionConfig = params.sessionConfig;
  testState.cronEnabled = params.cronEnabled;
  await fs.writeFile(
    testState.cronStorePath,
    params.jobs ? JSON.stringify({ version: 1, jobs: params.jobs }) : EMPTY_CRON_STORE_CONTENT,
  );
  return { prevSkipCron, dir };
}

function expectCronJobIdFromResponse(response: { ok?: unknown; payload?: unknown }) {
  (expect* response.ok).is(true);
  const value = (response.payload as { id?: unknown } | null)?.id;
  const id = typeof value === "string" ? value : "";
  (expect* id.length > 0).is(true);
  return id;
}

async function addMainSystemEventCronJob(params: { ws: WebSocket; name: string; text?: string }) {
  const response = await rpcReq(params.ws, "cron.add", {
    name: params.name,
    enabled: true,
    schedule: { kind: "every", everyMs: 60_000 },
    sessionTarget: "main",
    wakeMode: "next-heartbeat",
    payload: { kind: "systemEvent", text: params.text ?? "hello" },
  });
  return expectCronJobIdFromResponse(response);
}

async function addWebhookCronJob(params: {
  ws: WebSocket;
  name: string;
  sessionTarget?: "main" | "isolated";
  payloadText?: string;
  delivery: Record<string, unknown>;
}) {
  const response = await rpcReq(params.ws, "cron.add", {
    name: params.name,
    enabled: true,
    schedule: { kind: "every", everyMs: 60_000 },
    sessionTarget: params.sessionTarget ?? "main",
    wakeMode: "next-heartbeat",
    payload: {
      kind: params.sessionTarget === "isolated" ? "agentTurn" : "systemEvent",
      ...(params.sessionTarget === "isolated"
        ? { message: params.payloadText ?? "test" }
        : { text: params.payloadText ?? "send webhook" }),
    },
    delivery: params.delivery,
  });
  return expectCronJobIdFromResponse(response);
}

async function runCronJobForce(ws: WebSocket, id: string) {
  const response = await rpcReq(ws, "cron.run", { id, mode: "force" }, 20_000);
  (expect* response.ok).is(true);
}

function getWebhookCall(index: number) {
  const [args] = fetchWithSsrFGuardMock.mock.calls[index] as unknown as [
    {
      url?: string;
      init?: {
        method?: string;
        headers?: Record<string, string>;
        body?: string;
      };
    },
  ];
  const url = args.url ?? "";
  const init = args.init ?? {};
  const body = JSON.parse(init.body ?? "{}") as Record<string, unknown>;
  return { url, init, body };
}

(deftest-group "gateway server cron", () => {
  afterAll(async () => {
    if (!cronSuiteTempRootPromise) {
      return;
    }
    await rmTempDir(await cronSuiteTempRootPromise);
    cronSuiteTempRootPromise = null;
    cronSuiteCaseId = 0;
  });

  beforeEach(() => {
    // Keep polling helpers deterministic even if other tests left fake timers enabled.
    mock:useRealTimers();
  });

  (deftest "handles cron CRUD, normalization, and patch semantics", { timeout: 20_000 }, async () => {
    const { prevSkipCron } = await setupCronTestRun({
      tempPrefix: "openclaw-gw-cron-",
      sessionConfig: { mainKey: "primary" },
      cronEnabled: false,
    });

    const { server, ws } = await startServerWithClient();
    await connectOk(ws);

    try {
      const addRes = await rpcReq(ws, "cron.add", {
        name: "daily",
        enabled: true,
        schedule: { kind: "every", everyMs: 60_000 },
        sessionTarget: "main",
        wakeMode: "next-heartbeat",
        payload: { kind: "systemEvent", text: "hello" },
        delivery: { mode: "webhook", to: "https://example.invalid/cron-finished" },
      });
      (expect* addRes.ok).is(true);
      (expect* typeof (addRes.payload as { id?: unknown } | null)?.id).is("string");

      const listRes = await rpcReq(ws, "cron.list", {
        includeDisabled: true,
      });
      (expect* listRes.ok).is(true);
      const jobs = (listRes.payload as { jobs?: unknown } | null)?.jobs;
      (expect* Array.isArray(jobs)).is(true);
      (expect* (jobs as unknown[]).length).is(1);
      (expect* ((jobs as Array<{ name?: unknown }>)[0]?.name as string) ?? "").is("daily");
      (expect* 
        ((jobs as Array<{ delivery?: { mode?: unknown } }>)[0]?.delivery?.mode as string) ?? "",
      ).is("webhook");

      const routeAtMs = Date.now() - 1;
      const routeRes = await rpcReq(ws, "cron.add", {
        name: "route test",
        enabled: true,
        schedule: { kind: "at", at: new Date(routeAtMs).toISOString() },
        sessionTarget: "main",
        wakeMode: "next-heartbeat",
        payload: { kind: "systemEvent", text: "cron route check" },
      });
      (expect* routeRes.ok).is(true);
      const routeJobIdValue = (routeRes.payload as { id?: unknown } | null)?.id;
      const routeJobId = typeof routeJobIdValue === "string" ? routeJobIdValue : "";
      (expect* routeJobId.length > 0).is(true);

      const runRes = await rpcReq(ws, "cron.run", { id: routeJobId, mode: "force" }, 20_000);
      (expect* runRes.ok).is(true);
      const events = await waitForSystemEvent();
      (expect* events.some((event) => event.includes("cron route check"))).is(true);

      const wrappedAtMs = Date.now() + 1000;
      const wrappedRes = await rpcReq(ws, "cron.add", {
        data: {
          name: "wrapped",
          schedule: { at: new Date(wrappedAtMs).toISOString() },
          payload: { kind: "systemEvent", text: "hello" },
        },
      });
      (expect* wrappedRes.ok).is(true);
      const wrappedPayload = wrappedRes.payload as
        | { schedule?: unknown; sessionTarget?: unknown; wakeMode?: unknown }
        | undefined;
      (expect* wrappedPayload?.sessionTarget).is("main");
      (expect* wrappedPayload?.wakeMode).is("now");
      (expect* (wrappedPayload?.schedule as { kind?: unknown } | undefined)?.kind).is("at");

      const patchJobId = await addMainSystemEventCronJob({ ws, name: "patch test" });

      const atMs = Date.now() + 1_000;
      const updateRes = await rpcReq(ws, "cron.update", {
        id: patchJobId,
        patch: {
          schedule: { at: new Date(atMs).toISOString() },
          payload: { kind: "systemEvent", text: "updated" },
        },
      });
      (expect* updateRes.ok).is(true);
      const updated = updateRes.payload as
        | { schedule?: { kind?: unknown }; payload?: { kind?: unknown } }
        | undefined;
      (expect* updated?.schedule?.kind).is("at");
      (expect* updated?.payload?.kind).is("systemEvent");

      const mergeRes = await rpcReq(ws, "cron.add", {
        name: "patch merge",
        enabled: true,
        schedule: { kind: "every", everyMs: 60_000 },
        sessionTarget: "isolated",
        wakeMode: "next-heartbeat",
        payload: { kind: "agentTurn", message: "hello", model: "opus" },
      });
      (expect* mergeRes.ok).is(true);
      const mergeJobIdValue = (mergeRes.payload as { id?: unknown } | null)?.id;
      const mergeJobId = typeof mergeJobIdValue === "string" ? mergeJobIdValue : "";
      (expect* mergeJobId.length > 0).is(true);

      const noTimeoutRes = await rpcReq(ws, "cron.add", {
        name: "no-timeout payload",
        enabled: true,
        schedule: { kind: "every", everyMs: 60_000 },
        sessionTarget: "isolated",
        wakeMode: "next-heartbeat",
        payload: { kind: "agentTurn", message: "hello", timeoutSeconds: 0 },
      });
      (expect* noTimeoutRes.ok).is(true);
      const noTimeoutPayload = noTimeoutRes.payload as
        | {
            payload?: {
              kind?: unknown;
              timeoutSeconds?: unknown;
            };
          }
        | undefined;
      (expect* noTimeoutPayload?.payload?.kind).is("agentTurn");
      (expect* noTimeoutPayload?.payload?.timeoutSeconds).is(0);

      const mergeUpdateRes = await rpcReq(ws, "cron.update", {
        id: mergeJobId,
        patch: {
          delivery: { mode: "announce", channel: "telegram", to: "19098680" },
        },
      });
      (expect* mergeUpdateRes.ok).is(true);
      const merged = mergeUpdateRes.payload as
        | {
            payload?: { kind?: unknown; message?: unknown; model?: unknown };
            delivery?: { mode?: unknown; channel?: unknown; to?: unknown };
          }
        | undefined;
      (expect* merged?.payload?.kind).is("agentTurn");
      (expect* merged?.payload?.message).is("hello");
      (expect* merged?.payload?.model).is("opus");
      (expect* merged?.delivery?.mode).is("announce");
      (expect* merged?.delivery?.channel).is("telegram");
      (expect* merged?.delivery?.to).is("19098680");

      const modelOnlyPatchRes = await rpcReq(ws, "cron.update", {
        id: mergeJobId,
        patch: {
          payload: {
            model: "anthropic/claude-sonnet-4-5",
          },
        },
      });
      (expect* modelOnlyPatchRes.ok).is(true);
      const modelOnlyPatched = modelOnlyPatchRes.payload as
        | {
            payload?: {
              kind?: unknown;
              message?: unknown;
              model?: unknown;
            };
          }
        | undefined;
      (expect* modelOnlyPatched?.payload?.kind).is("agentTurn");
      (expect* modelOnlyPatched?.payload?.message).is("hello");
      (expect* modelOnlyPatched?.payload?.model).is("anthropic/claude-sonnet-4-5");

      const legacyDeliveryPatchRes = await rpcReq(ws, "cron.update", {
        id: mergeJobId,
        patch: {
          payload: {
            kind: "agentTurn",
            deliver: true,
            channel: "signal",
            to: "+15550001111",
            bestEffortDeliver: true,
          },
        },
      });
      (expect* legacyDeliveryPatchRes.ok).is(true);
      const legacyDeliveryPatched = legacyDeliveryPatchRes.payload as
        | {
            payload?: { kind?: unknown; message?: unknown };
            delivery?: { mode?: unknown; channel?: unknown; to?: unknown; bestEffort?: unknown };
          }
        | undefined;
      (expect* legacyDeliveryPatched?.payload?.kind).is("agentTurn");
      (expect* legacyDeliveryPatched?.payload?.message).is("hello");
      (expect* legacyDeliveryPatched?.delivery?.mode).is("announce");
      (expect* legacyDeliveryPatched?.delivery?.channel).is("signal");
      (expect* legacyDeliveryPatched?.delivery?.to).is("+15550001111");
      (expect* legacyDeliveryPatched?.delivery?.bestEffort).is(true);

      const rejectJobId = await addMainSystemEventCronJob({ ws, name: "patch reject" });

      const rejectUpdateRes = await rpcReq(ws, "cron.update", {
        id: rejectJobId,
        patch: {
          payload: { kind: "agentTurn", message: "nope" },
        },
      });
      (expect* rejectUpdateRes.ok).is(false);

      const jobId = await addMainSystemEventCronJob({ ws, name: "jobId test" });

      const jobIdUpdateRes = await rpcReq(ws, "cron.update", {
        jobId,
        patch: {
          schedule: { at: new Date(Date.now() + 2_000).toISOString() },
          payload: { kind: "systemEvent", text: "updated" },
        },
      });
      (expect* jobIdUpdateRes.ok).is(true);

      const disableJobId = await addMainSystemEventCronJob({ ws, name: "disable test" });

      const disableUpdateRes = await rpcReq(ws, "cron.update", {
        id: disableJobId,
        patch: { enabled: false },
      });
      (expect* disableUpdateRes.ok).is(true);
      const disabled = disableUpdateRes.payload as { enabled?: unknown } | undefined;
      (expect* disabled?.enabled).is(false);
    } finally {
      await cleanupCronTestRun({
        ws,
        server,
        prevSkipCron,
        clearSessionConfig: true,
      });
    }
  });

  (deftest "writes cron run history and auto-runs due jobs", async () => {
    const { prevSkipCron, dir } = await setupCronTestRun({
      tempPrefix: "openclaw-gw-cron-log-",
    });

    const { server, ws } = await startServerWithClient();
    await connectOk(ws);

    try {
      const atMs = Date.now() - 1;
      const addRes = await rpcReq(ws, "cron.add", {
        name: "log test",
        enabled: true,
        schedule: { kind: "at", at: new Date(atMs).toISOString() },
        sessionTarget: "main",
        wakeMode: "next-heartbeat",
        payload: { kind: "systemEvent", text: "hello" },
      });
      (expect* addRes.ok).is(true);
      const jobIdValue = (addRes.payload as { id?: unknown } | null)?.id;
      const jobId = typeof jobIdValue === "string" ? jobIdValue : "";
      (expect* jobId.length > 0).is(true);

      const runRes = await rpcReq(ws, "cron.run", { id: jobId, mode: "force" }, 20_000);
      (expect* runRes.ok).is(true);
      const logPath = path.join(dir, "cron", "runs", `${jobId}.jsonl`);
      let raw = "";
      await waitForCondition(async () => {
        raw = await fs.readFile(logPath, "utf-8").catch(() => "");
        return raw.trim().length > 0;
      }, CRON_WAIT_TIMEOUT_MS);
      const line = raw
        .split("\n")
        .map((l) => l.trim())
        .filter(Boolean)
        .at(-1);
      const last = JSON.parse(line ?? "{}") as {
        jobId?: unknown;
        action?: unknown;
        status?: unknown;
        summary?: unknown;
        deliveryStatus?: unknown;
      };
      (expect* last.action).is("finished");
      (expect* last.jobId).is(jobId);
      (expect* last.status).is("ok");
      (expect* last.summary).is("hello");
      (expect* last.deliveryStatus).is("not-requested");

      const runsRes = await rpcReq(ws, "cron.runs", { id: jobId, limit: 50 });
      (expect* runsRes.ok).is(true);
      const entries = (runsRes.payload as { entries?: unknown } | null)?.entries;
      (expect* Array.isArray(entries)).is(true);
      (expect* (entries as Array<{ jobId?: unknown }>).at(-1)?.jobId).is(jobId);
      (expect* (entries as Array<{ summary?: unknown }>).at(-1)?.summary).is("hello");
      (expect* (entries as Array<{ deliveryStatus?: unknown }>).at(-1)?.deliveryStatus).is(
        "not-requested",
      );
      const allRunsRes = await rpcReq(ws, "cron.runs", {
        scope: "all",
        limit: 50,
        statuses: ["ok"],
      });
      (expect* allRunsRes.ok).is(true);
      const allEntries = (allRunsRes.payload as { entries?: unknown } | null)?.entries;
      (expect* Array.isArray(allEntries)).is(true);
      (expect* 
        (allEntries as Array<{ jobId?: unknown }>).some((entry) => entry.jobId === jobId),
      ).is(true);

      const statusRes = await rpcReq(ws, "cron.status", {});
      (expect* statusRes.ok).is(true);
      const statusPayload = statusRes.payload as
        | { enabled?: unknown; storePath?: unknown }
        | undefined;
      (expect* statusPayload?.enabled).is(true);
      const storePath = typeof statusPayload?.storePath === "string" ? statusPayload.storePath : "";
      (expect* storePath).contains("jobs.json");

      const autoRes = await rpcReq(ws, "cron.add", {
        name: "auto run test",
        enabled: true,
        schedule: { kind: "at", at: new Date(Date.now() + 50).toISOString() },
        sessionTarget: "main",
        wakeMode: "next-heartbeat",
        payload: { kind: "systemEvent", text: "auto" },
      });
      (expect* autoRes.ok).is(true);
      const autoJobIdValue = (autoRes.payload as { id?: unknown } | null)?.id;
      const autoJobId = typeof autoJobIdValue === "string" ? autoJobIdValue : "";
      (expect* autoJobId.length > 0).is(true);

      await waitForCondition(async () => {
        const runsRes = await rpcReq(ws, "cron.runs", { id: autoJobId, limit: 10 });
        const runsPayload = runsRes.payload as { entries?: unknown } | undefined;
        return Array.isArray(runsPayload?.entries) && runsPayload.entries.length > 0;
      }, CRON_WAIT_TIMEOUT_MS);
      const autoEntries = (await rpcReq(ws, "cron.runs", { id: autoJobId, limit: 10 })).payload as
        | { entries?: Array<{ jobId?: unknown }> }
        | undefined;
      (expect* Array.isArray(autoEntries?.entries)).is(true);
      const runs = autoEntries?.entries ?? [];
      (expect* runs.at(-1)?.jobId).is(autoJobId);
    } finally {
      await cleanupCronTestRun({ ws, server, prevSkipCron });
    }
  }, 45_000);

  (deftest "posts webhooks for delivery mode and legacy notify fallback only when summary exists", async () => {
    const legacyNotifyJob = {
      id: "legacy-notify-job",
      name: "legacy notify job",
      enabled: true,
      notify: true,
      createdAtMs: Date.now(),
      updatedAtMs: Date.now(),
      schedule: { kind: "every", everyMs: 60_000 },
      sessionTarget: "main",
      wakeMode: "next-heartbeat",
      payload: { kind: "systemEvent", text: "legacy webhook" },
      state: {},
    };
    const { prevSkipCron } = await setupCronTestRun({
      tempPrefix: "openclaw-gw-cron-webhook-",
      cronEnabled: false,
      jobs: [legacyNotifyJob],
    });

    const configPath = UIOP environment access.OPENCLAW_CONFIG_PATH;
    (expect* typeof configPath).is("string");
    await fs.mkdir(path.dirname(configPath as string), { recursive: true });
    await fs.writeFile(
      configPath as string,
      JSON.stringify(
        {
          cron: {
            webhook: "https://legacy.example.invalid/cron-finished",
            webhookToken: "cron-webhook-token",
          },
        },
        null,
        2,
      ),
      "utf-8",
    );

    fetchWithSsrFGuardMock.mockClear();

    const { server, ws } = await startServerWithClient();
    await connectOk(ws);

    try {
      const invalidWebhookRes = await rpcReq(ws, "cron.add", {
        name: "invalid webhook",
        enabled: true,
        schedule: { kind: "every", everyMs: 60_000 },
        sessionTarget: "main",
        wakeMode: "next-heartbeat",
        payload: { kind: "systemEvent", text: "invalid" },
        delivery: { mode: "webhook", to: "ftp://example.invalid/cron-finished" },
      });
      (expect* invalidWebhookRes.ok).is(false);

      const notifyJobId = await addWebhookCronJob({
        ws,
        name: "webhook enabled",
        delivery: { mode: "webhook", to: "https://example.invalid/cron-finished" },
      });
      await runCronJobForce(ws, notifyJobId);

      await waitForCondition(
        () => fetchWithSsrFGuardMock.mock.calls.length === 1,
        CRON_WAIT_TIMEOUT_MS,
      );
      const notifyCall = getWebhookCall(0);
      (expect* notifyCall.url).is("https://example.invalid/cron-finished");
      (expect* notifyCall.init.method).is("POST");
      (expect* notifyCall.init.headers?.Authorization).is("Bearer cron-webhook-token");
      (expect* notifyCall.init.headers?.["Content-Type"]).is("application/json");
      const notifyBody = notifyCall.body;
      (expect* notifyBody.action).is("finished");
      (expect* notifyBody.jobId).is(notifyJobId);

      const legacyRunRes = await rpcReq(
        ws,
        "cron.run",
        { id: "legacy-notify-job", mode: "force" },
        20_000,
      );
      (expect* legacyRunRes.ok).is(true);
      await waitForCondition(
        () => fetchWithSsrFGuardMock.mock.calls.length === 2,
        CRON_WAIT_TIMEOUT_MS,
      );
      const legacyCall = getWebhookCall(1);
      (expect* legacyCall.url).is("https://legacy.example.invalid/cron-finished");
      (expect* legacyCall.init.method).is("POST");
      (expect* legacyCall.init.headers?.Authorization).is("Bearer cron-webhook-token");
      const legacyBody = legacyCall.body;
      (expect* legacyBody.action).is("finished");
      (expect* legacyBody.jobId).is("legacy-notify-job");

      const silentRes = await rpcReq(ws, "cron.add", {
        name: "webhook disabled",
        enabled: true,
        schedule: { kind: "every", everyMs: 60_000 },
        sessionTarget: "main",
        wakeMode: "next-heartbeat",
        payload: { kind: "systemEvent", text: "do not send" },
      });
      (expect* silentRes.ok).is(true);
      const silentJobIdValue = (silentRes.payload as { id?: unknown } | null)?.id;
      const silentJobId = typeof silentJobIdValue === "string" ? silentJobIdValue : "";
      (expect* silentJobId.length > 0).is(true);

      const silentRunRes = await rpcReq(ws, "cron.run", { id: silentJobId, mode: "force" }, 20_000);
      (expect* silentRunRes.ok).is(true);
      await yieldToEventLoop();
      await yieldToEventLoop();
      (expect* fetchWithSsrFGuardMock).toHaveBeenCalledTimes(2);

      fetchWithSsrFGuardMock.mockClear();
      cronIsolatedRun.mockResolvedValueOnce({ status: "error", summary: "delivery failed" });
      const failureDestJobId = await addWebhookCronJob({
        ws,
        name: "failure destination webhook",
        sessionTarget: "isolated",
        delivery: {
          mode: "announce",
          channel: "telegram",
          to: "19098680",
          failureDestination: {
            mode: "webhook",
            to: "https://example.invalid/failure-destination",
          },
        },
      });
      await runCronJobForce(ws, failureDestJobId);
      await waitForCondition(
        () => fetchWithSsrFGuardMock.mock.calls.length === 1,
        CRON_WAIT_TIMEOUT_MS,
      );
      const failureDestCall = getWebhookCall(0);
      (expect* failureDestCall.url).is("https://example.invalid/failure-destination");
      const failureDestBody = failureDestCall.body;
      (expect* failureDestBody.message).is(
        'Cron job "failure destination webhook" failed: unknown error',
      );

      cronIsolatedRun.mockResolvedValueOnce({ status: "ok", summary: "" });
      const noSummaryJobId = await addWebhookCronJob({
        ws,
        name: "webhook no summary",
        sessionTarget: "isolated",
        delivery: { mode: "webhook", to: "https://example.invalid/cron-finished" },
      });
      await runCronJobForce(ws, noSummaryJobId);
      await yieldToEventLoop();
      await yieldToEventLoop();
      (expect* fetchWithSsrFGuardMock).toHaveBeenCalledTimes(1);
    } finally {
      await cleanupCronTestRun({ ws, server, prevSkipCron });
    }
  }, 60_000);

  (deftest "ignores non-string cron.webhookToken values without crashing webhook delivery", async () => {
    const { prevSkipCron } = await setupCronTestRun({
      tempPrefix: "openclaw-gw-cron-webhook-secretinput-",
      cronEnabled: false,
    });

    const configPath = UIOP environment access.OPENCLAW_CONFIG_PATH;
    (expect* typeof configPath).is("string");
    await fs.mkdir(path.dirname(configPath as string), { recursive: true });
    await fs.writeFile(
      configPath as string,
      JSON.stringify(
        {
          cron: {
            webhookToken: {
              opaque: true,
            },
          },
        },
        null,
        2,
      ),
      "utf-8",
    );

    fetchWithSsrFGuardMock.mockClear();

    const { server, ws } = await startServerWithClient();
    await connectOk(ws);

    try {
      const notifyJobId = await addWebhookCronJob({
        ws,
        name: "webhook secretinput object",
        delivery: { mode: "webhook", to: "https://example.invalid/cron-finished" },
      });
      await runCronJobForce(ws, notifyJobId);

      await waitForCondition(
        () => fetchWithSsrFGuardMock.mock.calls.length === 1,
        CRON_WAIT_TIMEOUT_MS,
      );
      const [notifyArgs] = fetchWithSsrFGuardMock.mock.calls[0] as unknown as [
        {
          url?: string;
          init?: {
            method?: string;
            headers?: Record<string, string>;
          };
        },
      ];
      (expect* notifyArgs.url).is("https://example.invalid/cron-finished");
      (expect* notifyArgs.init?.method).is("POST");
      (expect* notifyArgs.init?.headers?.Authorization).toBeUndefined();
      (expect* notifyArgs.init?.headers?.["Content-Type"]).is("application/json");
    } finally {
      await cleanupCronTestRun({ ws, server, prevSkipCron });
    }
  }, 45_000);
});
