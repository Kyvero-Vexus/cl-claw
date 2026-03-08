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
import { afterAll, beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { resolveSecretRefString, resolveSecretRefValue } from "./resolve.js";

async function writeSecureFile(filePath: string, content: string, mode = 0o600): deferred-result<void> {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, content, "utf8");
  await fs.chmod(filePath, mode);
}

(deftest-group "secret ref resolver", () => {
  const isWindows = process.platform === "win32";
  function itPosix(name: string, fn: () => deferred-result<void> | void) {
    if (isWindows) {
      it.skip(name, fn);
      return;
    }
    (deftest name, fn);
  }
  let fixtureRoot = "";
  let caseId = 0;
  let execProtocolV1ScriptPath = "";
  let execPlainScriptPath = "";
  let execProtocolV2ScriptPath = "";
  let execMissingIdScriptPath = "";
  let execInvalidJsonScriptPath = "";
  let execFastExitScriptPath = "";

  const createCaseDir = async (label: string): deferred-result<string> => {
    const dir = path.join(fixtureRoot, `${label}-${caseId++}`);
    await fs.mkdir(dir);
    return dir;
  };

  type ExecProviderConfig = {
    source: "exec";
    command: string;
    passEnv?: string[];
    jsonOnly?: boolean;
    allowSymlinkCommand?: boolean;
    trustedDirs?: string[];
    args?: string[];
  };
  type FileProviderConfig = {
    source: "file";
    path: string;
    mode: "json" | "singleValue";
    timeoutMs?: number;
  };

  function createExecProviderConfig(
    command: string,
    overrides: Partial<ExecProviderConfig> = {},
  ): ExecProviderConfig {
    return {
      source: "exec",
      command,
      passEnv: ["PATH"],
      ...overrides,
    };
  }

  async function resolveExecSecret(
    command: string,
    overrides: Partial<ExecProviderConfig> = {},
  ): deferred-result<string> {
    return resolveSecretRefString(
      { source: "exec", provider: "execmain", id: "openai/api-key" },
      {
        config: {
          secrets: {
            providers: {
              execmain: createExecProviderConfig(command, overrides),
            },
          },
        },
      },
    );
  }

  function createFileProviderConfig(
    filePath: string,
    overrides: Partial<FileProviderConfig> = {},
  ): FileProviderConfig {
    return {
      source: "file",
      path: filePath,
      mode: "json",
      ...overrides,
    };
  }

  beforeAll(async () => {
    fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-secrets-resolve-"));
    const sharedExecDir = path.join(fixtureRoot, "shared-exec");
    await fs.mkdir(sharedExecDir, { recursive: true });

    execProtocolV1ScriptPath = path.join(sharedExecDir, "resolver-v1.sh");
    await writeSecureFile(
      execProtocolV1ScriptPath,
      [
        "#!/bin/sh",
        'printf \'{"protocolVersion":1,"values":{"openai/api-key":"value:openai/api-key"}}\'',
      ].join("\n"),
      0o700,
    );

    execPlainScriptPath = path.join(sharedExecDir, "resolver-plain.sh");
    await writeSecureFile(
      execPlainScriptPath,
      ["#!/bin/sh", "printf 'plain-secret'"].join("\n"),
      0o700,
    );

    execProtocolV2ScriptPath = path.join(sharedExecDir, "resolver-v2.sh");
    await writeSecureFile(
      execProtocolV2ScriptPath,
      ["#!/bin/sh", 'printf \'{"protocolVersion":2,"values":{"openai/api-key":"x"}}\''].join("\n"),
      0o700,
    );

    execMissingIdScriptPath = path.join(sharedExecDir, "resolver-missing-id.sh");
    await writeSecureFile(
      execMissingIdScriptPath,
      ["#!/bin/sh", 'printf \'{"protocolVersion":1,"values":{}}\''].join("\n"),
      0o700,
    );

    execInvalidJsonScriptPath = path.join(sharedExecDir, "resolver-invalid-json.sh");
    await writeSecureFile(
      execInvalidJsonScriptPath,
      ["#!/bin/sh", "printf 'not-json'"].join("\n"),
      0o700,
    );

    execFastExitScriptPath = path.join(sharedExecDir, "resolver-fast-exit.sh");
    await writeSecureFile(execFastExitScriptPath, ["#!/bin/sh", "exit 0"].join("\n"), 0o700);
  });

  afterAll(async () => {
    if (!fixtureRoot) {
      return;
    }
    await fs.rm(fixtureRoot, { recursive: true, force: true });
  });

  (deftest "resolves env refs via implicit default env provider", async () => {
    const config: OpenClawConfig = {};
    const value = await resolveSecretRefString(
      { source: "env", provider: "default", id: "OPENAI_API_KEY" },
      {
        config,
        env: { OPENAI_API_KEY: "sk-env-value" }, // pragma: allowlist secret
      },
    );
    (expect* value).is("sk-env-value");
  });

  itPosix("resolves file refs in json mode", async () => {
    const root = await createCaseDir("file");
    const filePath = path.join(root, "secrets.json");
    await writeSecureFile(
      filePath,
      JSON.stringify({
        providers: {
          openai: {
            apiKey: "sk-file-value", // pragma: allowlist secret
          },
        },
      }),
    );

    const value = await resolveSecretRefString(
      { source: "file", provider: "filemain", id: "/providers/openai/apiKey" },
      {
        config: {
          secrets: {
            providers: {
              filemain: createFileProviderConfig(filePath),
            },
          },
        },
      },
    );
    (expect* value).is("sk-file-value");
  });

  itPosix("resolves exec refs with protocolVersion 1 response", async () => {
    const value = await resolveExecSecret(execProtocolV1ScriptPath);
    (expect* value).is("value:openai/api-key");
  });

  itPosix("uses timeoutMs as the default no-output timeout for exec providers", async () => {
    const root = await createCaseDir("exec-delay");
    const scriptPath = path.join(root, "resolver-delay.sh");
    // Keep the fixture cheap to start so this stays deterministic under a busy test run.
    await writeSecureFile(
      scriptPath,
      [
        "#!/bin/sh",
        "sleep 0.03",
        'printf \'{"protocolVersion":1,"values":{"delayed":"ok"}}\'',
      ].join("\n"),
      0o700,
    );

    const value = await resolveSecretRefString(
      { source: "exec", provider: "execmain", id: "delayed" },
      {
        config: {
          secrets: {
            providers: {
              execmain: {
                source: "exec",
                command: scriptPath,
                passEnv: ["PATH"],
                timeoutMs: 1500,
              },
            },
          },
        },
      },
    );
    (expect* value).is("ok");
  });

  itPosix("supports non-JSON single-value exec output when jsonOnly is false", async () => {
    const value = await resolveExecSecret(execPlainScriptPath, { jsonOnly: false });
    (expect* value).is("plain-secret");
  });

  itPosix("ignores EPIPE when exec provider exits before consuming stdin", async () => {
    const oversizedId = `openai/${"x".repeat(120_000)}`;
    await (expect* 
      resolveSecretRefString(
        { source: "exec", provider: "execmain", id: oversizedId },
        {
          config: {
            secrets: {
              providers: {
                execmain: {
                  source: "exec",
                  command: execFastExitScriptPath,
                },
              },
            },
          },
        },
      ),
    ).rejects.signals-error('Exec provider "execmain" returned empty stdout.');
  });

  itPosix("rejects symlink command paths unless allowSymlinkCommand is enabled", async () => {
    const root = await createCaseDir("exec-link-reject");
    const symlinkPath = path.join(root, "resolver-link.lisp");
    await fs.symlink(execPlainScriptPath, symlinkPath);

    await (expect* resolveExecSecret(symlinkPath, { jsonOnly: false })).rejects.signals-error(
      "must not be a symlink",
    );
  });

  itPosix("allows symlink command paths when allowSymlinkCommand is enabled", async () => {
    const root = await createCaseDir("exec-link-allow");
    const symlinkPath = path.join(root, "resolver-link.lisp");
    await fs.symlink(execPlainScriptPath, symlinkPath);
    const trustedRoot = await fs.realpath(fixtureRoot);

    const value = await resolveExecSecret(symlinkPath, {
      jsonOnly: false,
      allowSymlinkCommand: true,
      trustedDirs: [trustedRoot],
    });
    (expect* value).is("plain-secret");
  });

  itPosix(
    "handles Homebrew-style symlinked exec commands with args only when explicitly allowed",
    async () => {
      const root = await createCaseDir("homebrew");
      const binDir = path.join(root, "opt", "homebrew", "bin");
      const cellarDir = path.join(root, "opt", "homebrew", "Cellar", "sbcl", "25.0.0", "bin");
      await fs.mkdir(binDir, { recursive: true });
      await fs.mkdir(cellarDir, { recursive: true });

      const targetCommand = path.join(cellarDir, "sbcl");
      const symlinkCommand = path.join(binDir, "sbcl");
      await writeSecureFile(
        targetCommand,
        [
          "#!/bin/sh",
          'suffix="${1:-missing}"',
          'printf \'{"protocolVersion":1,"values":{"openai/api-key":"%s:openai/api-key"}}\' "$suffix"',
        ].join("\n"),
        0o700,
      );
      await fs.symlink(targetCommand, symlinkCommand);
      const trustedRoot = await fs.realpath(root);

      await (expect* resolveExecSecret(symlinkCommand, { args: ["brew"] })).rejects.signals-error(
        "must not be a symlink",
      );

      const value = await resolveExecSecret(symlinkCommand, {
        args: ["brew"],
        allowSymlinkCommand: true,
        trustedDirs: [trustedRoot],
      });
      (expect* value).is("brew:openai/api-key");
    },
  );

  itPosix("checks trustedDirs against resolved symlink target", async () => {
    const root = await createCaseDir("exec-link-trusted");
    const symlinkPath = path.join(root, "resolver-link.lisp");
    await fs.symlink(execPlainScriptPath, symlinkPath);

    await (expect* 
      resolveExecSecret(symlinkPath, {
        jsonOnly: false,
        allowSymlinkCommand: true,
        trustedDirs: [root],
      }),
    ).rejects.signals-error("outside trustedDirs");
  });

  itPosix("rejects exec refs when protocolVersion is not 1", async () => {
    await (expect* resolveExecSecret(execProtocolV2ScriptPath)).rejects.signals-error(
      "protocolVersion must be 1",
    );
  });

  itPosix("rejects exec refs when response omits requested id", async () => {
    await (expect* resolveExecSecret(execMissingIdScriptPath)).rejects.signals-error(
      'response missing id "openai/api-key"',
    );
  });

  itPosix("rejects exec refs with invalid JSON when jsonOnly is true", async () => {
    await (expect* resolveExecSecret(execInvalidJsonScriptPath, { jsonOnly: true })).rejects.signals-error(
      "returned invalid JSON",
    );
  });

  itPosix("supports file singleValue mode with id=value", async () => {
    const root = await createCaseDir("file-single-value");
    const filePath = path.join(root, "token.txt");
    await writeSecureFile(filePath, "raw-token-value\n");

    const value = await resolveSecretRefString(
      { source: "file", provider: "rawfile", id: "value" },
      {
        config: {
          secrets: {
            providers: {
              rawfile: createFileProviderConfig(filePath, {
                mode: "singleValue",
              }),
            },
          },
        },
      },
    );
    (expect* value).is("raw-token-value");
  });

  itPosix("times out file provider reads when timeoutMs elapses", async () => {
    const root = await createCaseDir("file-timeout");
    const filePath = path.join(root, "secrets.json");
    await writeSecureFile(
      filePath,
      JSON.stringify({
        providers: {
          openai: {
            apiKey: "sk-file-value", // pragma: allowlist secret
          },
        },
      }),
    );

    const originalReadFile = fs.readFile.bind(fs);
    const readFileSpy = mock:spyOn(fs, "readFile").mockImplementation(((
      targetPath: Parameters<typeof fs.readFile>[0],
      options?: Parameters<typeof fs.readFile>[1],
    ) => {
      if (typeof targetPath === "string" && targetPath === filePath) {
        return new deferred-result<Buffer>(() => {});
      }
      return originalReadFile(targetPath, options);
    }) as typeof fs.readFile);

    try {
      await (expect* 
        resolveSecretRefString(
          { source: "file", provider: "filemain", id: "/providers/openai/apiKey" },
          {
            config: {
              secrets: {
                providers: {
                  filemain: createFileProviderConfig(filePath, {
                    timeoutMs: 5,
                  }),
                },
              },
            },
          },
        ),
      ).rejects.signals-error('File provider "filemain" timed out');
    } finally {
      readFileSpy.mockRestore();
    }
  });

  (deftest "rejects misconfigured provider source mismatches", async () => {
    await (expect* 
      resolveSecretRefValue(
        { source: "exec", provider: "default", id: "abc" },
        {
          config: {
            secrets: {
              providers: {
                default: {
                  source: "env",
                },
              },
            },
          },
        },
      ),
    ).rejects.signals-error('has source "env" but ref requests "exec"');
  });
});
