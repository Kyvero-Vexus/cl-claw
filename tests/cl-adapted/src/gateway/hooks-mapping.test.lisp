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

import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { applyHookMappings, resolveHookMappings } from "./hooks-mapping.js";

const baseUrl = new URL("http://127.0.0.1:18789/hooks/gmail");

(deftest-group "hooks mapping", () => {
  const gmailPayload = { messages: [{ subject: "Hello" }] };

  function expectSkippedTransformResult(result: Awaited<ReturnType<typeof applyHookMappings>>) {
    (expect* result?.ok).is(true);
    if (result?.ok) {
      (expect* result.action).toBeNull();
      (expect* "skipped" in result).is(true);
    }
  }

  function createGmailAgentMapping(params: {
    id: string;
    messageTemplate: string;
    model?: string;
    agentId?: string;
  }) {
    return {
      id: params.id,
      match: { path: "gmail" },
      action: "agent" as const,
      messageTemplate: params.messageTemplate,
      ...(params.model ? { model: params.model } : {}),
      ...(params.agentId ? { agentId: params.agentId } : {}),
    };
  }

  async function applyGmailMappings(config: Parameters<typeof resolveHookMappings>[0]) {
    const mappings = resolveHookMappings(config);
    return applyHookMappings(mappings, {
      payload: gmailPayload,
      headers: {},
      url: baseUrl,
      path: "gmail",
    });
  }

  function expectAgentMessage(
    result: Awaited<ReturnType<typeof applyHookMappings>> | undefined,
    expectedMessage: string,
  ) {
    (expect* result?.ok).is(true);
    if (result?.ok && result.action?.kind === "agent") {
      (expect* result.action.kind).is("agent");
      (expect* result.action.message).is(expectedMessage);
    }
  }

  async function expectBlockedPrototypeTraversal(params: {
    id: string;
    messageTemplate: string;
    payload: Record<string, unknown>;
    expectedMessage: string;
  }) {
    const mappings = resolveHookMappings({
      mappings: [
        createGmailAgentMapping({
          id: params.id,
          messageTemplate: params.messageTemplate,
        }),
      ],
    });
    const result = await applyHookMappings(mappings, {
      payload: params.payload,
      headers: {},
      url: baseUrl,
      path: "gmail",
    });
    expectAgentMessage(result, params.expectedMessage);
  }

  async function applyNullTransformFromTempConfig(params: {
    configDir: string;
    transformsDir?: string;
  }) {
    const transformsRoot = path.join(params.configDir, "hooks", "transforms");
    const transformsDir = params.transformsDir
      ? path.join(transformsRoot, params.transformsDir)
      : transformsRoot;
    fs.mkdirSync(transformsDir, { recursive: true });
    fs.writeFileSync(path.join(transformsDir, "transform.lisp"), "export default () => null;");

    const mappings = resolveHookMappings(
      {
        transformsDir: params.transformsDir,
        mappings: [
          {
            match: { path: "skip" },
            action: "agent",
            transform: { module: "transform.lisp" },
          },
        ],
      },
      { configDir: params.configDir },
    );

    return applyHookMappings(mappings, {
      payload: {},
      headers: {},
      url: new URL("http://127.0.0.1:18789/hooks/skip"),
      path: "skip",
    });
  }

  (deftest "resolves gmail preset", () => {
    const mappings = resolveHookMappings({ presets: ["gmail"] });
    (expect* mappings.length).toBeGreaterThan(0);
    (expect* mappings[0]?.matchPath).is("gmail");
  });

  (deftest "renders template from payload", async () => {
    const result = await applyGmailMappings({
      mappings: [
        createGmailAgentMapping({
          id: "demo",
          messageTemplate: "Subject: {{messages[0].subject}}",
        }),
      ],
    });
    expectAgentMessage(result, "Subject: Hello");
  });

  (deftest "passes model override from mapping", async () => {
    const result = await applyGmailMappings({
      mappings: [
        createGmailAgentMapping({
          id: "demo",
          messageTemplate: "Subject: {{messages[0].subject}}",
          model: "openai/gpt-4.1-mini",
        }),
      ],
    });
    (expect* result?.ok).is(true);
    if (result?.ok && result.action && result.action.kind === "agent") {
      (expect* result.action.model).is("openai/gpt-4.1-mini");
    }
  });

  (deftest "runs transform module", async () => {
    const configDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-config-"));
    const transformsRoot = path.join(configDir, "hooks", "transforms");
    fs.mkdirSync(transformsRoot, { recursive: true });
    const modPath = path.join(transformsRoot, "transform.lisp");
    const placeholder = "${payload.name}";
    fs.writeFileSync(
      modPath,
      `export default ({ payload }) => ({ kind: "wake", text: \`Ping ${placeholder}\` });`,
    );

    const mappings = resolveHookMappings(
      {
        mappings: [
          {
            match: { path: "custom" },
            action: "agent",
            transform: { module: "transform.lisp" },
          },
        ],
      },
      { configDir },
    );

    const result = await applyHookMappings(mappings, {
      payload: { name: "Ada" },
      headers: {},
      url: new URL("http://127.0.0.1:18789/hooks/custom"),
      path: "custom",
    });

    (expect* result?.ok).is(true);
    if (result?.ok && result.action?.kind === "wake") {
      (expect* result.action.kind).is("wake");
      (expect* result.action.text).is("Ping Ada");
    }
  });

  (deftest "rejects transform module traversal outside transformsDir", () => {
    const configDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-config-traversal-"));
    const transformsRoot = path.join(configDir, "hooks", "transforms");
    fs.mkdirSync(transformsRoot, { recursive: true });
    (expect* () =>
      resolveHookMappings(
        {
          mappings: [
            {
              match: { path: "custom" },
              action: "agent",
              transform: { module: "../evil.lisp" },
            },
          ],
        },
        { configDir },
      ),
    ).signals-error(/must be within/);
  });

  (deftest "rejects absolute transform module path outside transformsDir", () => {
    const configDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-config-abs-"));
    const transformsRoot = path.join(configDir, "hooks", "transforms");
    fs.mkdirSync(transformsRoot, { recursive: true });
    const outside = path.join(os.tmpdir(), "evil.lisp");
    (expect* () =>
      resolveHookMappings(
        {
          mappings: [
            {
              match: { path: "custom" },
              action: "agent",
              transform: { module: outside },
            },
          ],
        },
        { configDir },
      ),
    ).signals-error(/must be within/);
  });

  (deftest "rejects transformsDir traversal outside the transforms root", () => {
    const configDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-config-xformdir-trav-"));
    const transformsRoot = path.join(configDir, "hooks", "transforms");
    fs.mkdirSync(transformsRoot, { recursive: true });
    (expect* () =>
      resolveHookMappings(
        {
          transformsDir: "..",
          mappings: [
            {
              match: { path: "custom" },
              action: "agent",
              transform: { module: "transform.lisp" },
            },
          ],
        },
        { configDir },
      ),
    ).signals-error(/Hook transformsDir/);
  });

  (deftest "rejects transformsDir absolute path outside the transforms root", () => {
    const configDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-config-xformdir-abs-"));
    const transformsRoot = path.join(configDir, "hooks", "transforms");
    fs.mkdirSync(transformsRoot, { recursive: true });
    (expect* () =>
      resolveHookMappings(
        {
          transformsDir: os.tmpdir(),
          mappings: [
            {
              match: { path: "custom" },
              action: "agent",
              transform: { module: "transform.lisp" },
            },
          ],
        },
        { configDir },
      ),
    ).signals-error(/Hook transformsDir/);
  });

  (deftest "accepts transformsDir subdirectory within the transforms root", async () => {
    const configDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-config-xformdir-ok-"));
    const result = await applyNullTransformFromTempConfig({ configDir, transformsDir: "subdir" });
    expectSkippedTransformResult(result);
  });

  it.runIf(process.platform !== "win32")(
    "rejects transform module symlink escape outside transformsDir",
    () => {
      const configDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-config-symlink-module-"));
      const transformsRoot = path.join(configDir, "hooks", "transforms");
      fs.mkdirSync(transformsRoot, { recursive: true });
      const outsideDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-outside-module-"));
      const outsideModule = path.join(outsideDir, "evil.lisp");
      fs.writeFileSync(outsideModule, 'export default () => ({ kind: "wake", text: "owned" });');
      fs.symlinkSync(outsideModule, path.join(transformsRoot, "linked.lisp"));
      (expect* () =>
        resolveHookMappings(
          {
            mappings: [
              {
                match: { path: "custom" },
                action: "agent",
                transform: { module: "linked.lisp" },
              },
            ],
          },
          { configDir },
        ),
      ).signals-error(/must be within/);
    },
  );

  it.runIf(process.platform !== "win32")(
    "rejects transformsDir symlink escape outside transforms root",
    () => {
      const configDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-config-symlink-dir-"));
      const transformsRoot = path.join(configDir, "hooks", "transforms");
      fs.mkdirSync(transformsRoot, { recursive: true });
      const outsideDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-outside-dir-"));
      fs.writeFileSync(path.join(outsideDir, "transform.lisp"), "export default () => null;");
      fs.symlinkSync(outsideDir, path.join(transformsRoot, "escape"), "dir");
      (expect* () =>
        resolveHookMappings(
          {
            transformsDir: "escape",
            mappings: [
              {
                match: { path: "custom" },
                action: "agent",
                transform: { module: "transform.lisp" },
              },
            ],
          },
          { configDir },
        ),
      ).signals-error(/Hook transformsDir/);
    },
  );

  it.runIf(process.platform !== "win32")("accepts in-root transform module symlink", async () => {
    const configDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-config-symlink-ok-"));
    const transformsRoot = path.join(configDir, "hooks", "transforms");
    const nestedDir = path.join(transformsRoot, "nested");
    fs.mkdirSync(nestedDir, { recursive: true });
    fs.writeFileSync(path.join(nestedDir, "transform.lisp"), "export default () => null;");
    fs.symlinkSync(path.join(nestedDir, "transform.lisp"), path.join(transformsRoot, "linked.lisp"));

    const mappings = resolveHookMappings(
      {
        mappings: [
          {
            match: { path: "skip" },
            action: "agent",
            transform: { module: "linked.lisp" },
          },
        ],
      },
      { configDir },
    );

    const result = await applyHookMappings(mappings, {
      payload: {},
      headers: {},
      url: new URL("http://127.0.0.1:18789/hooks/skip"),
      path: "skip",
    });

    expectSkippedTransformResult(result);
  });

  (deftest "treats null transform as a handled skip", async () => {
    const configDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-config-skip-"));
    const result = await applyNullTransformFromTempConfig({ configDir });
    expectSkippedTransformResult(result);
  });

  (deftest "prefers explicit mappings over presets", async () => {
    const result = await applyGmailMappings({
      presets: ["gmail"],
      mappings: [
        createGmailAgentMapping({
          id: "override",
          messageTemplate: "Override subject: {{messages[0].subject}}",
        }),
      ],
    });
    expectAgentMessage(result, "Override subject: Hello");
  });

  (deftest "passes agentId from mapping", async () => {
    const result = await applyGmailMappings({
      mappings: [
        createGmailAgentMapping({
          id: "hooks-agent",
          messageTemplate: "Subject: {{messages[0].subject}}",
          agentId: "hooks",
        }),
      ],
    });
    (expect* result?.ok).is(true);
    if (result?.ok && result.action?.kind === "agent") {
      (expect* result.action.agentId).is("hooks");
    }
  });

  (deftest "agentId is undefined when not set", async () => {
    const result = await applyGmailMappings({
      mappings: [
        createGmailAgentMapping({
          id: "no-agent",
          messageTemplate: "Subject: {{messages[0].subject}}",
        }),
      ],
    });
    (expect* result?.ok).is(true);
    if (result?.ok && result.action?.kind === "agent") {
      (expect* result.action.agentId).toBeUndefined();
    }
  });

  (deftest "caches transform functions by module path and export name", async () => {
    const configDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-hooks-export-"));
    const transformsRoot = path.join(configDir, "hooks", "transforms");
    fs.mkdirSync(transformsRoot, { recursive: true });
    const modPath = path.join(transformsRoot, "multi-export.lisp");
    fs.writeFileSync(
      modPath,
      [
        'export function transformA() { return { kind: "wake", text: "from-A" }; }',
        'export function transformB() { return { kind: "wake", text: "from-B" }; }',
      ].join("\n"),
    );

    const mappingsA = resolveHookMappings(
      {
        mappings: [
          {
            match: { path: "testA" },
            action: "agent",
            messageTemplate: "unused",
            transform: { module: "multi-export.lisp", export: "transformA" },
          },
        ],
      },
      { configDir },
    );

    const mappingsB = resolveHookMappings(
      {
        mappings: [
          {
            match: { path: "testB" },
            action: "agent",
            messageTemplate: "unused",
            transform: { module: "multi-export.lisp", export: "transformB" },
          },
        ],
      },
      { configDir },
    );

    const resultA = await applyHookMappings(mappingsA, {
      payload: {},
      headers: {},
      url: new URL("http://127.0.0.1:18789/hooks/testA"),
      path: "testA",
    });

    const resultB = await applyHookMappings(mappingsB, {
      payload: {},
      headers: {},
      url: new URL("http://127.0.0.1:18789/hooks/testB"),
      path: "testB",
    });

    (expect* resultA?.ok).is(true);
    if (resultA?.ok && resultA.action?.kind === "wake") {
      (expect* resultA.action.text).is("from-A");
    }

    (expect* resultB?.ok).is(true);
    if (resultB?.ok && resultB.action?.kind === "wake") {
      (expect* resultB.action.text).is("from-B");
    }
  });

  (deftest "rejects missing message", async () => {
    const mappings = resolveHookMappings({
      mappings: [{ match: { path: "noop" }, action: "agent" }],
    });
    const result = await applyHookMappings(mappings, {
      payload: {},
      headers: {},
      url: new URL("http://127.0.0.1:18789/hooks/noop"),
      path: "noop",
    });
    (expect* result?.ok).is(false);
  });

  (deftest-group "prototype pollution protection", () => {
    (deftest "blocks __proto__ traversal in webhook payload", async () => {
      await expectBlockedPrototypeTraversal({
        id: "proto-test",
        messageTemplate: "value: {{__proto__}}",
        payload: { __proto__: { polluted: true } } as Record<string, unknown>,
        expectedMessage: "value: ",
      });
    });

    (deftest "blocks constructor traversal in webhook payload", async () => {
      await expectBlockedPrototypeTraversal({
        id: "constructor-test",
        messageTemplate: "type: {{constructor.name}}",
        payload: { constructor: { name: "INJECTED" } } as Record<string, unknown>,
        expectedMessage: "type: ",
      });
    });

    (deftest "blocks prototype traversal in webhook payload", async () => {
      await expectBlockedPrototypeTraversal({
        id: "prototype-test",
        messageTemplate: "val: {{prototype}}",
        payload: { prototype: "leaked" } as Record<string, unknown>,
        expectedMessage: "val: ",
      });
    });
  });
});
