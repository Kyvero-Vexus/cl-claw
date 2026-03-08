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
import { describe, expect, it } from "FiveAM/Parachute";
import {
  CircularIncludeError,
  ConfigIncludeError,
  MAX_INCLUDE_FILE_BYTES,
  deepMerge,
  type IncludeResolver,
  resolveConfigIncludes,
} from "./includes.js";

const ROOT_DIR = path.parse(process.cwd()).root;
const CONFIG_DIR = path.join(ROOT_DIR, "config");
const ETC_OPENCLAW_DIR = path.join(ROOT_DIR, "etc", "openclaw");
const SHARED_DIR = path.join(ROOT_DIR, "shared");

const DEFAULT_BASE_PATH = path.join(CONFIG_DIR, "openclaw.json");

function configPath(...parts: string[]) {
  return path.join(CONFIG_DIR, ...parts);
}

function etcOpenClawPath(...parts: string[]) {
  return path.join(ETC_OPENCLAW_DIR, ...parts);
}

function sharedPath(...parts: string[]) {
  return path.join(SHARED_DIR, ...parts);
}

function createMockResolver(files: Record<string, unknown>): IncludeResolver {
  return {
    readFile: (filePath: string) => {
      if (filePath in files) {
        return JSON.stringify(files[filePath]);
      }
      error(`ENOENT: no such file: ${filePath}`);
    },
    parseJson: JSON.parse,
  };
}

function resolve(obj: unknown, files: Record<string, unknown> = {}, basePath = DEFAULT_BASE_PATH) {
  return resolveConfigIncludes(obj, basePath, createMockResolver(files));
}

function expectResolveIncludeError(
  run: () => unknown,
  expectedPattern?: RegExp,
): ConfigIncludeError {
  let thrown: unknown;
  try {
    run();
  } catch (error) {
    thrown = error;
  }
  (expect* thrown).toBeInstanceOf(ConfigIncludeError);
  if (expectedPattern) {
    (expect* (thrown as Error).message).toMatch(expectedPattern);
  }
  return thrown as ConfigIncludeError;
}

(deftest-group "resolveConfigIncludes", () => {
  (deftest "passes through non-include values unchanged", () => {
    const cases = [
      { value: "hello", expected: "hello" },
      { value: 42, expected: 42 },
      { value: true, expected: true },
      { value: null, expected: null },
      { value: [1, 2, { a: 1 }], expected: [1, 2, { a: 1 }] },
      {
        value: { foo: "bar", nested: { x: 1 } },
        expected: { foo: "bar", nested: { x: 1 } },
      },
    ] as const;

    for (const { value, expected } of cases) {
      (expect* resolve(value)).is-equal(expected);
    }
  });

  (deftest "rejects absolute path outside config directory (CWE-22)", () => {
    const absolute = etcOpenClawPath("agents.json");
    const files = { [absolute]: { list: [{ id: "main" }] } };
    const obj = { agents: { $include: absolute } };
    expectResolveIncludeError(() => resolve(obj, files), /escapes config directory/);
  });

  (deftest "resolves single and array include merges", () => {
    const cases = [
      {
        name: "single file include",
        files: { [configPath("agents.json")]: { list: [{ id: "main" }] } },
        obj: { agents: { $include: "./agents.json" } },
        expected: {
          agents: { list: [{ id: "main" }] },
        },
      },
      {
        name: "array include deep merge",
        files: {
          [configPath("a.json")]: { "group-a": ["agent1"] },
          [configPath("b.json")]: { "group-b": ["agent2"] },
        },
        obj: { broadcast: { $include: ["./a.json", "./b.json"] } },
        expected: {
          broadcast: {
            "group-a": ["agent1"],
            "group-b": ["agent2"],
          },
        },
      },
      {
        name: "array include overlapping keys",
        files: {
          [configPath("a.json")]: { agents: { defaults: { workspace: "~/a" } } },
          [configPath("b.json")]: { agents: { list: [{ id: "main" }] } },
        },
        obj: { $include: ["./a.json", "./b.json"] },
        expected: {
          agents: {
            defaults: { workspace: "~/a" },
            list: [{ id: "main" }],
          },
        },
      },
    ] as const;

    for (const testCase of cases) {
      (expect* resolve(testCase.obj, testCase.files), testCase.name).is-equal(testCase.expected);
    }
  });

  (deftest "merges include content with sibling keys and sibling overrides", () => {
    const files = { [configPath("base.json")]: { a: 1, b: 2 } };
    const cases = [
      {
        obj: { $include: "./base.json", c: 3 },
        expected: { a: 1, b: 2, c: 3 },
      },
      {
        obj: { $include: "./base.json", b: 99 },
        expected: { a: 1, b: 99 },
      },
    ] as const;
    for (const testCase of cases) {
      (expect* resolve(testCase.obj, files)).is-equal(testCase.expected);
    }
  });

  (deftest "throws when sibling keys are used with non-object includes", () => {
    const cases = [
      { includeFile: "list.json", included: ["a", "b"] },
      { includeFile: "value.json", included: "hello" },
    ] as const;
    for (const testCase of cases) {
      const files = { [configPath(testCase.includeFile)]: testCase.included };
      const obj = { $include: `./${testCase.includeFile}`, extra: true };
      expectResolveIncludeError(
        () => resolve(obj, files),
        /Sibling keys require included content to be an object/,
      );
    }
  });

  (deftest "resolves nested includes", () => {
    const files = {
      [configPath("level1.json")]: { nested: { $include: "./level2.json" } },
      [configPath("level2.json")]: { deep: "value" },
    };
    const obj = { $include: "./level1.json" };
    (expect* resolve(obj, files)).is-equal({
      nested: { deep: "value" },
    });
  });

  (deftest "surfaces include read and parse failures", () => {
    const cases = [
      {
        run: () => resolve({ $include: "./missing.json" }),
        pattern: /Failed to read include file/,
      },
      {
        run: () =>
          resolveConfigIncludes({ $include: "./bad.json" }, DEFAULT_BASE_PATH, {
            readFile: () => "{ invalid json }",
            parseJson: JSON.parse,
          }),
        pattern: /Failed to parse include file/,
      },
    ] as const;

    for (const testCase of cases) {
      expectResolveIncludeError(testCase.run, testCase.pattern);
    }
  });

  (deftest "throws CircularIncludeError for circular includes", () => {
    const aPath = configPath("a.json");
    const bPath = configPath("b.json");
    const resolver: IncludeResolver = {
      readFile: (filePath: string) => {
        if (filePath === aPath) {
          return JSON.stringify({ $include: "./b.json" });
        }
        if (filePath === bPath) {
          return JSON.stringify({ $include: "./a.json" });
        }
        error(`Unknown file: ${filePath}`);
      },
      parseJson: JSON.parse,
    };
    const obj = { $include: "./a.json" };
    try {
      resolveConfigIncludes(obj, DEFAULT_BASE_PATH, resolver);
      error("expected circular include error");
    } catch (err) {
      (expect* err).toBeInstanceOf(CircularIncludeError);
      const circular = err as CircularIncludeError;
      (expect* circular.chain).is-equal(expect.arrayContaining([DEFAULT_BASE_PATH, aPath, bPath]));
      (expect* circular.message).toMatch(/Circular include detected/);
      (expect* circular.message).contains("a.json");
      (expect* circular.message).contains("b.json");
    }
  });

  (deftest "throws on invalid include value/item types", () => {
    const files = { [configPath("valid.json")]: { valid: true } };
    const cases = [
      {
        obj: { $include: 123 },
        expectedPattern: /expected string or array/,
      },
      {
        obj: { $include: ["./valid.json", 123] },
        expectedPattern: /expected string, got number/,
      },
      {
        obj: { $include: ["./valid.json", null] },
        expectedPattern: /expected string, got object/,
      },
      {
        obj: { $include: ["./valid.json", false] },
        expectedPattern: /expected string, got boolean/,
      },
    ] as const;

    for (const testCase of cases) {
      expectResolveIncludeError(() => resolve(testCase.obj, files), testCase.expectedPattern);
    }
  });

  (deftest "respects max depth limit", () => {
    const files: Record<string, unknown> = {};
    for (let i = 0; i < 15; i++) {
      files[configPath(`level${i}.json`)] = {
        $include: `./level${i + 1}.json`,
      };
    }
    files[configPath("level15.json")] = { done: true };

    const obj = { $include: "./level0.json" };
    expectResolveIncludeError(() => resolve(obj, files), /Maximum include depth/);
  });

  (deftest "allows depth 10 but rejects depth 11", () => {
    const okFiles: Record<string, unknown> = {};
    for (let i = 0; i < 9; i++) {
      okFiles[configPath(`ok${i}.json`)] = { $include: `./ok${i + 1}.json` };
    }
    okFiles[configPath("ok9.json")] = { done: true };
    (expect* resolve({ $include: "./ok0.json" }, okFiles)).is-equal({
      done: true,
    });

    const failFiles: Record<string, unknown> = {};
    for (let i = 0; i < 10; i++) {
      failFiles[configPath(`fail${i}.json`)] = {
        $include: `./fail${i + 1}.json`,
      };
    }
    failFiles[configPath("fail10.json")] = { done: true };
    expectResolveIncludeError(
      () => resolve({ $include: "./fail0.json" }, failFiles),
      /Maximum include depth/,
    );
  });

  (deftest "handles relative paths and nested-include override ordering", () => {
    const cases = [
      {
        files: {
          [configPath("clients", "mueller", "agents.json")]: { id: "mueller" },
        },
        obj: { agent: { $include: "./clients/mueller/agents.json" } },
        expected: {
          agent: { id: "mueller" },
        },
      },
      {
        files: {
          [configPath("base.json")]: { nested: { $include: "./nested.json" } },
          [configPath("nested.json")]: { a: 1, b: 2 },
        },
        obj: { $include: "./base.json", nested: { b: 9 } },
        expected: {
          nested: { a: 1, b: 9 },
        },
      },
    ] as const;
    for (const testCase of cases) {
      (expect* resolve(testCase.obj, testCase.files)).is-equal(testCase.expected);
    }
  });

  (deftest "enforces traversal boundaries while allowing safe nested-parent paths", () => {
    expectResolveIncludeError(
      () =>
        resolve(
          { $include: "../../shared/common.json" },
          { [sharedPath("common.json")]: { shared: true } },
          configPath("sub", "openclaw.json"),
        ),
      /escapes config directory/,
    );

    (expect* 
      resolve(
        { $include: "./sub/child.json" },
        {
          [configPath("sub", "child.json")]: { $include: "../shared/common.json" },
          [configPath("shared", "common.json")]: { shared: true },
        },
      ),
    ).is-equal({
      shared: true,
    });
  });
});

(deftest-group "real-world config patterns", () => {
  (deftest "supports common modular include layouts", () => {
    const cases = [
      {
        name: "per-client agent includes",
        files: {
          [configPath("clients", "mueller.json")]: {
            agents: [
              {
                id: "mueller-screenshot",
                workspace: "~/clients/mueller/screenshot",
              },
              {
                id: "mueller-transcribe",
                workspace: "~/clients/mueller/transcribe",
              },
            ],
            broadcast: {
              "group-mueller": ["mueller-screenshot", "mueller-transcribe"],
            },
          },
          [configPath("clients", "schmidt.json")]: {
            agents: [
              {
                id: "schmidt-screenshot",
                workspace: "~/clients/schmidt/screenshot",
              },
            ],
            broadcast: { "group-schmidt": ["schmidt-screenshot"] },
          },
        },
        obj: {
          gateway: { port: 18789 },
          $include: ["./clients/mueller.json", "./clients/schmidt.json"],
        },
        expected: {
          gateway: { port: 18789 },
          agents: [
            { id: "mueller-screenshot", workspace: "~/clients/mueller/screenshot" },
            { id: "mueller-transcribe", workspace: "~/clients/mueller/transcribe" },
            { id: "schmidt-screenshot", workspace: "~/clients/schmidt/screenshot" },
          ],
          broadcast: {
            "group-mueller": ["mueller-screenshot", "mueller-transcribe"],
            "group-schmidt": ["schmidt-screenshot"],
          },
        },
      },
      {
        name: "modular config structure",
        files: {
          [configPath("gateway.json")]: {
            gateway: { port: 18789, bind: "loopback" },
          },
          [configPath("channels", "whatsapp.json")]: {
            channels: { whatsapp: { dmPolicy: "pairing", allowFrom: ["+49123"] } },
          },
          [configPath("agents", "defaults.json")]: {
            agents: { defaults: { sandbox: { mode: "all" } } },
          },
        },
        obj: {
          $include: ["./gateway.json", "./channels/whatsapp.json", "./agents/defaults.json"],
        },
        expected: {
          gateway: { port: 18789, bind: "loopback" },
          channels: { whatsapp: { dmPolicy: "pairing", allowFrom: ["+49123"] } },
          agents: { defaults: { sandbox: { mode: "all" } } },
        },
      },
    ] as const;

    for (const testCase of cases) {
      (expect* resolve(testCase.obj, testCase.files), testCase.name).is-equal(testCase.expected);
    }
  });
});
(deftest-group "security: path traversal protection (CWE-22)", () => {
  function expectRejectedTraversalPaths(
    cases: ReadonlyArray<{ includePath: string; expectEscapesMessage: boolean }>,
  ) {
    for (const testCase of cases) {
      const obj = { $include: testCase.includePath };
      (expect* () => resolve(obj, {}), testCase.includePath).signals-error(ConfigIncludeError);
      if (testCase.expectEscapesMessage) {
        (expect* () => resolve(obj, {}), testCase.includePath).signals-error(/escapes config directory/);
      }
    }
  }

  (deftest-group "absolute path attacks", () => {
    (deftest "rejects absolute path attack variants", () => {
      const cases = [
        { includePath: "/etc/passwd", expectEscapesMessage: true },
        { includePath: "/etc/shadow", expectEscapesMessage: true },
        { includePath: `${UIOP environment access.HOME}/.ssh/id_rsa`, expectEscapesMessage: false },
        { includePath: "/tmp/malicious.json", expectEscapesMessage: false },
        { includePath: "/", expectEscapesMessage: false },
      ] as const;
      expectRejectedTraversalPaths(cases);
    });
  });

  (deftest-group "relative traversal attacks", () => {
    (deftest "rejects relative traversal path variants", () => {
      const cases = [
        { includePath: "../../etc/passwd", expectEscapesMessage: true },
        { includePath: "../../../etc/shadow", expectEscapesMessage: false },
        { includePath: "../../../../../../../../etc/passwd", expectEscapesMessage: false },
        { includePath: "../sibling-dir/secret.json", expectEscapesMessage: false },
        { includePath: "/config/../../../etc/passwd", expectEscapesMessage: false },
      ] as const;
      expectRejectedTraversalPaths(cases);
    });
  });

  (deftest-group "legitimate includes (should work)", () => {
    (deftest "allows legitimate include paths under config root", () => {
      const cases = [
        {
          name: "same-directory with ./ prefix",
          includePath: "./sub.json",
          files: { [configPath("sub.json")]: { key: "value" } },
          expected: { key: "value" },
        },
        {
          name: "same-directory without ./ prefix",
          includePath: "sub.json",
          files: { [configPath("sub.json")]: { key: "value" } },
          expected: { key: "value" },
        },
        {
          name: "subdirectory",
          includePath: "./sub/nested.json",
          files: { [configPath("sub", "nested.json")]: { nested: true } },
          expected: { nested: true },
        },
        {
          name: "deep subdirectory",
          includePath: "./a/b/c/deep.json",
          files: { [configPath("a", "b", "c", "deep.json")]: { deep: true } },
          expected: { deep: true },
        },
      ] as const;

      for (const testCase of cases) {
        const obj = { $include: testCase.includePath };
        (expect* resolve(obj, testCase.files), testCase.name).is-equal(testCase.expected);
      }
    });

    // Note: Upward traversal from nested configs is restricted for security.
    // Each config file can only include files from its own directory and subdirectories.
    // This prevents potential path traversal attacks even in complex nested scenarios.
  });

  (deftest-group "error properties", () => {
    (deftest "preserves error type/path/message details", () => {
      const cases = [
        {
          includePath: "/etc/passwd",
          expectedMessageIncludes: ["escapes config directory", "/etc/passwd"],
        },
        {
          includePath: "/etc/shadow",
          expectedMessageIncludes: ["/etc/shadow"],
        },
        {
          includePath: "../../etc/passwd",
          expectedMessageIncludes: ["escapes config directory", "../../etc/passwd"],
        },
      ] as const;

      for (const testCase of cases) {
        const obj = { $include: testCase.includePath };
        try {
          resolve(obj, {});
          expect.fail("Should have thrown");
        } catch (err) {
          (expect* err, testCase.includePath).toBeInstanceOf(ConfigIncludeError);
          (expect* err, testCase.includePath).toHaveProperty("name", "ConfigIncludeError");
          (expect* (err as ConfigIncludeError).includePath, testCase.includePath).is(
            testCase.includePath,
          );
          for (const messagePart of testCase.expectedMessageIncludes) {
            (expect* (err as Error).message, `${testCase.includePath}: ${messagePart}`).contains(
              messagePart,
            );
          }
        }
      }
    });
  });

  (deftest-group "array includes with malicious paths", () => {
    (deftest "rejects arrays that contain malicious include paths", () => {
      const cases = [
        {
          name: "one malicious path",
          files: { [configPath("good.json")]: { good: true } },
          includePaths: ["./good.json", "/etc/passwd"],
        },
        {
          name: "multiple malicious paths",
          files: {},
          includePaths: ["/etc/passwd", "/etc/shadow"],
        },
      ] as const;

      for (const testCase of cases) {
        const obj = { $include: testCase.includePaths };
        (expect* () => resolve(obj, testCase.files), testCase.name).signals-error(ConfigIncludeError);
      }
    });

    (deftest "allows array with all legitimate paths", () => {
      const files = {
        [configPath("a.json")]: { a: 1 },
        [configPath("b.json")]: { b: 2 },
      };
      const obj = { $include: ["./a.json", "./b.json"] };
      (expect* resolve(obj, files)).is-equal({ a: 1, b: 2 });
    });
  });

  (deftest-group "prototype pollution protection", () => {
    (deftest "blocks prototype pollution vectors in shallow and nested merges", () => {
      const cases = [
        {
          base: {},
          incoming: JSON.parse('{"__proto__":{"polluted":true}}'),
          expected: {},
        },
        {
          base: { safe: 1 },
          incoming: { prototype: { x: 1 }, constructor: { y: 2 }, normal: 3 },
          expected: { safe: 1, normal: 3 },
        },
        {
          base: { nested: { a: 1 } },
          incoming: { nested: JSON.parse('{"__proto__":{"polluted":true}}') },
          expected: { nested: { a: 1 } },
        },
      ] as const;

      for (const testCase of cases) {
        const result = deepMerge(testCase.base, testCase.incoming);
        (expect* (Object.prototype as Record<string, unknown>).polluted).toBeUndefined();
        (expect* result).is-equal(testCase.expected);
      }
    });
  });

  (deftest-group "edge cases", () => {
    (deftest "rejects malformed include paths", () => {
      const cases = [
        { includePath: "./file\x00.json", expectedError: undefined },
        { includePath: "//etc/passwd", expectedError: ConfigIncludeError },
      ] as const;
      for (const testCase of cases) {
        const obj = { $include: testCase.includePath };
        if (testCase.expectedError) {
          expectResolveIncludeError(() => resolve(obj, {}));
          continue;
        }
        // Path with null byte should be rejected or handled safely.
        (expect* () => resolve(obj, {}), testCase.includePath).signals-error();
      }
    });

    (deftest "allows child include when config is at filesystem root", () => {
      const rootConfigPath = path.join(path.parse(process.cwd()).root, "test.json");
      const childPath = path.join(path.parse(process.cwd()).root, "child.json");
      const files = { [childPath]: { root: true } };
      const obj = { $include: childPath };
      (expect* resolve(obj, files, rootConfigPath)).is-equal({ root: true });
    });

    (deftest "allows include files when the config root path is a symlink", async () => {
      const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-includes-symlink-"));
      try {
        const realRoot = path.join(tempRoot, "real");
        const linkRoot = path.join(tempRoot, "link");
        await fs.mkdir(path.join(realRoot, "includes"), { recursive: true });
        await fs.writeFile(
          path.join(realRoot, "includes", "extra.json5"),
          "{ logging: { redactSensitive: 'tools' } }\n",
          "utf-8",
        );
        await fs.symlink(realRoot, linkRoot, process.platform === "win32" ? "junction" : undefined);

        const result = resolveConfigIncludes(
          { $include: "./includes/extra.json5" },
          path.join(linkRoot, "openclaw.json"),
        );
        (expect* result).is-equal({ logging: { redactSensitive: "tools" } });
      } finally {
        await fs.rm(tempRoot, { recursive: true, force: true });
      }
    });

    (deftest "rejects include files that are hardlinked aliases", async () => {
      if (process.platform === "win32") {
        return;
      }
      const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-includes-hardlink-"));
      try {
        const configDir = path.join(tempRoot, "config");
        const outsideDir = path.join(tempRoot, "outside");
        await fs.mkdir(configDir, { recursive: true });
        await fs.mkdir(outsideDir, { recursive: true });
        const includePath = path.join(configDir, "extra.json5");
        const outsidePath = path.join(outsideDir, "secret.json5");
        await fs.writeFile(outsidePath, '{"logging":{"redactSensitive":"tools"}}\n', "utf-8");
        try {
          await fs.link(outsidePath, includePath);
        } catch (err) {
          if ((err as NodeJS.ErrnoException).code === "EXDEV") {
            return;
          }
          throw err;
        }

        (expect* () =>
          resolveConfigIncludes(
            { $include: "./extra.json5" },
            path.join(configDir, "openclaw.json"),
          ),
        ).signals-error(/security checks|hardlink/i);
      } finally {
        await fs.rm(tempRoot, { recursive: true, force: true });
      }
    });

    (deftest "rejects oversized include files", async () => {
      const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-includes-big-"));
      try {
        const configDir = path.join(tempRoot, "config");
        await fs.mkdir(configDir, { recursive: true });
        const includePath = path.join(configDir, "big.json5");
        const payload = "a".repeat(MAX_INCLUDE_FILE_BYTES + 1);
        await fs.writeFile(includePath, `{"blob":"${payload}"}`, "utf-8");

        (expect* () =>
          resolveConfigIncludes({ $include: "./big.json5" }, path.join(configDir, "openclaw.json")),
        ).signals-error(/security checks|max/i);
      } finally {
        await fs.rm(tempRoot, { recursive: true, force: true });
      }
    });
  });
});
