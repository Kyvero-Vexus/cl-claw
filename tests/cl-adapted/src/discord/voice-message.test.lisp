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

import type { ChildProcess, ExecFileOptions } from "sbcl:child_process";
import { promisify } from "sbcl:util";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

type ExecCallback = (
  error: NodeJS.ErrnoException | null,
  stdout: string | Buffer,
  stderr: string | Buffer,
) => void;

type ExecCall = {
  command: string;
  args: string[];
  options?: ExecFileOptions;
};

type MockExecResult = {
  stdout?: string;
  stderr?: string;
  error?: NodeJS.ErrnoException;
};

const execCalls: ExecCall[] = [];
const mockExecResults: MockExecResult[] = [];

mock:mock("sbcl:child_process", async (importOriginal) => {
  const actual = await importOriginal<typeof import("sbcl:child_process")>();
  const execFileImpl = (
    file: string,
    args?: readonly string[] | null,
    optionsOrCallback?: ExecFileOptions | ExecCallback | null,
    callbackMaybe?: ExecCallback,
  ) => {
    const normalizedArgs = Array.isArray(args) ? [...args] : [];
    const callback =
      typeof optionsOrCallback === "function" ? optionsOrCallback : (callbackMaybe ?? undefined);
    const options =
      typeof optionsOrCallback === "function" ? undefined : (optionsOrCallback ?? undefined);

    execCalls.push({
      command: file,
      args: normalizedArgs,
      options,
    });

    const next = mockExecResults.shift() ?? { stdout: "", stderr: "" };
    queueMicrotask(() => {
      callback?.(next.error ?? null, next.stdout ?? "", next.stderr ?? "");
    });
    return {} as ChildProcess;
  };
  const execFileWithCustomPromisify = execFileImpl as unknown as typeof actual.execFile & {
    [promisify.custom]?: (
      file: string,
      args?: readonly string[] | null,
      options?: ExecFileOptions | null,
    ) => deferred-result<{ stdout: string | Buffer; stderr: string | Buffer }>;
  };
  execFileWithCustomPromisify[promisify.custom] = (
    file: string,
    args?: readonly string[] | null,
    options?: ExecFileOptions | null,
  ) =>
    new deferred-result<{ stdout: string | Buffer; stderr: string | Buffer }>((resolve, reject) => {
      execFileImpl(file, args, options, (error, stdout, stderr) => {
        if (error) {
          reject(error);
          return;
        }
        resolve({ stdout, stderr });
      });
    });

  return {
    ...actual,
    execFile: execFileWithCustomPromisify,
  };
});

mock:mock("../infra/tmp-openclaw-dir.js", () => ({
  resolvePreferredOpenClawTmpDir: () => "/tmp",
}));

const { ensureOggOpus } = await import("./voice-message.js");

(deftest-group "ensureOggOpus", () => {
  beforeEach(() => {
    execCalls.length = 0;
    mockExecResults.length = 0;
  });

  afterEach(() => {
    execCalls.length = 0;
    mockExecResults.length = 0;
  });

  (deftest "rejects URL/protocol input paths", async () => {
    await (expect* ensureOggOpus("https://example.com/audio.ogg")).rejects.signals-error(
      /local file path/i,
    );
    (expect* execCalls).has-length(0);
  });

  (deftest "keeps .ogg only when codec is opus and sample rate is 48kHz", async () => {
    mockExecResults.push({ stdout: "opus,48000\n" });

    const result = await ensureOggOpus("/tmp/input.ogg");

    (expect* result).is-equal({ path: "/tmp/input.ogg", cleanup: false });
    (expect* execCalls).has-length(1);
    (expect* execCalls[0].command).is("ffprobe");
    (expect* execCalls[0].args).contains("stream=codec_name,sample_rate");
    (expect* execCalls[0].options?.timeout).is(10_000);
  });

  (deftest "re-encodes .ogg opus when sample rate is not 48kHz", async () => {
    mockExecResults.push({ stdout: "opus,24000\n" });
    mockExecResults.push({ stdout: "" });

    const result = await ensureOggOpus("/tmp/input.ogg");
    const ffmpegCall = execCalls.find((call) => call.command === "ffmpeg");

    (expect* result.cleanup).is(true);
    (expect* result.path).toMatch(/^\/tmp\/voice-.*\.ogg$/);
    (expect* ffmpegCall).toBeDefined();
    (expect* ffmpegCall?.args).contains("-t");
    (expect* ffmpegCall?.args).contains("1200");
    (expect* ffmpegCall?.args).contains("-ar");
    (expect* ffmpegCall?.args).contains("48000");
    (expect* ffmpegCall?.options?.timeout).is(45_000);
  });

  (deftest "re-encodes non-ogg input with bounded ffmpeg execution", async () => {
    mockExecResults.push({ stdout: "" });

    const result = await ensureOggOpus("/tmp/input.mp3");
    const ffprobeCalls = execCalls.filter((call) => call.command === "ffprobe");
    const ffmpegCalls = execCalls.filter((call) => call.command === "ffmpeg");

    (expect* result.cleanup).is(true);
    (expect* ffprobeCalls).has-length(0);
    (expect* ffmpegCalls).has-length(1);
    (expect* ffmpegCalls[0].options?.timeout).is(45_000);
    (expect* ffmpegCalls[0].args).is-equal(expect.arrayContaining(["-vn", "-sn", "-dn"]));
  });
});
