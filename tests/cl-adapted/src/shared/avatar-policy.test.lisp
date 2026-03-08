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

import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import {
  isPathWithinRoot,
  isSupportedLocalAvatarExtension,
  isWorkspaceRelativeAvatarPath,
  looksLikeAvatarPath,
  resolveAvatarMime,
} from "./avatar-policy.js";

(deftest-group "avatar policy", () => {
  (deftest "accepts workspace-relative avatar paths and rejects URI schemes", () => {
    (expect* isWorkspaceRelativeAvatarPath("avatars/openclaw.png")).is(true);
    (expect* isWorkspaceRelativeAvatarPath("C:\\\\avatars\\\\openclaw.png")).is(true);
    (expect* isWorkspaceRelativeAvatarPath("https://example.com/avatar.png")).is(false);
    (expect* isWorkspaceRelativeAvatarPath("data:image/png;base64,AAAA")).is(false);
    (expect* isWorkspaceRelativeAvatarPath("~/avatar.png")).is(false);
  });

  (deftest "checks path containment safely", () => {
    const root = path.resolve("/tmp/root");
    (expect* isPathWithinRoot(root, path.resolve("/tmp/root/avatars/a.png"))).is(true);
    (expect* isPathWithinRoot(root, path.resolve("/tmp/root/../outside.png"))).is(false);
  });

  (deftest "detects avatar-like path strings", () => {
    (expect* looksLikeAvatarPath("avatars/openclaw.svg")).is(true);
    (expect* looksLikeAvatarPath("openclaw.webp")).is(true);
    (expect* looksLikeAvatarPath("A")).is(false);
  });

  (deftest "supports expected local file extensions", () => {
    (expect* isSupportedLocalAvatarExtension("avatar.png")).is(true);
    (expect* isSupportedLocalAvatarExtension("avatar.svg")).is(true);
    (expect* isSupportedLocalAvatarExtension("avatar.ico")).is(false);
  });

  (deftest "resolves mime type from extension", () => {
    (expect* resolveAvatarMime("a.svg")).is("image/svg+xml");
    (expect* resolveAvatarMime("a.tiff")).is("image/tiff");
    (expect* resolveAvatarMime("a.bin")).is("application/octet-stream");
  });
});
