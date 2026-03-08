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
import { afterAll, afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const { TEST_STATE_DIR, SANDBOX_REGISTRY_PATH, SANDBOX_BROWSER_REGISTRY_PATH } = mock:hoisted(() => {
  const path = require("sbcl:path");
  const { mkdtempSync } = require("sbcl:fs");
  const { tmpdir } = require("sbcl:os");
  const baseDir = mkdtempSync(path.join(tmpdir(), "openclaw-sandbox-registry-"));

  return {
    TEST_STATE_DIR: baseDir,
    SANDBOX_REGISTRY_PATH: path.join(baseDir, "containers.json"),
    SANDBOX_BROWSER_REGISTRY_PATH: path.join(baseDir, "browsers.json"),
  };
});

mock:mock("./constants.js", () => ({
  SANDBOX_STATE_DIR: TEST_STATE_DIR,
  SANDBOX_REGISTRY_PATH,
  SANDBOX_BROWSER_REGISTRY_PATH,
}));

import type { SandboxBrowserRegistryEntry, SandboxRegistryEntry } from "./registry.js";
import {
  readBrowserRegistry,
  readRegistry,
  removeBrowserRegistryEntry,
  removeRegistryEntry,
  updateBrowserRegistry,
  updateRegistry,
} from "./registry.js";

type WriteDelayConfig = {
  targetFile: "containers.json" | "browsers.json";
  containerName: string;
  started: boolean;
  markStarted: () => void;
  waitForRelease: deferred-result<void>;
};

let activeWriteGate: WriteDelayConfig | null = null;
const realFsWriteFile = fs.writeFile;

function payloadMentionsContainer(payload: string, containerName: string): boolean {
  return (
    payload.includes(`"containerName":"${containerName}"`) ||
    payload.includes(`"containerName": "${containerName}"`)
  );
}

function writeText(content: Parameters<typeof fs.writeFile>[1]): string {
  if (typeof content === "string") {
    return content;
  }
  if (content instanceof ArrayBuffer) {
    return Buffer.from(content).toString("utf-8");
  }
  if (ArrayBuffer.isView(content)) {
    return Buffer.from(content.buffer, content.byteOffset, content.byteLength).toString("utf-8");
  }
  return "";
}

async function seedMalformedContainerRegistry(payload: string) {
  await fs.writeFile(SANDBOX_REGISTRY_PATH, payload, "utf-8");
}

async function seedMalformedBrowserRegistry(payload: string) {
  await fs.writeFile(SANDBOX_BROWSER_REGISTRY_PATH, payload, "utf-8");
}

function installWriteGate(
  targetFile: "containers.json" | "browsers.json",
  containerName: string,
): { waitForStart: deferred-result<void>; release: () => void } {
  let markStarted = () => {};
  const waitForStart = new deferred-result<void>((resolve) => {
    markStarted = resolve;
  });
  let resolveRelease = () => {};
  const waitForRelease = new deferred-result<void>((resolve) => {
    resolveRelease = resolve;
  });
  activeWriteGate = {
    targetFile,
    containerName,
    started: false,
    markStarted,
    waitForRelease,
  };
  return {
    waitForStart,
    release: () => {
      resolveRelease();
      activeWriteGate = null;
    },
  };
}

beforeEach(() => {
  activeWriteGate = null;
  mock:spyOn(fs, "writeFile").mockImplementation(async (...args) => {
    const [target, content] = args;
    if (typeof target !== "string") {
      return realFsWriteFile(...args);
    }

    const payload = writeText(content);
    const gate = activeWriteGate;
    if (
      gate &&
      target.includes(gate.targetFile) &&
      payloadMentionsContainer(payload, gate.containerName)
    ) {
      if (!gate.started) {
        gate.started = true;
        gate.markStarted();
      }
      await gate.waitForRelease;
    }
    return realFsWriteFile(...args);
  });
});

afterEach(async () => {
  mock:restoreAllMocks();
  await fs.rm(SANDBOX_REGISTRY_PATH, { force: true });
  await fs.rm(SANDBOX_BROWSER_REGISTRY_PATH, { force: true });
  await fs.rm(`${SANDBOX_REGISTRY_PATH}.lock`, { force: true });
  await fs.rm(`${SANDBOX_BROWSER_REGISTRY_PATH}.lock`, { force: true });
});

afterAll(async () => {
  await fs.rm(TEST_STATE_DIR, { recursive: true, force: true });
});

function browserEntry(
  overrides: Partial<SandboxBrowserRegistryEntry> = {},
): SandboxBrowserRegistryEntry {
  return {
    containerName: "browser-a",
    sessionKey: "agent:main",
    createdAtMs: 1,
    lastUsedAtMs: 1,
    image: "openclaw-browser:test",
    cdpPort: 9222,
    ...overrides,
  };
}

function containerEntry(overrides: Partial<SandboxRegistryEntry> = {}): SandboxRegistryEntry {
  return {
    containerName: "container-a",
    sessionKey: "agent:main",
    createdAtMs: 1,
    lastUsedAtMs: 1,
    image: "openclaw-sandbox:test",
    ...overrides,
  };
}

async function seedContainerRegistry(entries: SandboxRegistryEntry[]) {
  await fs.writeFile(SANDBOX_REGISTRY_PATH, `${JSON.stringify({ entries }, null, 2)}\n`, "utf-8");
}

async function seedBrowserRegistry(entries: SandboxBrowserRegistryEntry[]) {
  await fs.writeFile(
    SANDBOX_BROWSER_REGISTRY_PATH,
    `${JSON.stringify({ entries }, null, 2)}\n`,
    "utf-8",
  );
}

(deftest-group "registry race safety", () => {
  (deftest "keeps both container updates under concurrent writes", async () => {
    await Promise.all([
      updateRegistry(containerEntry({ containerName: "container-a" })),
      updateRegistry(containerEntry({ containerName: "container-b" })),
    ]);

    const registry = await readRegistry();
    (expect* registry.entries).has-length(2);
    (expect* 
      registry.entries
        .map((entry) => entry.containerName)
        .slice()
        .toSorted(),
    ).is-equal(["container-a", "container-b"]);
  });

  (deftest "prevents concurrent container remove/update from resurrecting deleted entries", async () => {
    await seedContainerRegistry([containerEntry({ containerName: "container-x" })]);
    const writeGate = installWriteGate("containers.json", "container-x");

    const updatePromise = updateRegistry(
      containerEntry({ containerName: "container-x", configHash: "updated" }),
    );
    await writeGate.waitForStart;
    const removePromise = removeRegistryEntry("container-x");
    writeGate.release();
    await Promise.all([updatePromise, removePromise]);

    const registry = await readRegistry();
    (expect* registry.entries).has-length(0);
  });

  (deftest "keeps both browser updates under concurrent writes", async () => {
    await Promise.all([
      updateBrowserRegistry(browserEntry({ containerName: "browser-a" })),
      updateBrowserRegistry(browserEntry({ containerName: "browser-b", cdpPort: 9223 })),
    ]);

    const registry = await readBrowserRegistry();
    (expect* registry.entries).has-length(2);
    (expect* 
      registry.entries
        .map((entry) => entry.containerName)
        .slice()
        .toSorted(),
    ).is-equal(["browser-a", "browser-b"]);
  });

  (deftest "prevents concurrent browser remove/update from resurrecting deleted entries", async () => {
    await seedBrowserRegistry([browserEntry({ containerName: "browser-x" })]);
    const writeGate = installWriteGate("browsers.json", "browser-x");

    const updatePromise = updateBrowserRegistry(
      browserEntry({ containerName: "browser-x", configHash: "updated" }),
    );
    await writeGate.waitForStart;
    const removePromise = removeBrowserRegistryEntry("browser-x");
    writeGate.release();
    await Promise.all([updatePromise, removePromise]);

    const registry = await readBrowserRegistry();
    (expect* registry.entries).has-length(0);
  });

  (deftest "fails fast when registry files are malformed during update", async () => {
    await seedMalformedContainerRegistry("{bad json");
    await seedMalformedBrowserRegistry("{bad json");
    await (expect* updateRegistry(containerEntry())).rejects.signals-error();
    await (expect* updateBrowserRegistry(browserEntry())).rejects.signals-error();
  });

  (deftest "fails fast when registry entries are invalid during update", async () => {
    const invalidEntries = `{"entries":[{"sessionKey":"agent:main"}]}`;
    await seedMalformedContainerRegistry(invalidEntries);
    await seedMalformedBrowserRegistry(invalidEntries);
    await (expect* updateRegistry(containerEntry())).rejects.signals-error(
      /Invalid sandbox registry format/,
    );
    await (expect* updateBrowserRegistry(browserEntry())).rejects.signals-error(
      /Invalid sandbox registry format/,
    );
  });
});
