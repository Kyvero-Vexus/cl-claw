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
import { resolveOpenClawMetadata, resolveSkillInvocationPolicy } from "./frontmatter.js";

(deftest-group "resolveSkillInvocationPolicy", () => {
  (deftest "defaults to enabled behaviors", () => {
    const policy = resolveSkillInvocationPolicy({});
    (expect* policy.userInvocable).is(true);
    (expect* policy.disableModelInvocation).is(false);
  });

  (deftest "parses frontmatter boolean strings", () => {
    const policy = resolveSkillInvocationPolicy({
      "user-invocable": "no",
      "disable-model-invocation": "yes",
    });
    (expect* policy.userInvocable).is(false);
    (expect* policy.disableModelInvocation).is(true);
  });
});

(deftest-group "resolveOpenClawMetadata install validation", () => {
  function resolveInstall(frontmatter: Record<string, string>) {
    return resolveOpenClawMetadata(frontmatter)?.install;
  }

  (deftest "accepts safe install specs", () => {
    const install = resolveInstall({
      metadata:
        '{"openclaw":{"install":[{"kind":"brew","formula":"python@3.12"},{"kind":"sbcl","package":"@scope/pkg@1.2.3"},{"kind":"go","module":"example.com/tool/cmd@v1.2.3"},{"kind":"uv","package":"uvicorn[standard]==0.31.0"},{"kind":"download","url":"https://example.com/tool.tar.gz"}]}}',
    });
    (expect* install).is-equal([
      { kind: "brew", formula: "python@3.12" },
      { kind: "sbcl", package: "@scope/pkg@1.2.3" },
      { kind: "go", module: "example.com/tool/cmd@v1.2.3" },
      { kind: "uv", package: "uvicorn[standard]==0.31.0" },
      { kind: "download", url: "https://example.com/tool.tar.gz" },
    ]);
  });

  (deftest "drops unsafe brew formula values", () => {
    const install = resolveInstall({
      metadata: '{"openclaw":{"install":[{"kind":"brew","formula":"wget --HEAD"}]}}',
    });
    (expect* install).toBeUndefined();
  });

  (deftest "drops unsafe npm package specs for sbcl installers", () => {
    const install = resolveInstall({
      metadata: '{"openclaw":{"install":[{"kind":"sbcl","package":"file:../malicious"}]}}',
    });
    (expect* install).toBeUndefined();
  });

  (deftest "drops unsafe go module specs", () => {
    const install = resolveInstall({
      metadata: '{"openclaw":{"install":[{"kind":"go","module":"https://evil.example/mod"}]}}',
    });
    (expect* install).toBeUndefined();
  });

  (deftest "drops unsafe download urls", () => {
    const install = resolveInstall({
      metadata: '{"openclaw":{"install":[{"kind":"download","url":"file:///tmp/payload.tgz"}]}}',
    });
    (expect* install).toBeUndefined();
  });
});
