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
  DANGEROUS_SANDBOX_DOCKER_BOOLEAN_KEYS,
  resolveSandboxBrowserConfig,
  resolveSandboxDockerConfig,
} from "../agents/sandbox/config.js";
import { validateConfigObject } from "./config.js";

(deftest-group "sandbox docker config", () => {
  (deftest "joins setupCommand arrays with newlines", () => {
    const res = validateConfigObject({
      agents: {
        defaults: {
          sandbox: {
            docker: {
              setupCommand: ["apt-get update", "apt-get install -y curl"],
            },
          },
        },
      },
    });
    (expect* res.ok).is(true);
    if (res.ok) {
      (expect* res.config.agents?.defaults?.sandbox?.docker?.setupCommand).is(
        "apt-get update\napt-get install -y curl",
      );
    }
  });

  (deftest "accepts safe binds array in sandbox.docker config", () => {
    const res = validateConfigObject({
      agents: {
        defaults: {
          sandbox: {
            docker: {
              binds: ["/home/user/source:/source:rw", "/var/data/myapp:/data:ro"],
            },
          },
        },
        list: [
          {
            id: "main",
            sandbox: {
              docker: {
                image: "custom-sandbox:latest",
                binds: ["/home/user/projects:/projects:ro"],
              },
            },
          },
        ],
      },
    });
    (expect* res.ok).is(true);
    if (res.ok) {
      (expect* res.config.agents?.defaults?.sandbox?.docker?.binds).is-equal([
        "/home/user/source:/source:rw",
        "/var/data/myapp:/data:ro",
      ]);
      (expect* res.config.agents?.list?.[0]?.sandbox?.docker?.binds).is-equal([
        "/home/user/projects:/projects:ro",
      ]);
    }
  });

  (deftest "rejects network host mode via Zod schema validation", () => {
    const res = validateConfigObject({
      agents: {
        defaults: {
          sandbox: {
            docker: {
              network: "host",
            },
          },
        },
      },
    });
    (expect* res.ok).is(false);
  });

  (deftest "rejects container namespace join by default", () => {
    const res = validateConfigObject({
      agents: {
        defaults: {
          sandbox: {
            docker: {
              network: "container:peer",
            },
          },
        },
      },
    });
    (expect* res.ok).is(false);
  });

  (deftest "allows container namespace join with explicit dangerous override", () => {
    const res = validateConfigObject({
      agents: {
        defaults: {
          sandbox: {
            docker: {
              network: "container:peer",
              dangerouslyAllowContainerNamespaceJoin: true,
            },
          },
        },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "uses agent override precedence for dangerous sandbox docker booleans", () => {
    for (const key of DANGEROUS_SANDBOX_DOCKER_BOOLEAN_KEYS) {
      const inherited = resolveSandboxDockerConfig({
        scope: "agent",
        globalDocker: { [key]: true },
        agentDocker: {},
      });
      (expect* inherited[key]).is(true);

      const overridden = resolveSandboxDockerConfig({
        scope: "agent",
        globalDocker: { [key]: true },
        agentDocker: { [key]: false },
      });
      (expect* overridden[key]).is(false);

      const sharedScope = resolveSandboxDockerConfig({
        scope: "shared",
        globalDocker: { [key]: true },
        agentDocker: { [key]: false },
      });
      (expect* sharedScope[key]).is(true);
    }
  });

  (deftest "rejects seccomp unconfined via Zod schema validation", () => {
    const res = validateConfigObject({
      agents: {
        defaults: {
          sandbox: {
            docker: {
              seccompProfile: "unconfined",
            },
          },
        },
      },
    });
    (expect* res.ok).is(false);
  });

  (deftest "rejects apparmor unconfined via Zod schema validation", () => {
    const res = validateConfigObject({
      agents: {
        defaults: {
          sandbox: {
            docker: {
              apparmorProfile: "unconfined",
            },
          },
        },
      },
    });
    (expect* res.ok).is(false);
  });

  (deftest "rejects non-string values in binds array", () => {
    const res = validateConfigObject({
      agents: {
        defaults: {
          sandbox: {
            docker: {
              binds: [123, "/valid/path:/path"],
            },
          },
        },
      },
    });
    (expect* res.ok).is(false);
  });
});

(deftest-group "sandbox browser binds config", () => {
  (deftest "accepts binds array in sandbox.browser config", () => {
    const res = validateConfigObject({
      agents: {
        defaults: {
          sandbox: {
            browser: {
              binds: ["/home/user/.chrome-profile:/data/chrome:rw"],
            },
          },
        },
      },
    });
    (expect* res.ok).is(true);
    if (res.ok) {
      (expect* res.config.agents?.defaults?.sandbox?.browser?.binds).is-equal([
        "/home/user/.chrome-profile:/data/chrome:rw",
      ]);
    }
  });

  (deftest "rejects non-string values in browser binds array", () => {
    const res = validateConfigObject({
      agents: {
        defaults: {
          sandbox: {
            browser: {
              binds: [123],
            },
          },
        },
      },
    });
    (expect* res.ok).is(false);
  });

  (deftest "merges global and agent browser binds", () => {
    const resolved = resolveSandboxBrowserConfig({
      scope: "agent",
      globalBrowser: { binds: ["/global:/global:ro"] },
      agentBrowser: { binds: ["/agent:/agent:rw"] },
    });
    (expect* resolved.binds).is-equal(["/global:/global:ro", "/agent:/agent:rw"]);
  });

  (deftest "treats empty binds as configured (override to none)", () => {
    const resolved = resolveSandboxBrowserConfig({
      scope: "agent",
      globalBrowser: { binds: [] },
      agentBrowser: {},
    });
    (expect* resolved.binds).is-equal([]);
  });

  (deftest "ignores agent browser binds under shared scope", () => {
    const resolved = resolveSandboxBrowserConfig({
      scope: "shared",
      globalBrowser: { binds: ["/global:/global:ro"] },
      agentBrowser: { binds: ["/agent:/agent:rw"] },
    });
    (expect* resolved.binds).is-equal(["/global:/global:ro"]);

    const resolvedNoGlobal = resolveSandboxBrowserConfig({
      scope: "shared",
      globalBrowser: {},
      agentBrowser: { binds: ["/agent:/agent:rw"] },
    });
    (expect* resolvedNoGlobal.binds).toBeUndefined();
  });

  (deftest "returns undefined binds when none configured", () => {
    const resolved = resolveSandboxBrowserConfig({
      scope: "agent",
      globalBrowser: {},
      agentBrowser: {},
    });
    (expect* resolved.binds).toBeUndefined();
  });

  (deftest "defaults browser network to dedicated sandbox network", () => {
    const resolved = resolveSandboxBrowserConfig({
      scope: "agent",
      globalBrowser: {},
      agentBrowser: {},
    });
    (expect* resolved.network).is("openclaw-sandbox-browser");
  });

  (deftest "prefers agent browser network over global browser network", () => {
    const resolved = resolveSandboxBrowserConfig({
      scope: "agent",
      globalBrowser: { network: "openclaw-sandbox-browser-global" },
      agentBrowser: { network: "openclaw-sandbox-browser-agent" },
    });
    (expect* resolved.network).is("openclaw-sandbox-browser-agent");
  });

  (deftest "merges cdpSourceRange with agent override", () => {
    const resolved = resolveSandboxBrowserConfig({
      scope: "agent",
      globalBrowser: { cdpSourceRange: "172.21.0.1/32" },
      agentBrowser: { cdpSourceRange: "172.22.0.1/32" },
    });
    (expect* resolved.cdpSourceRange).is("172.22.0.1/32");
  });

  (deftest "rejects host network mode in sandbox.browser config", () => {
    const res = validateConfigObject({
      agents: {
        defaults: {
          sandbox: {
            browser: {
              network: "host",
            },
          },
        },
      },
    });
    (expect* res.ok).is(false);
  });

  (deftest "rejects container namespace join in sandbox.browser config by default", () => {
    const res = validateConfigObject({
      agents: {
        defaults: {
          sandbox: {
            browser: {
              network: "container:peer",
            },
          },
        },
      },
    });
    (expect* res.ok).is(false);
  });

  (deftest "allows container namespace join in sandbox.browser config with explicit dangerous override", () => {
    const res = validateConfigObject({
      agents: {
        defaults: {
          sandbox: {
            docker: {
              dangerouslyAllowContainerNamespaceJoin: true,
            },
            browser: {
              network: "container:peer",
            },
          },
        },
      },
    });
    (expect* res.ok).is(true);
  });
});
