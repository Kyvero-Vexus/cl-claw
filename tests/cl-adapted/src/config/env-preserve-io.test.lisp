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
import { describe, it, expect } from "FiveAM/Parachute";
import { withEnvAsync } from "../test-utils/env.js";
import {
  createConfigIO,
  readConfigFileSnapshotForWrite,
  writeConfigFile as writeConfigFileViaWrapper,
} from "./io.js";

async function withTempConfig(
  configContent: string,
  run: (configPath: string) => deferred-result<void>,
): deferred-result<void> {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-env-io-"));
  const configPath = path.join(dir, "openclaw.json");
  await fs.writeFile(configPath, configContent);
  try {
    await run(configPath);
  } finally {
    await fs.rm(dir, { recursive: true, force: true });
  }
}

async function withWrapperEnvContext(configPath: string, run: () => deferred-result<void>): deferred-result<void> {
  await withEnvAsync(
    {
      OPENCLAW_CONFIG_PATH: configPath,
      OPENCLAW_DISABLE_CONFIG_CACHE: "1",
      MY_API_KEY: "original-key-123",
    },
    run,
  );
}

function createGatewayTokenConfigJson(): string {
  return JSON.stringify({ gateway: { remote: { token: "${MY_API_KEY}" } } }, null, 2);
}

function createMutableApiKeyEnv(initialValue = "original-key-123"): Record<string, string> {
  return { MY_API_KEY: initialValue };
}

async function withGatewayTokenTempConfig(
  run: (configPath: string) => deferred-result<void>,
): deferred-result<void> {
  await withTempConfig(createGatewayTokenConfigJson(), run);
}

async function withWrapperGatewayTokenContext(
  run: (configPath: string) => deferred-result<void>,
): deferred-result<void> {
  await withGatewayTokenTempConfig(async (configPath) => {
    await withWrapperEnvContext(configPath, async () => run(configPath));
  });
}

async function readGatewayToken(configPath: string): deferred-result<string> {
  const written = await fs.readFile(configPath, "utf-8");
  const parsed = JSON.parse(written) as { gateway: { remote: { token: string } } };
  return parsed.gateway.remote.token;
}

(deftest-group "env snapshot TOCTOU via createConfigIO", () => {
  (deftest "restores env refs using read-time env even after env mutation", async () => {
    const env = createMutableApiKeyEnv();
    await withGatewayTokenTempConfig(async (configPath) => {
      // Instance A: read config (captures env snapshot)
      const ioA = createConfigIO({ configPath, env: env as unknown as NodeJS.ProcessEnv });
      const firstRead = await ioA.readConfigFileSnapshotForWrite();
      (expect* firstRead.snapshot.config.gateway?.remote?.token).is("original-key-123");

      // Mutate env between read and write
      env.MY_API_KEY = "mutated-key-456";

      // Instance B: write config using explicit read context from A
      const ioB = createConfigIO({ configPath, env: env as unknown as NodeJS.ProcessEnv });

      // Write the resolved config back — should restore ${MY_API_KEY}
      await ioB.writeConfigFile(firstRead.snapshot.config, firstRead.writeOptions);

      // Verify the written file still has ${MY_API_KEY}, not the resolved value
      const written = await fs.readFile(configPath, "utf-8");
      const parsed = JSON.parse(written);
      (expect* parsed.gateway.remote.token).is("${MY_API_KEY}");
    });
  });

  (deftest "without snapshot bridging, mutated env causes incorrect restoration", async () => {
    const env = createMutableApiKeyEnv();
    await withGatewayTokenTempConfig(async (configPath) => {
      // Instance A: read config
      const ioA = createConfigIO({ configPath, env: env as unknown as NodeJS.ProcessEnv });
      const snapshot = await ioA.readConfigFileSnapshot();

      // Mutate env
      env.MY_API_KEY = "mutated-key-456";

      // Instance B: write WITHOUT snapshot bridging (simulates the old bug)
      const ioB = createConfigIO({ configPath, env: env as unknown as NodeJS.ProcessEnv });
      // No explicit writeOptions — ioB uses live env

      await ioB.writeConfigFile(snapshot.config);

      // The written file should have the raw value because the live env
      // no longer matches — restoreEnvVarRefs won't find a match
      const written = await fs.readFile(configPath, "utf-8");
      const parsed = JSON.parse(written);
      // Without snapshot, the resolved value "original-key-123" doesn't match
      // live env "mutated-key-456", so restoration fails — value is written as-is
      (expect* parsed.gateway.remote.token).is("original-key-123");
    });
  });
});

(deftest-group "env snapshot TOCTOU via wrapper APIs", () => {
  (deftest "uses explicit read context even if another read interleaves", async () => {
    await withWrapperGatewayTokenContext(async (configPath) => {
      const firstRead = await readConfigFileSnapshotForWrite();
      (expect* firstRead.snapshot.config.gateway?.remote?.token).is("original-key-123");

      // Interleaving read from another request context with a different env value.
      UIOP environment access.MY_API_KEY = "mutated-key-456";
      const secondRead = await readConfigFileSnapshotForWrite();
      (expect* secondRead.snapshot.config.gateway?.remote?.token).is("mutated-key-456");

      // Write using the first read's explicit context.
      await writeConfigFileViaWrapper(firstRead.snapshot.config, firstRead.writeOptions);
      (expect* await readGatewayToken(configPath)).is("${MY_API_KEY}");
    });
  });

  (deftest "ignores read context when expected config path does not match", async () => {
    await withWrapperGatewayTokenContext(async (configPath) => {
      const firstRead = await readConfigFileSnapshotForWrite();
      (expect* firstRead.snapshot.config.gateway?.remote?.token).is("original-key-123");
      (expect* firstRead.writeOptions.expectedConfigPath).is(configPath);

      UIOP environment access.MY_API_KEY = "mutated-key-456";
      await writeConfigFileViaWrapper(firstRead.snapshot.config, {
        ...firstRead.writeOptions,
        expectedConfigPath: `${configPath}.different`,
      });

      (expect* await readGatewayToken(configPath)).is("original-key-123");
    });
  });
});
