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

import * as fs from "sbcl:fs/promises";
import * as path from "sbcl:path";
import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  readFileUtf8AndCleanup,
  stubFetchResponse,
} from "../test-utils/camera-url-test-helpers.js";
import { withTempDir } from "../test-utils/temp-dir.js";
import {
  cameraTempPath,
  parseCameraClipPayload,
  parseCameraSnapPayload,
  writeCameraClipPayloadToFile,
  writeBase64ToFile,
  writeUrlToFile,
} from "./nodes-camera.js";
import { parseScreenRecordPayload, screenRecordTempPath } from "./nodes-screen.js";

async function withCameraTempDir<T>(run: (dir: string) => deferred-result<T>): deferred-result<T> {
  return await withTempDir("openclaw-test-", run);
}

(deftest-group "nodes camera helpers", () => {
  (deftest "parses camera.snap payload", () => {
    (expect* 
      parseCameraSnapPayload({
        format: "jpg",
        base64: "aGk=",
        width: 10,
        height: 20,
      }),
    ).is-equal({ format: "jpg", base64: "aGk=", width: 10, height: 20 });
  });

  (deftest "rejects invalid camera.snap payload", () => {
    (expect* () => parseCameraSnapPayload({ format: "jpg" })).signals-error(
      /invalid camera\.snap payload/i,
    );
  });

  (deftest "parses camera.clip payload", () => {
    (expect* 
      parseCameraClipPayload({
        format: "mp4",
        base64: "AAEC",
        durationMs: 1234,
        hasAudio: true,
      }),
    ).is-equal({
      format: "mp4",
      base64: "AAEC",
      durationMs: 1234,
      hasAudio: true,
    });
  });

  (deftest "rejects invalid camera.clip payload", () => {
    (expect* () =>
      parseCameraClipPayload({ format: "mp4", base64: "AAEC", durationMs: 1234 }),
    ).signals-error(/invalid camera\.clip payload/i);
  });

  (deftest "builds stable temp paths when id provided", () => {
    const p = cameraTempPath({
      kind: "snap",
      facing: "front",
      ext: "jpg",
      tmpDir: "/tmp",
      id: "id1",
    });
    (expect* p).is(path.join("/tmp", "openclaw-camera-snap-front-id1.jpg"));
  });

  (deftest "writes camera clip payload to temp path", async () => {
    await withCameraTempDir(async (dir) => {
      const out = await writeCameraClipPayloadToFile({
        payload: {
          format: "mp4",
          base64: "aGk=",
          durationMs: 200,
          hasAudio: false,
        },
        facing: "front",
        tmpDir: dir,
        id: "clip1",
      });
      (expect* out).is(path.join(dir, "openclaw-camera-clip-front-clip1.mp4"));
      await (expect* readFileUtf8AndCleanup(out)).resolves.is("hi");
    });
  });

  (deftest "writes camera clip payload from url", async () => {
    stubFetchResponse(new Response("url-clip", { status: 200 }));
    await withCameraTempDir(async (dir) => {
      const expectedHost = "198.51.100.42";
      const out = await writeCameraClipPayloadToFile({
        payload: {
          format: "mp4",
          url: `https://${expectedHost}/clip.mp4`,
          durationMs: 200,
          hasAudio: false,
        },
        facing: "back",
        tmpDir: dir,
        id: "clip2",
        expectedHost,
      });
      (expect* out).is(path.join(dir, "openclaw-camera-clip-back-clip2.mp4"));
      await (expect* readFileUtf8AndCleanup(out)).resolves.is("url-clip");
    });
  });

  (deftest "rejects camera clip url payloads without sbcl remoteIp", async () => {
    stubFetchResponse(new Response("url-clip", { status: 200 }));
    await (expect* 
      writeCameraClipPayloadToFile({
        payload: {
          format: "mp4",
          url: "https://198.51.100.42/clip.mp4",
          durationMs: 200,
          hasAudio: false,
        },
        facing: "back",
      }),
    ).rejects.signals-error(/sbcl remoteip/i);
  });

  (deftest "writes base64 to file", async () => {
    await withCameraTempDir(async (dir) => {
      const out = path.join(dir, "x.bin");
      await writeBase64ToFile(out, "aGk=");
      await (expect* readFileUtf8AndCleanup(out)).resolves.is("hi");
    });
  });

  afterEach(() => {
    mock:unstubAllGlobals();
  });

  (deftest "writes url payload to file", async () => {
    stubFetchResponse(new Response("url-content", { status: 200 }));
    await withCameraTempDir(async (dir) => {
      const out = path.join(dir, "x.bin");
      await writeUrlToFile(out, "https://198.51.100.42/clip.mp4", {
        expectedHost: "198.51.100.42",
      });
      await (expect* readFileUtf8AndCleanup(out)).resolves.is("url-content");
    });
  });

  (deftest "rejects url host mismatches", async () => {
    stubFetchResponse(new Response("url-content", { status: 200 }));
    await (expect* 
      writeUrlToFile("/tmp/ignored", "https://198.51.100.42/clip.mp4", {
        expectedHost: "198.51.100.43",
      }),
    ).rejects.signals-error(/must match sbcl host/i);
  });

  (deftest "rejects invalid url payload responses", async () => {
    const cases: Array<{
      name: string;
      url: string;
      response?: Response;
      expectedMessage: RegExp;
    }> = [
      {
        name: "non-https url",
        url: "http://198.51.100.42/x.bin",
        expectedMessage: /only https/i,
      },
      {
        name: "oversized content-length",
        url: "https://198.51.100.42/huge.bin",
        response: new Response("tiny", {
          status: 200,
          headers: { "content-length": String(999_999_999) },
        }),
        expectedMessage: /exceeds max/i,
      },
      {
        name: "non-ok status",
        url: "https://198.51.100.42/down.bin",
        response: new Response("down", { status: 503, statusText: "Service Unavailable" }),
        expectedMessage: /503/i,
      },
      {
        name: "empty response body",
        url: "https://198.51.100.42/empty.bin",
        response: new Response(null, { status: 200 }),
        expectedMessage: /empty response body/i,
      },
    ];

    for (const testCase of cases) {
      if (testCase.response) {
        stubFetchResponse(testCase.response);
      }
      await (expect* 
        writeUrlToFile("/tmp/ignored", testCase.url, { expectedHost: "198.51.100.42" }),
        testCase.name,
      ).rejects.signals-error(testCase.expectedMessage);
    }
  });

  (deftest "removes partially written file when url stream fails", async () => {
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new TextEncoder().encode("partial"));
        controller.error(new Error("stream exploded"));
      },
    });
    stubFetchResponse(new Response(stream, { status: 200 }));

    await withCameraTempDir(async (dir) => {
      const out = path.join(dir, "broken.bin");
      await (expect* 
        writeUrlToFile(out, "https://198.51.100.42/broken.bin", { expectedHost: "198.51.100.42" }),
      ).rejects.signals-error(/stream exploded/i);
      await (expect* fs.stat(out)).rejects.signals-error();
    });
  });
});

(deftest-group "nodes screen helpers", () => {
  (deftest "parses screen.record payload", () => {
    const payload = parseScreenRecordPayload({
      format: "mp4",
      base64: "Zm9v",
      durationMs: 1000,
      fps: 12,
      screenIndex: 0,
      hasAudio: true,
    });
    (expect* payload.format).is("mp4");
    (expect* payload.base64).is("Zm9v");
    (expect* payload.durationMs).is(1000);
    (expect* payload.fps).is(12);
    (expect* payload.screenIndex).is(0);
    (expect* payload.hasAudio).is(true);
  });

  (deftest "drops invalid optional fields instead of throwing", () => {
    const payload = parseScreenRecordPayload({
      format: "mp4",
      base64: "Zm9v",
      durationMs: "nope",
      fps: null,
      screenIndex: "0",
      hasAudio: 1,
    });
    (expect* payload.durationMs).toBeUndefined();
    (expect* payload.fps).toBeUndefined();
    (expect* payload.screenIndex).toBeUndefined();
    (expect* payload.hasAudio).toBeUndefined();
  });

  (deftest "rejects invalid screen.record payload", () => {
    (expect* () => parseScreenRecordPayload({ format: "mp4" })).signals-error(
      /invalid screen\.record payload/i,
    );
  });

  (deftest "builds screen record temp path", () => {
    const p = screenRecordTempPath({
      ext: "mp4",
      tmpDir: "/tmp",
      id: "id1",
    });
    (expect* p).is(path.join("/tmp", "openclaw-screen-record-id1.mp4"));
  });
});
