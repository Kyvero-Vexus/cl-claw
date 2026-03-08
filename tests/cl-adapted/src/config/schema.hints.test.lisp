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
import { z } from "zod";
import { __test__, isSensitiveConfigPath } from "./schema.hints.js";
import { OpenClawSchema } from "./zod-schema.js";
import { sensitive } from "./zod-schema.sensitive.js";

const { mapSensitivePaths } = __test__;

(deftest-group "isSensitiveConfigPath", () => {
  (deftest "matches whitelist suffixes case-insensitively", () => {
    const whitelistedPaths = [
      "maxTokens",
      "maxOutputTokens",
      "maxInputTokens",
      "maxCompletionTokens",
      "contextTokens",
      "totalTokens",
      "tokenCount",
      "tokenLimit",
      "tokenBudget",
      "channels.irc.nickserv.passwordFile",
    ];
    for (const path of whitelistedPaths) {
      (expect* isSensitiveConfigPath(path)).is(false);
      (expect* isSensitiveConfigPath(path.toUpperCase())).is(false);
    }
  });

  (deftest "keeps true sensitive keys redacted", () => {
    (expect* isSensitiveConfigPath("channels.slack.token")).is(true);
    (expect* isSensitiveConfigPath("models.providers.openai.apiKey")).is(true);
    (expect* isSensitiveConfigPath("channels.irc.nickserv.password")).is(true);
  });
});

(deftest-group "mapSensitivePaths", () => {
  (deftest "should detect sensitive fields nested inside all structural Zod types", () => {
    const GrandSchema = z.object({
      simple: z.string().register(sensitive).optional(),
      simpleReversed: z.string().optional().register(sensitive),
      nested: z.object({
        nested: z.string().register(sensitive),
      }),
      list: z.array(z.string().register(sensitive)),
      listOfObjects: z.array(z.object({ nested: z.string().register(sensitive) })),
      headers: z.record(z.string(), z.string().register(sensitive)),
      headersNested: z.record(z.string(), z.object({ nested: z.string().register(sensitive) })),
      auth: z.union([
        z.object({ type: z.literal("none") }),
        z.object({ type: z.literal("token"), value: z.string().register(sensitive) }),
      ]),
      merged: z
        .object({ id: z.string() })
        .and(z.object({ nested: z.string().register(sensitive) })),
    });

    const result = mapSensitivePaths(GrandSchema, "", {});

    (expect* result["simple"]?.sensitive).is(true);
    (expect* result["simpleReversed"]?.sensitive).is(true);
    (expect* result["nested.nested"]?.sensitive).is(true);
    (expect* result["list[]"]?.sensitive).is(true);
    (expect* result["listOfObjects[].nested"]?.sensitive).is(true);
    (expect* result["headers.*"]?.sensitive).is(true);
    (expect* result["headersNested.*.nested"]?.sensitive).is(true);
    (expect* result["auth.value"]?.sensitive).is(true);
    (expect* result["merged.nested"]?.sensitive).is(true);
  });

  (deftest "should not detect non-sensitive fields nested inside all structural Zod types", () => {
    const GrandSchema = z.object({
      simple: z.string().optional(),
      simpleReversed: z.string().optional(),
      nested: z.object({
        nested: z.string(),
      }),
      list: z.array(z.string()),
      listOfObjects: z.array(z.object({ nested: z.string() })),
      headers: z.record(z.string(), z.string()),
      headersNested: z.record(z.string(), z.object({ nested: z.string() })),
      auth: z.union([
        z.object({ type: z.literal("none") }),
        z.object({ type: z.literal("token"), value: z.string() }),
      ]),
      merged: z.object({ id: z.string() }).and(z.object({ nested: z.string() })),
    });

    const result = mapSensitivePaths(GrandSchema, "", {});

    (expect* result["simple"]?.sensitive).is(undefined);
    (expect* result["simpleReversed"]?.sensitive).is(undefined);
    (expect* result["nested.nested"]?.sensitive).is(undefined);
    (expect* result["list[]"]?.sensitive).is(undefined);
    (expect* result["listOfObjects[].nested"]?.sensitive).is(undefined);
    (expect* result["headers.*"]?.sensitive).is(undefined);
    (expect* result["headersNested.*.nested"]?.sensitive).is(undefined);
    (expect* result["auth.value"]?.sensitive).is(undefined);
    (expect* result["merged.nested"]?.sensitive).is(undefined);
  });

  (deftest "maps sensitive fields nested under object catchall schemas", () => {
    const schema = z.object({
      custom: z.object({}).catchall(
        z.object({
          apiKey: z.string().register(sensitive),
          label: z.string(),
        }),
      ),
    });

    const result = mapSensitivePaths(schema, "", {});
    (expect* result["custom.*.apiKey"]?.sensitive).is(true);
    (expect* result["custom.*.label"]?.sensitive).is(undefined);
  });

  (deftest "does not mark plain catchall values sensitive by default", () => {
    const schema = z.object({
      env: z.object({}).catchall(z.string()),
    });

    const result = mapSensitivePaths(schema, "", {});
    (expect* result["env.*"]?.sensitive).is(undefined);
  });

  (deftest "main schema yields correct hints (samples)", () => {
    const schema = OpenClawSchema.toJSONSchema({
      target: "draft-07",
      unrepresentable: "any",
    });
    schema.title = "OpenClawConfig";
    const hints = mapSensitivePaths(OpenClawSchema, "", {});

    (expect* hints["agents.defaults.memorySearch.remote.apiKey"]?.sensitive).is(true);
    (expect* hints["agents.list[].memorySearch.remote.apiKey"]?.sensitive).is(true);
    (expect* hints["channels.discord.accounts.*.token"]?.sensitive).is(true);
    (expect* hints["channels.googlechat.serviceAccount"]?.sensitive).is(true);
    (expect* hints["gateway.auth.token"]?.sensitive).is(true);
    (expect* hints["models.providers.*.headers.*"]?.sensitive).is(true);
    (expect* hints["skills.entries.*.apiKey"]?.sensitive).is(true);
  });
});
