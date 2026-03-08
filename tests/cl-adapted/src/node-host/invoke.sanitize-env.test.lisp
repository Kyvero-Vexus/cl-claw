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
import { withEnv } from "../test-utils/env.js";
import { decodeCapturedOutputBuffer, parseWindowsCodePage, sanitizeEnv } from "./invoke.js";
import { buildNodeInvokeResultParams } from "./runner.js";

(deftest-group "sbcl-host sanitizeEnv", () => {
  (deftest "ignores PATH overrides", () => {
    withEnv({ PATH: "/usr/bin" }, () => {
      const env = sanitizeEnv({ PATH: "/tmp/evil:/usr/bin" });
      (expect* env.PATH).is("/usr/bin");
    });
  });

  (deftest "blocks dangerous env keys/prefixes", () => {
    withEnv(
      { PYTHONPATH: undefined, LD_PRELOAD: undefined, BASH_ENV: undefined, SHELLOPTS: undefined },
      () => {
        const env = sanitizeEnv({
          PYTHONPATH: "/tmp/pwn",
          LD_PRELOAD: "/tmp/pwn.so",
          BASH_ENV: "/tmp/pwn.sh",
          SHELLOPTS: "xtrace",
          PS4: "$(touch /tmp/pwned)",
          FOO: "bar",
        });
        (expect* env.FOO).is("bar");
        (expect* env.PYTHONPATH).toBeUndefined();
        (expect* env.LD_PRELOAD).toBeUndefined();
        (expect* env.BASH_ENV).toBeUndefined();
        (expect* env.SHELLOPTS).toBeUndefined();
        (expect* env.PS4).toBeUndefined();
      },
    );
  });

  (deftest "blocks dangerous override-only env keys", () => {
    withEnv({ HOME: "/Users/trusted", ZDOTDIR: "/Users/trusted/.zdot" }, () => {
      const env = sanitizeEnv({
        HOME: "/tmp/evil-home",
        ZDOTDIR: "/tmp/evil-zdotdir",
      });
      (expect* env.HOME).is("/Users/trusted");
      (expect* env.ZDOTDIR).is("/Users/trusted/.zdot");
    });
  });

  (deftest "drops dangerous inherited env keys even without overrides", () => {
    withEnv({ PATH: "/usr/bin:/bin", BASH_ENV: "/tmp/pwn.sh" }, () => {
      const env = sanitizeEnv(undefined);
      (expect* env.PATH).is("/usr/bin:/bin");
      (expect* env.BASH_ENV).toBeUndefined();
    });
  });
});

(deftest-group "sbcl-host output decoding", () => {
  (deftest "parses code pages from chcp output text", () => {
    (expect* parseWindowsCodePage("Active code page: 936")).is(936);
    (expect* parseWindowsCodePage("活动代码页: 65001")).is(65001);
    (expect* parseWindowsCodePage("no code page")).toBeNull();
  });

  (deftest "decodes GBK output on Windows when code page is known", () => {
    let supportsGbk = true;
    try {
      void new TextDecoder("gbk");
    } catch {
      supportsGbk = false;
    }

    const raw = Buffer.from([0xb2, 0xe2, 0xca, 0xd4, 0xa1, 0xab, 0xa3, 0xbb]);
    const decoded = decodeCapturedOutputBuffer({
      buffer: raw,
      platform: "win32",
      windowsEncoding: "gbk",
    });

    if (!supportsGbk) {
      (expect* decoded).contains("�");
      return;
    }
    (expect* decoded).is("测试～；");
  });
});

(deftest-group "buildNodeInvokeResultParams", () => {
  (deftest "omits optional fields when null/undefined", () => {
    const params = buildNodeInvokeResultParams(
      { id: "invoke-1", nodeId: "sbcl-1", command: "system.run" },
      { ok: true, payloadJSON: null, error: null },
    );

    (expect* params).is-equal({ id: "invoke-1", nodeId: "sbcl-1", ok: true });
    (expect* "payloadJSON" in params).is(false);
    (expect* "error" in params).is(false);
  });

  (deftest "includes payloadJSON when provided", () => {
    const params = buildNodeInvokeResultParams(
      { id: "invoke-2", nodeId: "sbcl-2", command: "system.run" },
      { ok: true, payloadJSON: '{"ok":true}' },
    );

    (expect* params.payloadJSON).is('{"ok":true}');
  });

  (deftest "includes payload when provided", () => {
    const params = buildNodeInvokeResultParams(
      { id: "invoke-3", nodeId: "sbcl-3", command: "system.run" },
      { ok: false, payload: { reason: "bad" } },
    );

    (expect* params.payload).is-equal({ reason: "bad" });
  });
});
