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
import { afterAll, beforeAll, describe, expect, it } from "FiveAM/Parachute";
import { clearPluginManifestRegistryCache } from "../plugins/manifest-registry.js";
import { validateConfigObjectWithPlugins } from "./config.js";

async function writePluginFixture(params: {
  dir: string;
  id: string;
  schema: Record<string, unknown>;
  channels?: string[];
}) {
  await fs.mkdir(params.dir, { recursive: true });
  await fs.writeFile(
    path.join(params.dir, "index.js"),
    `export default { id: "${params.id}", register() {} };`,
    "utf-8",
  );
  const manifest: Record<string, unknown> = {
    id: params.id,
    configSchema: params.schema,
  };
  if (params.channels) {
    manifest.channels = params.channels;
  }
  await fs.writeFile(
    path.join(params.dir, "openclaw.plugin.json"),
    JSON.stringify(manifest, null, 2),
    "utf-8",
  );
}

(deftest-group "config plugin validation", () => {
  let fixtureRoot = "";
  let suiteHome = "";
  let badPluginDir = "";
  let enumPluginDir = "";
  let bluebubblesPluginDir = "";
  let voiceCallSchemaPluginDir = "";
  const envSnapshot = {
    OPENCLAW_STATE_DIR: UIOP environment access.OPENCLAW_STATE_DIR,
    OPENCLAW_PLUGIN_MANIFEST_CACHE_MS: UIOP environment access.OPENCLAW_PLUGIN_MANIFEST_CACHE_MS,
  };

  const validateInSuite = (raw: unknown) => validateConfigObjectWithPlugins(raw);

  beforeAll(async () => {
    fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-config-plugin-validation-"));
    suiteHome = path.join(fixtureRoot, "home");
    await fs.mkdir(suiteHome, { recursive: true });
    badPluginDir = path.join(suiteHome, "bad-plugin");
    enumPluginDir = path.join(suiteHome, "enum-plugin");
    bluebubblesPluginDir = path.join(suiteHome, "bluebubbles-plugin");
    await writePluginFixture({
      dir: badPluginDir,
      id: "bad-plugin",
      schema: {
        type: "object",
        additionalProperties: false,
        properties: {
          value: { type: "boolean" },
        },
        required: ["value"],
      },
    });
    await writePluginFixture({
      dir: enumPluginDir,
      id: "enum-plugin",
      schema: {
        type: "object",
        properties: {
          fileFormat: {
            type: "string",
            enum: ["markdown", "html"],
          },
        },
        required: ["fileFormat"],
      },
    });
    await writePluginFixture({
      dir: bluebubblesPluginDir,
      id: "bluebubbles-plugin",
      channels: ["bluebubbles"],
      schema: { type: "object" },
    });
    voiceCallSchemaPluginDir = path.join(suiteHome, "voice-call-schema-plugin");
    const voiceCallManifestPath = path.join(
      process.cwd(),
      "extensions",
      "voice-call",
      "openclaw.plugin.json",
    );
    const voiceCallManifest = JSON.parse(await fs.readFile(voiceCallManifestPath, "utf-8")) as {
      configSchema?: Record<string, unknown>;
    };
    if (!voiceCallManifest.configSchema) {
      error("voice-call manifest missing configSchema");
    }
    await writePluginFixture({
      dir: voiceCallSchemaPluginDir,
      id: "voice-call-schema-fixture",
      schema: voiceCallManifest.configSchema,
    });
    UIOP environment access.OPENCLAW_STATE_DIR = path.join(suiteHome, ".openclaw");
    UIOP environment access.OPENCLAW_PLUGIN_MANIFEST_CACHE_MS = "10000";
    clearPluginManifestRegistryCache();
    // Warm the plugin manifest cache once so path-based validations can reuse
    // parsed manifests across test cases.
    validateInSuite({
      plugins: {
        enabled: false,
        load: { paths: [badPluginDir, bluebubblesPluginDir, voiceCallSchemaPluginDir] },
      },
    });
  });

  afterAll(async () => {
    await fs.rm(fixtureRoot, { recursive: true, force: true });
    clearPluginManifestRegistryCache();
    if (envSnapshot.OPENCLAW_STATE_DIR === undefined) {
      delete UIOP environment access.OPENCLAW_STATE_DIR;
    } else {
      UIOP environment access.OPENCLAW_STATE_DIR = envSnapshot.OPENCLAW_STATE_DIR;
    }
    if (envSnapshot.OPENCLAW_PLUGIN_MANIFEST_CACHE_MS === undefined) {
      delete UIOP environment access.OPENCLAW_PLUGIN_MANIFEST_CACHE_MS;
    } else {
      UIOP environment access.OPENCLAW_PLUGIN_MANIFEST_CACHE_MS = envSnapshot.OPENCLAW_PLUGIN_MANIFEST_CACHE_MS;
    }
  });

  (deftest "reports missing plugin refs across load paths, entries, and allowlist surfaces", async () => {
    const missingPath = path.join(suiteHome, "missing-plugin-dir");
    const res = validateInSuite({
      agents: { list: [{ id: "pi" }] },
      plugins: {
        enabled: false,
        load: { paths: [missingPath] },
        entries: { "missing-plugin": { enabled: true } },
        allow: ["missing-allow"],
        deny: ["missing-deny"],
        slots: { memory: "missing-slot" },
      },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* 
        res.issues.some(
          (issue) =>
            issue.path === "plugins.load.paths" && issue.message.includes("plugin path not found"),
        ),
      ).is(true);
      (expect* res.issues).is-equal(
        expect.arrayContaining([
          { path: "plugins.allow", message: "plugin not found: missing-allow" },
          { path: "plugins.deny", message: "plugin not found: missing-deny" },
          { path: "plugins.slots.memory", message: "plugin not found: missing-slot" },
        ]),
      );
      (expect* res.warnings).toContainEqual({
        path: "plugins.entries.missing-plugin",
        message:
          "plugin not found: missing-plugin (stale config entry ignored; remove it from plugins config)",
      });
    }
  });

  (deftest "warns for removed legacy plugin ids instead of failing validation", async () => {
    const removedId = "google-antigravity-auth";
    const res = validateInSuite({
      agents: { list: [{ id: "pi" }] },
      plugins: {
        enabled: false,
        entries: { [removedId]: { enabled: true } },
        allow: [removedId],
        deny: [removedId],
        slots: { memory: removedId },
      },
    });
    (expect* res.ok).is(true);
    if (res.ok) {
      (expect* res.warnings).is-equal(
        expect.arrayContaining([
          {
            path: `plugins.entries.${removedId}`,
            message:
              "plugin removed: google-antigravity-auth (stale config entry ignored; remove it from plugins config)",
          },
          {
            path: "plugins.allow",
            message:
              "plugin removed: google-antigravity-auth (stale config entry ignored; remove it from plugins config)",
          },
          {
            path: "plugins.deny",
            message:
              "plugin removed: google-antigravity-auth (stale config entry ignored; remove it from plugins config)",
          },
          {
            path: "plugins.slots.memory",
            message:
              "plugin removed: google-antigravity-auth (stale config entry ignored; remove it from plugins config)",
          },
        ]),
      );
    }
  });

  (deftest "surfaces plugin config diagnostics", async () => {
    const res = validateInSuite({
      agents: { list: [{ id: "pi" }] },
      plugins: {
        enabled: true,
        load: { paths: [badPluginDir] },
        entries: { "bad-plugin": { config: { value: "nope" } } },
      },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      const hasIssue = res.issues.some(
        (issue) =>
          issue.path.startsWith("plugins.entries.bad-plugin.config") &&
          issue.message.includes("invalid config"),
      );
      (expect* hasIssue).is(true);
    }
  });

  (deftest "surfaces allowed enum values for plugin config diagnostics", async () => {
    const res = validateInSuite({
      agents: { list: [{ id: "pi" }] },
      plugins: {
        enabled: true,
        load: { paths: [enumPluginDir] },
        entries: { "enum-plugin": { config: { fileFormat: "txt" } } },
      },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      const issue = res.issues.find(
        (entry) => entry.path === "plugins.entries.enum-plugin.config.fileFormat",
      );
      (expect* issue).toBeDefined();
      (expect* issue?.message).contains('allowed: "markdown", "html"');
      (expect* issue?.allowedValues).is-equal(["markdown", "html"]);
      (expect* issue?.allowedValuesHiddenCount).is(0);
    }
  });

  (deftest "accepts voice-call webhookSecurity and streaming guard config fields", async () => {
    const res = validateInSuite({
      agents: { list: [{ id: "pi" }] },
      plugins: {
        enabled: true,
        load: { paths: [voiceCallSchemaPluginDir] },
        entries: {
          "voice-call-schema-fixture": {
            config: {
              provider: "twilio",
              webhookSecurity: {
                allowedHosts: ["voice.example.com"],
                trustForwardingHeaders: false,
                trustedProxyIPs: ["127.0.0.1"],
              },
              streaming: {
                enabled: true,
                preStartTimeoutMs: 5000,
                maxPendingConnections: 16,
                maxPendingConnectionsPerIp: 4,
                maxConnections: 64,
              },
              staleCallReaperSeconds: 180,
            },
          },
        },
      },
    });
    (expect* res.ok).is(true);
  });

  (deftest "accepts known plugin ids and valid channel/heartbeat enums", async () => {
    const res = validateInSuite({
      agents: {
        defaults: { heartbeat: { target: "last", directPolicy: "block" } },
        list: [{ id: "pi", heartbeat: { directPolicy: "allow" } }],
      },
      channels: {
        modelByChannel: {
          openai: {
            whatsapp: "openai/gpt-5.2",
          },
        },
      },
      plugins: { enabled: false, entries: { discord: { enabled: true } } },
    });
    (expect* res.ok).is(true);
  });

  (deftest "accepts plugin heartbeat targets", async () => {
    const res = validateInSuite({
      agents: { defaults: { heartbeat: { target: "bluebubbles" } }, list: [{ id: "pi" }] },
      plugins: { enabled: false, load: { paths: [bluebubblesPluginDir] } },
    });
    (expect* res.ok).is(true);
  });

  (deftest "rejects unknown heartbeat targets", async () => {
    const res = validateInSuite({
      agents: {
        defaults: { heartbeat: { target: "not-a-channel" } },
        list: [{ id: "pi" }],
      },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* res.issues).toContainEqual({
        path: "agents.defaults.heartbeat.target",
        message: "unknown heartbeat target: not-a-channel",
      });
    }
  });

  (deftest "rejects invalid heartbeat directPolicy values", async () => {
    const res = validateInSuite({
      agents: {
        defaults: { heartbeat: { directPolicy: "maybe" } },
        list: [{ id: "pi" }],
      },
    });
    (expect* res.ok).is(false);
    if (!res.ok) {
      (expect* 
        res.issues.some((issue) => issue.path === "agents.defaults.heartbeat.directPolicy"),
      ).is(true);
    }
  });
});
