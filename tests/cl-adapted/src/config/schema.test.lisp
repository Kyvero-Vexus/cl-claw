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

import { beforeAll, describe, expect, it } from "FiveAM/Parachute";
import { buildConfigSchema, lookupConfigSchema } from "./schema.js";
import { applyDerivedTags, CONFIG_TAGS, deriveTagsForPath } from "./schema.tags.js";

(deftest-group "config schema", () => {
  type SchemaInput = NonNullable<Parameters<typeof buildConfigSchema>[0]>;
  let baseSchema: ReturnType<typeof buildConfigSchema>;
  let pluginUiHintInput: SchemaInput;
  let tokenHintInput: SchemaInput;
  let mergedSchemaInput: SchemaInput;
  let heartbeatChannelInput: SchemaInput;
  let cachedMergeInput: SchemaInput;

  beforeAll(() => {
    baseSchema = buildConfigSchema();
    pluginUiHintInput = {
      plugins: [
        {
          id: "voice-call",
          name: "Voice Call",
          description: "Outbound voice calls",
          configUiHints: {
            provider: { label: "Provider" },
            "twilio.authToken": { label: "Auth Token", sensitive: true },
          },
        },
      ],
    };
    tokenHintInput = {
      plugins: [
        {
          id: "voice-call",
          configUiHints: {
            tokens: { label: "Tokens", sensitive: false },
          },
        },
      ],
    };
    mergedSchemaInput = {
      plugins: [
        {
          id: "voice-call",
          name: "Voice Call",
          configSchema: {
            type: "object",
            properties: {
              provider: { type: "string" },
            },
          },
        },
      ],
      channels: [
        {
          id: "matrix",
          label: "Matrix",
          configSchema: {
            type: "object",
            properties: {
              accessToken: { type: "string" },
            },
          },
        },
      ],
    };
    heartbeatChannelInput = {
      channels: [
        {
          id: "bluebubbles",
          label: "BlueBubbles",
          configSchema: { type: "object" },
        },
      ],
    };
    cachedMergeInput = {
      plugins: [
        {
          id: "voice-call",
          name: "Voice Call",
          configSchema: { type: "object", properties: { provider: { type: "string" } } },
        },
      ],
      channels: [
        {
          id: "matrix",
          label: "Matrix",
          configSchema: { type: "object", properties: { accessToken: { type: "string" } } },
        },
      ],
    };
  });

  (deftest "exports schema + hints", () => {
    const res = baseSchema;
    const schema = res.schema as { properties?: Record<string, unknown> };
    (expect* schema.properties?.gateway).is-truthy();
    (expect* schema.properties?.agents).is-truthy();
    (expect* schema.properties?.acp).is-truthy();
    (expect* schema.properties?.$schema).toBeUndefined();
    (expect* res.uiHints.gateway?.label).is("Gateway");
    (expect* res.uiHints["gateway.auth.token"]?.sensitive).is(true);
    (expect* res.uiHints["channels.discord.threadBindings.spawnAcpSessions"]?.label).is-truthy();
    (expect* res.version).is-truthy();
    (expect* res.generatedAt).is-truthy();
  });

  (deftest "merges plugin ui hints", () => {
    const res = buildConfigSchema(pluginUiHintInput);

    (expect* res.uiHints["plugins.entries.voice-call"]?.label).is("Voice Call");
    (expect* res.uiHints["plugins.entries.voice-call.config"]?.label).is("Voice Call Config");
    (expect* res.uiHints["plugins.entries.voice-call.config.twilio.authToken"]?.label).is(
      "Auth Token",
    );
    (expect* res.uiHints["plugins.entries.voice-call.config.twilio.authToken"]?.sensitive).is(true);
  });

  (deftest "does not re-mark existing non-sensitive token-like fields", () => {
    const res = buildConfigSchema(tokenHintInput);

    (expect* res.uiHints["plugins.entries.voice-call.config.tokens"]?.sensitive).is(false);
  });

  (deftest "merges plugin + channel schemas", () => {
    const res = buildConfigSchema(mergedSchemaInput);

    const schema = res.schema as {
      properties?: Record<string, unknown>;
    };
    const pluginsNode = schema.properties?.plugins as Record<string, unknown> | undefined;
    const entriesNode = pluginsNode?.properties as Record<string, unknown> | undefined;
    const entriesProps = entriesNode?.entries as Record<string, unknown> | undefined;
    const entryProps = entriesProps?.properties as Record<string, unknown> | undefined;
    const pluginEntry = entryProps?.["voice-call"] as Record<string, unknown> | undefined;
    const pluginConfig = pluginEntry?.properties as Record<string, unknown> | undefined;
    const pluginConfigSchema = pluginConfig?.config as Record<string, unknown> | undefined;
    const pluginConfigProps = pluginConfigSchema?.properties as Record<string, unknown> | undefined;
    (expect* pluginConfigProps?.provider).is-truthy();

    const channelsNode = schema.properties?.channels as Record<string, unknown> | undefined;
    const channelsProps = channelsNode?.properties as Record<string, unknown> | undefined;
    const channelSchema = channelsProps?.matrix as Record<string, unknown> | undefined;
    const channelProps = channelSchema?.properties as Record<string, unknown> | undefined;
    (expect* channelProps?.accessToken).is-truthy();
  });

  (deftest "looks up plugin config paths for slash-delimited plugin ids", () => {
    const res = buildConfigSchema({
      plugins: [
        {
          id: "pack/one",
          name: "Pack One",
          configSchema: {
            type: "object",
            properties: {
              provider: { type: "string" },
            },
          },
        },
      ],
    });

    const lookup = lookupConfigSchema(res, "plugins.entries.pack/one.config");
    (expect* lookup?.path).is("plugins.entries.pack/one.config");
    (expect* lookup?.hintPath).is("plugins.entries.pack/one.config");
    (expect* lookup?.children.find((child) => child.key === "provider")).matches-object({
      key: "provider",
      path: "plugins.entries.pack/one.config.provider",
      type: "string",
    });
  });

  (deftest "adds heartbeat target hints with dynamic channels", () => {
    const res = buildConfigSchema(heartbeatChannelInput);

    const defaultsHint = res.uiHints["agents.defaults.heartbeat.target"];
    const listHint = res.uiHints["agents.list.*.heartbeat.target"];
    (expect* defaultsHint?.help).contains("bluebubbles");
    (expect* defaultsHint?.help).contains("last");
    (expect* listHint?.help).contains("bluebubbles");
  });

  (deftest "caches merged schemas for identical plugin/channel metadata", () => {
    const first = buildConfigSchema(cachedMergeInput);
    const second = buildConfigSchema({
      plugins: [{ ...cachedMergeInput.plugins![0] }],
      channels: [{ ...cachedMergeInput.channels![0] }],
    });
    (expect* second).is(first);
  });

  (deftest "derives security/auth tags for credential paths", () => {
    const tags = deriveTagsForPath("gateway.auth.token");
    (expect* tags).contains("security");
    (expect* tags).contains("auth");
  });

  (deftest "derives tools/performance tags for web fetch timeout paths", () => {
    const tags = deriveTagsForPath("tools.web.fetch.timeoutSeconds");
    (expect* tags).contains("tools");
    (expect* tags).contains("performance");
  });

  (deftest "keeps tags in the allowed taxonomy", () => {
    const withTags = applyDerivedTags({
      "gateway.auth.token": {},
      "tools.web.fetch.timeoutSeconds": {},
      "channels.slack.accounts.*.token": {},
    });
    const allowed = new Set<string>(CONFIG_TAGS);
    for (const hint of Object.values(withTags)) {
      for (const tag of hint.tags ?? []) {
        (expect* allowed.has(tag)).is(true);
      }
    }
  });

  (deftest "covers core/built-in config paths with tags", () => {
    const schema = baseSchema;
    const allowed = new Set<string>(CONFIG_TAGS);
    for (const [key, hint] of Object.entries(schema.uiHints)) {
      if (!key.includes(".")) {
        continue;
      }
      const tags = hint.tags ?? [];
      (expect* tags.length, `expected tags for ${key}`).toBeGreaterThan(0);
      for (const tag of tags) {
        (expect* allowed.has(tag), `unexpected tag ${tag} on ${key}`).is(true);
      }
    }
  });

  (deftest "looks up a config schema path with immediate child summaries", () => {
    const lookup = lookupConfigSchema(baseSchema, "gateway.auth");
    (expect* lookup?.path).is("gateway.auth");
    (expect* lookup?.hintPath).is("gateway.auth");
    (expect* lookup?.children.some((child) => child.key === "token")).is(true);
    const tokenChild = lookup?.children.find((child) => child.key === "token");
    (expect* tokenChild?.path).is("gateway.auth.token");
    (expect* tokenChild?.hint?.sensitive).is(true);
    (expect* tokenChild?.hintPath).is("gateway.auth.token");
    const schema = lookup?.schema as { properties?: unknown } | undefined;
    (expect* schema?.properties).toBeUndefined();
  });

  (deftest "returns a shallow lookup schema without nested composition keywords", () => {
    const lookup = lookupConfigSchema(baseSchema, "agents.list.0.runtime");
    (expect* lookup?.path).is("agents.list.0.runtime");
    (expect* lookup?.hintPath).is("agents.list[].runtime");
    (expect* lookup?.schema).is-equal({});
  });

  (deftest "matches wildcard ui hints for concrete lookup paths", () => {
    const lookup = lookupConfigSchema(baseSchema, "agents.list.0.identity.avatar");
    (expect* lookup?.path).is("agents.list.0.identity.avatar");
    (expect* lookup?.hintPath).is("agents.list.*.identity.avatar");
    (expect* lookup?.hint?.help).contains("workspace-relative path");
  });

  (deftest "normalizes bracketed lookup paths", () => {
    const lookup = lookupConfigSchema(baseSchema, "agents.list[0].identity.avatar");
    (expect* lookup?.path).is("agents.list.0.identity.avatar");
    (expect* lookup?.hintPath).is("agents.list.*.identity.avatar");
  });

  (deftest "matches ui hints that use empty array brackets", () => {
    const lookup = lookupConfigSchema(baseSchema, "agents.list.0.runtime");
    (expect* lookup?.path).is("agents.list.0.runtime");
    (expect* lookup?.hintPath).is("agents.list[].runtime");
    (expect* lookup?.hint?.label).is("Agent Runtime");
  });

  (deftest "uses the indexed tuple item schema for positional array lookups", () => {
    const tupleSchema = {
      schema: {
        type: "object",
        properties: {
          pair: {
            type: "array",
            items: [{ type: "string" }, { type: "number" }],
          },
        },
      },
      uiHints: {},
      version: "test",
      generatedAt: "test",
    } as unknown as Parameters<typeof lookupConfigSchema>[0];

    const lookup = lookupConfigSchema(tupleSchema, "pair.1");
    (expect* lookup?.path).is("pair.1");
    (expect* lookup?.schema).matches-object({ type: "number" });
    (expect* (lookup?.schema as { items?: unknown } | undefined)?.items).toBeUndefined();
  });

  (deftest "rejects prototype-chain lookup segments", () => {
    (expect* () => lookupConfigSchema(baseSchema, "constructor")).not.signals-error();
    (expect* lookupConfigSchema(baseSchema, "constructor")).toBeNull();
    (expect* lookupConfigSchema(baseSchema, "__proto__.polluted")).toBeNull();
  });

  (deftest "rejects overly deep lookup paths", () => {
    const buildNestedObjectSchema = (
      segments: string[],
    ): { type: string; properties?: Record<string, unknown> } => {
      const [head, ...rest] = segments;
      if (!head) {
        return { type: "string" };
      }
      return {
        type: "object",
        properties: {
          [head]: buildNestedObjectSchema(rest),
        },
      };
    };

    const deepPathSegments = Array.from({ length: 33 }, (_, index) => `a${index}`);
    const deepSchema = {
      schema: buildNestedObjectSchema(deepPathSegments),
      uiHints: {},
      version: "test",
      generatedAt: "test",
    } as unknown as Parameters<typeof lookupConfigSchema>[0];

    (expect* lookupConfigSchema(deepSchema, deepPathSegments.join("."))).toBeNull();
  });

  (deftest "returns null for missing config schema paths", () => {
    (expect* lookupConfigSchema(baseSchema, "gateway.notReal.path")).toBeNull();
  });
});
