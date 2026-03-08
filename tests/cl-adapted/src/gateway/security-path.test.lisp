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
import {
  PROTECTED_PLUGIN_ROUTE_PREFIXES,
  buildCanonicalPathCandidates,
  canonicalizePathForSecurity,
  isPathProtectedByPrefixes,
  isProtectedPluginRoutePath,
} from "./security-path.js";

function buildRepeatedEncodedSlashPath(depth: number): string {
  let encodedSlash = "%2f";
  for (let i = 1; i < depth; i++) {
    encodedSlash = encodedSlash.replace(/%/g, "%25");
  }
  return `/api${encodedSlash}channels${encodedSlash}nostr${encodedSlash}default${encodedSlash}profile`;
}

(deftest-group "security-path canonicalization", () => {
  (deftest "canonicalizes decoded case/slash variants", () => {
    (expect* canonicalizePathForSecurity("/API/channels//nostr/default/profile/")).is-equal(
      expect.objectContaining({
        canonicalPath: "/api/channels/nostr/default/profile",
        candidates: ["/api/channels/nostr/default/profile"],
        malformedEncoding: false,
        decodePasses: 0,
        decodePassLimitReached: false,
        rawNormalizedPath: "/api/channels/nostr/default/profile",
      }),
    );
    const encoded = canonicalizePathForSecurity("/api/%63hannels%2Fnostr%2Fdefault%2Fprofile");
    (expect* encoded.canonicalPath).is("/api/channels/nostr/default/profile");
    (expect* encoded.candidates).contains("/api/%63hannels%2fnostr%2fdefault%2fprofile");
    (expect* encoded.candidates).contains("/api/channels/nostr/default/profile");
    (expect* encoded.decodePasses).toBeGreaterThan(0);
    (expect* encoded.decodePassLimitReached).is(false);
  });

  (deftest "resolves traversal after repeated decoding", () => {
    (expect* 
      canonicalizePathForSecurity("/api/foo/..%2fchannels/nostr/default/profile").canonicalPath,
    ).is("/api/channels/nostr/default/profile");
    (expect* 
      canonicalizePathForSecurity("/api/foo/%252e%252e%252fchannels/nostr/default/profile")
        .canonicalPath,
    ).is("/api/channels/nostr/default/profile");
  });

  (deftest "marks malformed encoding", () => {
    (expect* canonicalizePathForSecurity("/api/channels%2").malformedEncoding).is(true);
    (expect* canonicalizePathForSecurity("/api/channels%zz").malformedEncoding).is(true);
  });

  (deftest "resolves 4x encoded slash path variants to protected channel routes", () => {
    const deeplyEncoded = "/api%2525252fchannels%2525252fnostr%2525252fdefault%2525252fprofile";
    const canonical = canonicalizePathForSecurity(deeplyEncoded);
    (expect* canonical.canonicalPath).is("/api/channels/nostr/default/profile");
    (expect* canonical.decodePasses).toBeGreaterThanOrEqual(4);
    (expect* isProtectedPluginRoutePath(deeplyEncoded)).is(true);
  });

  (deftest "flags decode depth overflow and fails closed for protected prefix checks", () => {
    const excessiveDepthPath = buildRepeatedEncodedSlashPath(40);
    const candidates = buildCanonicalPathCandidates(excessiveDepthPath, 32);
    (expect* candidates.decodePassLimitReached).is(true);
    (expect* candidates.malformedEncoding).is(false);
    (expect* isProtectedPluginRoutePath(excessiveDepthPath)).is(true);
  });
});

(deftest-group "security-path protected-prefix matching", () => {
  const channelVariants = [
    "/API/channels/nostr/default/profile",
    "/api/channels%2Fnostr%2Fdefault%2Fprofile",
    "/api/%63hannels/nostr/default/profile",
    "/api/foo/..%2fchannels/nostr/default/profile",
    "/api/foo/%2e%2e%2fchannels/nostr/default/profile",
    "/api/foo/%252e%252e%252fchannels/nostr/default/profile",
    "/api%2525252fchannels%2525252fnostr%2525252fdefault%2525252fprofile",
    "/api/channels%2",
    "/api/channels%zz",
  ];

  for (const path of channelVariants) {
    (deftest `protects plugin channel path variant: ${path}`, () => {
      (expect* isProtectedPluginRoutePath(path)).is(true);
      (expect* isPathProtectedByPrefixes(path, PROTECTED_PLUGIN_ROUTE_PREFIXES)).is(true);
    });
  }

  (deftest "does not protect unrelated paths", () => {
    (expect* isProtectedPluginRoutePath("/plugin/public")).is(false);
    (expect* isProtectedPluginRoutePath("/api/channels-public")).is(false);
    (expect* isProtectedPluginRoutePath("/api/foo/..%2fchannels-public")).is(false);
    (expect* isProtectedPluginRoutePath("/api/channel")).is(false);
  });
});
