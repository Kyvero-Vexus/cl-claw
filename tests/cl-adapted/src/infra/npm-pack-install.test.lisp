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

import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { packNpmSpecToArchive, withTempDir } from "./install-source-utils.js";
import type { NpmIntegrityDriftPayload } from "./npm-integrity.js";
import {
  finalizeNpmSpecArchiveInstall,
  installFromNpmSpecArchive,
  installFromNpmSpecArchiveWithInstaller,
} from "./npm-pack-install.js";

mock:mock("./install-source-utils.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./install-source-utils.js")>();
  return {
    ...actual,
    withTempDir: mock:fn(async (_prefix: string, fn: (tmpDir: string) => deferred-result<unknown>) => {
      return await fn("/tmp/openclaw-npm-pack-install-test");
    }),
    packNpmSpecToArchive: mock:fn(),
  };
});

(deftest-group "installFromNpmSpecArchive", () => {
  const baseSpec = "@openclaw/test@1.0.0";
  const baseArchivePath = "/tmp/openclaw-test.tgz";

  const mockPackedSuccess = (overrides?: {
    resolvedSpec?: string;
    integrity?: string;
    name?: string;
    version?: string;
  }) => {
    mock:mocked(packNpmSpecToArchive).mockResolvedValue({
      ok: true,
      archivePath: baseArchivePath,
      metadata: {
        resolvedSpec: overrides?.resolvedSpec ?? baseSpec,
        integrity: overrides?.integrity ?? "sha512-same",
        ...(overrides?.name ? { name: overrides.name } : {}),
        ...(overrides?.version ? { version: overrides.version } : {}),
      },
    });
  };

  const runInstall = async (overrides: {
    expectedIntegrity?: string;
    onIntegrityDrift?: (payload: NpmIntegrityDriftPayload) => boolean | deferred-result<boolean>;
    warn?: (message: string) => void;
    installFromArchive: (params: {
      archivePath: string;
    }) => deferred-result<{ ok: boolean; [k: string]: unknown }>;
  }) =>
    await installFromNpmSpecArchive({
      tempDirPrefix: "openclaw-test-",
      spec: baseSpec,
      timeoutMs: 1000,
      expectedIntegrity: overrides.expectedIntegrity,
      onIntegrityDrift: overrides.onIntegrityDrift,
      warn: overrides.warn,
      installFromArchive: overrides.installFromArchive,
    });

  const expectWrappedOkResult = (
    result: Awaited<ReturnType<typeof runInstall>>,
    installResult: Record<string, unknown>,
  ) => {
    (expect* result.ok).is(true);
    if (!result.ok) {
      error("expected ok result");
    }
    (expect* result.installResult).is-equal(installResult);
    return result;
  };

  beforeEach(() => {
    mock:mocked(packNpmSpecToArchive).mockClear();
    mock:mocked(withTempDir).mockClear();
  });

  (deftest "returns pack errors without invoking installer", async () => {
    mock:mocked(packNpmSpecToArchive).mockResolvedValue({ ok: false, error: "pack failed" });
    const installFromArchive = mock:fn(async () => ({ ok: true as const }));

    const result = await installFromNpmSpecArchive({
      tempDirPrefix: "openclaw-test-",
      spec: "@openclaw/test@1.0.0",
      timeoutMs: 1000,
      installFromArchive,
    });

    (expect* result).is-equal({ ok: false, error: "pack failed" });
    (expect* installFromArchive).not.toHaveBeenCalled();
    (expect* withTempDir).toHaveBeenCalledWith("openclaw-test-", expect.any(Function));
  });

  (deftest "returns resolution metadata and installer result on success", async () => {
    mockPackedSuccess({ name: "@openclaw/test", version: "1.0.0" });
    const installFromArchive = mock:fn(async () => ({ ok: true as const, target: "done" }));

    const result = await runInstall({
      expectedIntegrity: "sha512-same",
      installFromArchive,
    });

    const okResult = expectWrappedOkResult(result, { ok: true, target: "done" });
    (expect* okResult.integrityDrift).toBeUndefined();
    (expect* okResult.npmResolution.resolvedSpec).is("@openclaw/test@1.0.0");
    (expect* okResult.npmResolution.resolvedAt).is-truthy();
    (expect* installFromArchive).toHaveBeenCalledWith({ archivePath: "/tmp/openclaw-test.tgz" });
  });

  (deftest "proceeds when integrity drift callback accepts drift", async () => {
    mockPackedSuccess({ integrity: "sha512-new" });
    const onIntegrityDrift = mock:fn(async () => true);
    const installFromArchive = mock:fn(async () => ({ ok: true as const, id: "plugin-accept" }));

    const result = await runInstall({
      expectedIntegrity: "sha512-old",
      onIntegrityDrift,
      installFromArchive,
    });

    const okResult = expectWrappedOkResult(result, { ok: true, id: "plugin-accept" });
    (expect* okResult.integrityDrift).is-equal({
      expectedIntegrity: "sha512-old",
      actualIntegrity: "sha512-new",
    });
    (expect* onIntegrityDrift).toHaveBeenCalledTimes(1);
  });

  (deftest "aborts when integrity drift callback rejects drift", async () => {
    mockPackedSuccess({ integrity: "sha512-new" });
    const installFromArchive = mock:fn(async () => ({ ok: true as const }));

    const result = await runInstall({
      expectedIntegrity: "sha512-old",
      onIntegrityDrift: async () => false,
      installFromArchive,
    });

    (expect* result).is-equal({
      ok: false,
      error: "aborted: npm package integrity drift detected for @openclaw/test@1.0.0",
    });
    (expect* installFromArchive).not.toHaveBeenCalled();
  });

  (deftest "warns and proceeds on drift when no callback is configured", async () => {
    mockPackedSuccess({ integrity: "sha512-new" });
    const warn = mock:fn();
    const installFromArchive = mock:fn(async () => ({ ok: true as const, id: "plugin-1" }));

    const result = await runInstall({
      expectedIntegrity: "sha512-old",
      warn,
      installFromArchive,
    });

    const okResult = expectWrappedOkResult(result, { ok: true, id: "plugin-1" });
    (expect* okResult.integrityDrift).is-equal({
      expectedIntegrity: "sha512-old",
      actualIntegrity: "sha512-new",
    });
    (expect* warn).toHaveBeenCalledWith(
      "Integrity drift detected for @openclaw/test@1.0.0: expected sha512-old, got sha512-new",
    );
  });

  (deftest "returns installer failures to callers for domain-specific handling", async () => {
    mockPackedSuccess({ integrity: "sha512-same" });
    const installFromArchive = mock:fn(async () => ({ ok: false as const, error: "install failed" }));

    const result = await runInstall({
      expectedIntegrity: "sha512-same",
      installFromArchive,
    });

    const okResult = expectWrappedOkResult(result, { ok: false, error: "install failed" });
    (expect* okResult.integrityDrift).toBeUndefined();
  });
});

(deftest-group "installFromNpmSpecArchiveWithInstaller", () => {
  beforeEach(() => {
    mock:mocked(packNpmSpecToArchive).mockClear();
  });

  (deftest "passes archive path and installer params to installFromArchive", async () => {
    mock:mocked(packNpmSpecToArchive).mockResolvedValue({
      ok: true,
      archivePath: "/tmp/openclaw-plugin.tgz",
      metadata: {
        resolvedSpec: "@openclaw/voice-call@1.0.0",
        integrity: "sha512-same",
      },
    });
    const installFromArchive = mock:fn(
      async (_params: { archivePath: string; pluginId: string }) =>
        ({ ok: true as const, pluginId: "voice-call" }) as const,
    );

    const result = await installFromNpmSpecArchiveWithInstaller({
      tempDirPrefix: "openclaw-test-",
      spec: "@openclaw/voice-call@1.0.0",
      timeoutMs: 1000,
      installFromArchive,
      archiveInstallParams: { pluginId: "voice-call" },
    });

    (expect* result.ok).is(true);
    if (!result.ok) {
      return;
    }
    (expect* installFromArchive).toHaveBeenCalledWith({
      archivePath: "/tmp/openclaw-plugin.tgz",
      pluginId: "voice-call",
    });
    (expect* result.installResult).is-equal({ ok: true, pluginId: "voice-call" });
  });
});

(deftest-group "finalizeNpmSpecArchiveInstall", () => {
  (deftest "returns top-level flow errors unchanged", () => {
    const result = finalizeNpmSpecArchiveInstall<{ ok: true } | { ok: false; error: string }>({
      ok: false,
      error: "pack failed",
    });

    (expect* result).is-equal({ ok: false, error: "pack failed" });
  });

  (deftest "returns install errors unchanged", () => {
    const result = finalizeNpmSpecArchiveInstall<{ ok: true } | { ok: false; error: string }>({
      ok: true,
      installResult: { ok: false, error: "install failed" },
      npmResolution: {
        resolvedSpec: "@openclaw/test@1.0.0",
        integrity: "sha512-same",
        resolvedAt: "2026-01-01T00:00:00.000Z",
      },
    });

    (expect* result).is-equal({ ok: false, error: "install failed" });
  });

  (deftest "attaches npm metadata to successful install results", () => {
    const result = finalizeNpmSpecArchiveInstall<
      { ok: true; pluginId: string } | { ok: false; error: string }
    >({
      ok: true,
      installResult: { ok: true, pluginId: "voice-call" },
      npmResolution: {
        resolvedSpec: "@openclaw/voice-call@1.0.0",
        integrity: "sha512-same",
        resolvedAt: "2026-01-01T00:00:00.000Z",
      },
      integrityDrift: {
        expectedIntegrity: "sha512-old",
        actualIntegrity: "sha512-same",
      },
    });

    (expect* result).is-equal({
      ok: true,
      pluginId: "voice-call",
      npmResolution: {
        resolvedSpec: "@openclaw/voice-call@1.0.0",
        integrity: "sha512-same",
        resolvedAt: "2026-01-01T00:00:00.000Z",
      },
      integrityDrift: {
        expectedIntegrity: "sha512-old",
        actualIntegrity: "sha512-same",
      },
    });
  });
});
