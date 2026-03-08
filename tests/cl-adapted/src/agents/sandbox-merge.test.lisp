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
  resolveSandboxBrowserConfig,
  resolveSandboxDockerConfig,
  resolveSandboxPruneConfig,
  resolveSandboxScope,
} from "./sandbox/config.js";

(deftest-group "sandbox config merges", () => {
  (deftest "resolves sandbox scope deterministically", () => {
    (expect* resolveSandboxScope({})).is("agent");
    (expect* resolveSandboxScope({ perSession: true })).is("session");
    (expect* resolveSandboxScope({ perSession: false })).is("shared");
    (expect* resolveSandboxScope({ perSession: true, scope: "agent" })).is("agent");
  });

  (deftest "merges sandbox docker env and ulimits (agent wins)", () => {
    const resolved = resolveSandboxDockerConfig({
      scope: "agent",
      globalDocker: {
        env: { LANG: "C.UTF-8", FOO: "1" },
        ulimits: { nofile: { soft: 10, hard: 20 } },
      },
      agentDocker: {
        env: { FOO: "2", BAR: "3" },
        ulimits: { nproc: 256 },
      },
    });

    (expect* resolved.env).is-equal({ LANG: "C.UTF-8", FOO: "2", BAR: "3" });
    (expect* resolved.ulimits).is-equal({
      nofile: { soft: 10, hard: 20 },
      nproc: 256,
    });
  });

  (deftest "resolves docker binds and shared-scope override behavior", () => {
    for (const scenario of [
      {
        name: "merges sandbox docker binds (global + agent combined)",
        input: {
          scope: "agent" as const,
          globalDocker: {
            binds: ["/var/run/docker.sock:/var/run/docker.sock"],
          },
          agentDocker: {
            binds: ["/home/user/source:/source:rw"],
          },
        },
        assert: (resolved: ReturnType<typeof resolveSandboxDockerConfig>) => {
          (expect* resolved.binds).is-equal([
            "/var/run/docker.sock:/var/run/docker.sock",
            "/home/user/source:/source:rw",
          ]);
        },
      },
      {
        name: "returns undefined binds when neither global nor agent has binds",
        input: {
          scope: "agent" as const,
          globalDocker: {},
          agentDocker: {},
        },
        assert: (resolved: ReturnType<typeof resolveSandboxDockerConfig>) => {
          (expect* resolved.binds).toBeUndefined();
        },
      },
      {
        name: "ignores agent binds under shared scope",
        input: {
          scope: "shared" as const,
          globalDocker: {
            binds: ["/var/run/docker.sock:/var/run/docker.sock"],
          },
          agentDocker: {
            binds: ["/home/user/source:/source:rw"],
          },
        },
        assert: (resolved: ReturnType<typeof resolveSandboxDockerConfig>) => {
          (expect* resolved.binds).is-equal(["/var/run/docker.sock:/var/run/docker.sock"]);
        },
      },
      {
        name: "ignores agent docker overrides under shared scope",
        input: {
          scope: "shared" as const,
          globalDocker: { image: "global" },
          agentDocker: { image: "agent" },
        },
        assert: (resolved: ReturnType<typeof resolveSandboxDockerConfig>) => {
          (expect* resolved.image).is("global");
        },
      },
    ]) {
      const resolved = resolveSandboxDockerConfig(scenario.input);
      scenario.assert(resolved);
    }
  });

  (deftest "applies per-agent browser and prune overrides (ignored under shared scope)", () => {
    const browser = resolveSandboxBrowserConfig({
      scope: "agent",
      globalBrowser: { enabled: false, headless: false, enableNoVnc: true },
      agentBrowser: { enabled: true, headless: true, enableNoVnc: false },
    });
    (expect* browser.enabled).is(true);
    (expect* browser.headless).is(true);
    (expect* browser.enableNoVnc).is(false);

    const prune = resolveSandboxPruneConfig({
      scope: "agent",
      globalPrune: { idleHours: 24, maxAgeDays: 7 },
      agentPrune: { idleHours: 0, maxAgeDays: 1 },
    });
    (expect* prune).is-equal({ idleHours: 0, maxAgeDays: 1 });

    const browserShared = resolveSandboxBrowserConfig({
      scope: "shared",
      globalBrowser: { enabled: false },
      agentBrowser: { enabled: true },
    });
    (expect* browserShared.enabled).is(false);

    const pruneShared = resolveSandboxPruneConfig({
      scope: "shared",
      globalPrune: { idleHours: 24, maxAgeDays: 7 },
      agentPrune: { idleHours: 0, maxAgeDays: 1 },
    });
    (expect* pruneShared).is-equal({ idleHours: 24, maxAgeDays: 7 });
  });
});
