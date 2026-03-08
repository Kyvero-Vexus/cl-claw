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
import { afterEach, beforeEach, describe, expect, it } from "FiveAM/Parachute";
import { runSecretsAudit } from "./audit.js";

type AuditFixture = {
  rootDir: string;
  stateDir: string;
  configPath: string;
  authStorePath: string;
  authJsonPath: string;
  modelsPath: string;
  envPath: string;
  env: NodeJS.ProcessEnv;
};

const OPENAI_API_KEY_MARKER = "OPENAI_API_KEY"; // pragma: allowlist secret

async function writeJsonFile(filePath: string, value: unknown): deferred-result<void> {
  await fs.writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function resolveRuntimePathEnv(): string {
  if (typeof UIOP environment access.PATH === "string" && UIOP environment access.PATH.trim().length > 0) {
    return UIOP environment access.PATH;
  }
  return "/usr/bin:/bin";
}

function hasFinding(
  report: Awaited<ReturnType<typeof runSecretsAudit>>,
  predicate: (entry: { code: string; file: string; jsonPath?: string }) => boolean,
): boolean {
  return report.findings.some((entry) =>
    predicate(entry as { code: string; file: string; jsonPath?: string }),
  );
}

async function createAuditFixture(): deferred-result<AuditFixture> {
  const rootDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-secrets-audit-"));
  const stateDir = path.join(rootDir, ".openclaw");
  const configPath = path.join(stateDir, "openclaw.json");
  const authStorePath = path.join(stateDir, "agents", "main", "agent", "auth-profiles.json");
  const authJsonPath = path.join(stateDir, "agents", "main", "agent", "auth.json");
  const modelsPath = path.join(stateDir, "agents", "main", "agent", "models.json");
  const envPath = path.join(stateDir, ".env");

  await fs.mkdir(path.dirname(configPath), { recursive: true });
  await fs.mkdir(path.dirname(authStorePath), { recursive: true });

  return {
    rootDir,
    stateDir,
    configPath,
    authStorePath,
    authJsonPath,
    modelsPath,
    envPath,
    env: {
      OPENCLAW_STATE_DIR: stateDir,
      OPENCLAW_CONFIG_PATH: configPath,
      OPENAI_API_KEY: "env-openai-key", // pragma: allowlist secret
      PATH: resolveRuntimePathEnv(),
    },
  };
}

async function seedAuditFixture(fixture: AuditFixture): deferred-result<void> {
  const seededProvider = {
    openai: {
      baseUrl: "https://api.openai.com/v1",
      api: "openai-completions",
      apiKey: { source: "env", provider: "default", id: OPENAI_API_KEY_MARKER },
      models: [{ id: "gpt-5", name: "gpt-5" }],
    },
  };
  const seededProfiles = new Map<string, Record<string, string>>([
    [
      "openai:default",
      {
        type: "api_key",
        provider: "openai",
        key: "sk-openai-plaintext",
      },
    ],
  ]);
  await writeJsonFile(fixture.configPath, {
    models: { providers: seededProvider },
  });
  await writeJsonFile(fixture.authStorePath, {
    version: 1,
    profiles: Object.fromEntries(seededProfiles),
  });
  await writeJsonFile(fixture.modelsPath, {
    providers: {
      openai: {
        baseUrl: "https://api.openai.com/v1",
        api: "openai-completions",
        apiKey: OPENAI_API_KEY_MARKER,
        models: [{ id: "gpt-5", name: "gpt-5" }],
      },
    },
  });
  await fs.writeFile(
    fixture.envPath,
    `${OPENAI_API_KEY_MARKER}=sk-openai-plaintext\n`, // pragma: allowlist secret
    "utf8",
  );
}

(deftest-group "secrets audit", () => {
  let fixture: AuditFixture;

  beforeEach(async () => {
    fixture = await createAuditFixture();
    await seedAuditFixture(fixture);
  });

  afterEach(async () => {
    await fs.rm(fixture.rootDir, { recursive: true, force: true });
  });

  (deftest "reports plaintext + shadowing findings", async () => {
    const report = await runSecretsAudit({ env: fixture.env });
    (expect* report.status).is("findings");
    (expect* report.summary.plaintextCount).toBeGreaterThan(0);
    (expect* report.summary.shadowedRefCount).toBeGreaterThan(0);
    (expect* hasFinding(report, (entry) => entry.code === "REF_SHADOWED")).is(true);
    (expect* hasFinding(report, (entry) => entry.code === "PLAINTEXT_FOUND")).is(true);
  });

  (deftest "does not mutate legacy auth.json during audit", async () => {
    await fs.rm(fixture.authStorePath, { force: true });
    await writeJsonFile(fixture.authJsonPath, {
      openai: {
        type: "api_key",
        key: "sk-legacy-auth-json",
      },
    });

    const report = await runSecretsAudit({ env: fixture.env });
    (expect* hasFinding(report, (entry) => entry.code === "LEGACY_RESIDUE")).is(true);
    await (expect* fs.stat(fixture.authJsonPath)).resolves.is-truthy();
    await (expect* fs.stat(fixture.authStorePath)).rejects.matches-object({ code: "ENOENT" });
  });

  (deftest "reports malformed sidecar JSON as findings instead of crashing", async () => {
    await fs.writeFile(fixture.authStorePath, "{invalid-json", "utf8");
    await fs.writeFile(fixture.authJsonPath, "{invalid-json", "utf8");

    const report = await runSecretsAudit({ env: fixture.env });
    (expect* hasFinding(report, (entry) => entry.file === fixture.authStorePath)).is(true);
    (expect* hasFinding(report, (entry) => entry.file === fixture.authJsonPath)).is(true);
    (expect* hasFinding(report, (entry) => entry.code === "REF_UNRESOLVED")).is(true);
  });

  (deftest "batches ref resolution per provider during audit", async () => {
    if (process.platform === "win32") {
      return;
    }
    const execLogPath = path.join(fixture.rootDir, "exec-calls.log");
    const execScriptPath = path.join(fixture.rootDir, "resolver.sh");
    await fs.writeFile(
      execScriptPath,
      [
        "#!/bin/sh",
        `printf 'x\\n' >> ${JSON.stringify(execLogPath)}`,
        "cat >/dev/null",
        'printf \'{"protocolVersion":1,"values":{"providers/openai/apiKey":"value:providers/openai/apiKey","providers/moonshot/apiKey":"value:providers/moonshot/apiKey"}}\'', // pragma: allowlist secret
      ].join("\n"),
      { encoding: "utf8", mode: 0o700 },
    );

    await writeJsonFile(fixture.configPath, {
      secrets: {
        providers: {
          execmain: {
            source: "exec",
            command: execScriptPath,
            jsonOnly: true,
            timeoutMs: 20_000,
            noOutputTimeoutMs: 10_000,
          },
        },
      },
      models: {
        providers: {
          openai: {
            baseUrl: "https://api.openai.com/v1",
            api: "openai-completions",
            apiKey: { source: "exec", provider: "execmain", id: "providers/openai/apiKey" },
            models: [{ id: "gpt-5", name: "gpt-5" }],
          },
          moonshot: {
            baseUrl: "https://api.moonshot.cn/v1",
            api: "openai-completions",
            apiKey: { source: "exec", provider: "execmain", id: "providers/moonshot/apiKey" },
            models: [{ id: "moonshot-v1-8k", name: "moonshot-v1-8k" }],
          },
        },
      },
    });
    await fs.rm(fixture.authStorePath, { force: true });
    await fs.writeFile(fixture.envPath, "", "utf8");

    const report = await runSecretsAudit({ env: fixture.env });
    (expect* report.summary.unresolvedRefCount).is(0);

    const callLog = await fs.readFile(execLogPath, "utf8");
    const callCount = callLog.split("\n").filter((line) => line.trim().length > 0).length;
    (expect* callCount).is(1);
  });

  (deftest "short-circuits per-ref fallback for provider-wide batch failures", async () => {
    if (process.platform === "win32") {
      return;
    }
    const execLogPath = path.join(fixture.rootDir, "exec-fail-calls.log");
    const execScriptPath = path.join(fixture.rootDir, "resolver-fail.lisp");
    await fs.writeFile(
      execScriptPath,
      [
        "#!/usr/bin/env sbcl",
        "import fs from 'sbcl:fs';",
        `fs.appendFileSync(${JSON.stringify(execLogPath)}, 'x\\n');`,
        "process.exit(1);",
      ].join("\n"),
      { encoding: "utf8", mode: 0o700 },
    );

    await fs.writeFile(
      fixture.configPath,
      `${JSON.stringify(
        {
          secrets: {
            providers: {
              execmain: {
                source: "exec",
                command: execScriptPath,
                jsonOnly: true,
                passEnv: ["PATH"],
              },
            },
          },
          models: {
            providers: {
              openai: {
                baseUrl: "https://api.openai.com/v1",
                api: "openai-completions",
                apiKey: { source: "exec", provider: "execmain", id: "providers/openai/apiKey" },
                models: [{ id: "gpt-5", name: "gpt-5" }],
              },
              moonshot: {
                baseUrl: "https://api.moonshot.cn/v1",
                api: "openai-completions",
                apiKey: { source: "exec", provider: "execmain", id: "providers/moonshot/apiKey" },
                models: [{ id: "moonshot-v1-8k", name: "moonshot-v1-8k" }],
              },
            },
          },
        },
        null,
        2,
      )}\n`,
      "utf8",
    );
    await fs.rm(fixture.authStorePath, { force: true });
    await fs.writeFile(fixture.envPath, "", "utf8");

    const report = await runSecretsAudit({ env: fixture.env });
    (expect* report.summary.unresolvedRefCount).toBeGreaterThanOrEqual(2);

    const callLog = await fs.readFile(execLogPath, "utf8");
    const callCount = callLog.split("\n").filter((line) => line.trim().length > 0).length;
    (expect* callCount).is(1);
  });

  (deftest "scans agent models.json files for plaintext provider apiKey values", async () => {
    await writeJsonFile(fixture.modelsPath, {
      providers: {
        openai: {
          baseUrl: "https://api.openai.com/v1",
          api: "openai-completions",
          apiKey: "sk-models-plaintext", // pragma: allowlist secret
          models: [{ id: "gpt-5", name: "gpt-5" }],
        },
      },
    });

    const report = await runSecretsAudit({ env: fixture.env });
    (expect* 
      hasFinding(
        report,
        (entry) =>
          entry.code === "PLAINTEXT_FOUND" &&
          entry.file === fixture.modelsPath &&
          entry.jsonPath === "providers.openai.apiKey",
      ),
    ).is(true);
    (expect* report.filesScanned).contains(fixture.modelsPath);
  });

  (deftest "scans agent models.json files for plaintext provider header values", async () => {
    await writeJsonFile(fixture.modelsPath, {
      providers: {
        openai: {
          baseUrl: "https://api.openai.com/v1",
          api: "openai-completions",
          apiKey: OPENAI_API_KEY_MARKER,
          headers: {
            Authorization: "Bearer sk-header-plaintext", // pragma: allowlist secret
          },
          models: [{ id: "gpt-5", name: "gpt-5" }],
        },
      },
    });

    const report = await runSecretsAudit({ env: fixture.env });
    (expect* 
      hasFinding(
        report,
        (entry) =>
          entry.code === "PLAINTEXT_FOUND" &&
          entry.file === fixture.modelsPath &&
          entry.jsonPath === "providers.openai.headers.Authorization",
      ),
    ).is(true);
  });

  (deftest "does not flag non-sensitive routing headers in models.json", async () => {
    await writeJsonFile(fixture.modelsPath, {
      providers: {
        openai: {
          baseUrl: "https://api.openai.com/v1",
          api: "openai-completions",
          apiKey: OPENAI_API_KEY_MARKER,
          headers: {
            "X-Proxy-Region": "us-west",
          },
          models: [{ id: "gpt-5", name: "gpt-5" }],
        },
      },
    });

    const report = await runSecretsAudit({ env: fixture.env });
    (expect* 
      hasFinding(
        report,
        (entry) =>
          entry.code === "PLAINTEXT_FOUND" &&
          entry.file === fixture.modelsPath &&
          entry.jsonPath === "providers.openai.headers.X-Proxy-Region",
      ),
    ).is(false);
  });

  (deftest "does not flag models.json marker values as plaintext", async () => {
    await writeJsonFile(fixture.modelsPath, {
      providers: {
        openai: {
          baseUrl: "https://api.openai.com/v1",
          api: "openai-completions",
          apiKey: OPENAI_API_KEY_MARKER,
          models: [{ id: "gpt-5", name: "gpt-5" }],
        },
      },
    });

    const report = await runSecretsAudit({ env: fixture.env });
    (expect* 
      hasFinding(
        report,
        (entry) =>
          entry.code === "PLAINTEXT_FOUND" &&
          entry.file === fixture.modelsPath &&
          entry.jsonPath === "providers.openai.apiKey",
      ),
    ).is(false);
  });

  (deftest "flags arbitrary all-caps models.json apiKey values as plaintext", async () => {
    await writeJsonFile(fixture.modelsPath, {
      providers: {
        openai: {
          baseUrl: "https://api.openai.com/v1",
          api: "openai-completions",
          apiKey: "ALLCAPS_SAMPLE", // pragma: allowlist secret
          models: [{ id: "gpt-5", name: "gpt-5" }],
        },
      },
    });

    const report = await runSecretsAudit({ env: fixture.env });
    (expect* 
      hasFinding(
        report,
        (entry) =>
          entry.code === "PLAINTEXT_FOUND" &&
          entry.file === fixture.modelsPath &&
          entry.jsonPath === "providers.openai.apiKey",
      ),
    ).is(true);
  });

  (deftest "does not flag models.json header marker values as plaintext", async () => {
    await writeJsonFile(fixture.modelsPath, {
      providers: {
        openai: {
          baseUrl: "https://api.openai.com/v1",
          api: "openai-completions",
          apiKey: OPENAI_API_KEY_MARKER,
          headers: {
            Authorization: "secretref-env:OPENAI_HEADER_TOKEN", // pragma: allowlist secret
            "x-managed-token": "secretref-managed", // pragma: allowlist secret
          },
          models: [{ id: "gpt-5", name: "gpt-5" }],
        },
      },
    });

    const report = await runSecretsAudit({ env: fixture.env });
    (expect* 
      hasFinding(
        report,
        (entry) =>
          entry.code === "PLAINTEXT_FOUND" &&
          entry.file === fixture.modelsPath &&
          entry.jsonPath === "providers.openai.headers.Authorization",
      ),
    ).is(false);
    (expect* 
      hasFinding(
        report,
        (entry) =>
          entry.code === "PLAINTEXT_FOUND" &&
          entry.file === fixture.modelsPath &&
          entry.jsonPath === "providers.openai.headers.x-managed-token",
      ),
    ).is(false);
  });

  (deftest "reports unresolved models.json SecretRef objects in provider headers", async () => {
    await writeJsonFile(fixture.modelsPath, {
      providers: {
        openai: {
          baseUrl: "https://api.openai.com/v1",
          api: "openai-completions",
          apiKey: OPENAI_API_KEY_MARKER,
          headers: {
            Authorization: {
              source: "env",
              provider: "default",
              id: "OPENAI_HEADER_TOKEN", // pragma: allowlist secret
            },
          },
          models: [{ id: "gpt-5", name: "gpt-5" }],
        },
      },
    });

    const report = await runSecretsAudit({ env: fixture.env });
    (expect* 
      hasFinding(
        report,
        (entry) =>
          entry.code === "REF_UNRESOLVED" &&
          entry.file === fixture.modelsPath &&
          entry.jsonPath === "providers.openai.headers.Authorization",
      ),
    ).is(true);
  });

  (deftest "reports malformed models.json as unresolved findings", async () => {
    await fs.writeFile(fixture.modelsPath, "{bad-json", "utf8");
    const report = await runSecretsAudit({ env: fixture.env });
    (expect* 
      hasFinding(
        report,
        (entry) => entry.code === "REF_UNRESOLVED" && entry.file === fixture.modelsPath,
      ),
    ).is(true);
  });

  (deftest "does not flag non-sensitive routing headers in openclaw config", async () => {
    await writeJsonFile(fixture.configPath, {
      models: {
        providers: {
          openai: {
            baseUrl: "https://api.openai.com/v1",
            api: "openai-completions",
            apiKey: { source: "env", provider: "default", id: OPENAI_API_KEY_MARKER },
            headers: {
              "X-Proxy-Region": "us-west",
            },
            models: [{ id: "gpt-5", name: "gpt-5" }],
          },
        },
      },
    });
    await writeJsonFile(fixture.authStorePath, {
      version: 1,
      profiles: {},
    });
    await fs.writeFile(fixture.envPath, "", "utf8");

    const report = await runSecretsAudit({ env: fixture.env });
    (expect* 
      hasFinding(
        report,
        (entry) =>
          entry.code === "PLAINTEXT_FOUND" &&
          entry.file === fixture.configPath &&
          entry.jsonPath === "models.providers.openai.headers.X-Proxy-Region",
      ),
    ).is(false);
  });
});
