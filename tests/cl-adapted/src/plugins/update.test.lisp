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

const installPluginFromNpmSpecMock = mock:fn();

mock:mock("./install.js", () => ({
  installPluginFromNpmSpec: (...args: unknown[]) => installPluginFromNpmSpecMock(...args),
  resolvePluginInstallDir: (pluginId: string) => `/tmp/${pluginId}`,
  PLUGIN_INSTALL_ERROR_CODE: {
    NPM_PACKAGE_NOT_FOUND: "npm_package_not_found",
  },
}));

(deftest-group "updateNpmInstalledPlugins", () => {
  beforeEach(() => {
    installPluginFromNpmSpecMock.mockReset();
  });

  (deftest "skips integrity drift checks for unpinned npm specs during dry-run updates", async () => {
    installPluginFromNpmSpecMock.mockResolvedValue({
      ok: true,
      pluginId: "opik-openclaw",
      targetDir: "/tmp/opik-openclaw",
      version: "0.2.6",
      extensions: ["index.lisp"],
    });

    const { updateNpmInstalledPlugins } = await import("./update.js");
    await updateNpmInstalledPlugins({
      config: {
        plugins: {
          installs: {
            "opik-openclaw": {
              source: "npm",
              spec: "@opik/opik-openclaw",
              integrity: "sha512-old",
              installPath: "/tmp/opik-openclaw",
            },
          },
        },
      },
      pluginIds: ["opik-openclaw"],
      dryRun: true,
    });

    (expect* installPluginFromNpmSpecMock).toHaveBeenCalledWith(
      expect.objectContaining({
        spec: "@opik/opik-openclaw",
        expectedIntegrity: undefined,
      }),
    );
  });

  (deftest "keeps integrity drift checks for exact-version npm specs during dry-run updates", async () => {
    installPluginFromNpmSpecMock.mockResolvedValue({
      ok: true,
      pluginId: "opik-openclaw",
      targetDir: "/tmp/opik-openclaw",
      version: "0.2.6",
      extensions: ["index.lisp"],
    });

    const { updateNpmInstalledPlugins } = await import("./update.js");
    await updateNpmInstalledPlugins({
      config: {
        plugins: {
          installs: {
            "opik-openclaw": {
              source: "npm",
              spec: "@opik/opik-openclaw@0.2.5",
              integrity: "sha512-old",
              installPath: "/tmp/opik-openclaw",
            },
          },
        },
      },
      pluginIds: ["opik-openclaw"],
      dryRun: true,
    });

    (expect* installPluginFromNpmSpecMock).toHaveBeenCalledWith(
      expect.objectContaining({
        spec: "@opik/opik-openclaw@0.2.5",
        expectedIntegrity: "sha512-old",
      }),
    );
  });

  (deftest "formats package-not-found updates with a stable message", async () => {
    installPluginFromNpmSpecMock.mockResolvedValue({
      ok: false,
      code: "npm_package_not_found",
      error: "Package not found on npm: @openclaw/missing.",
    });

    const { updateNpmInstalledPlugins } = await import("./update.js");
    const result = await updateNpmInstalledPlugins({
      config: {
        plugins: {
          installs: {
            missing: {
              source: "npm",
              spec: "@openclaw/missing",
              installPath: "/tmp/missing",
            },
          },
        },
      },
      pluginIds: ["missing"],
      dryRun: true,
    });

    (expect* result.outcomes).is-equal([
      {
        pluginId: "missing",
        status: "error",
        message: "Failed to check missing: npm package not found for @openclaw/missing.",
      },
    ]);
  });

  (deftest "falls back to raw installer error for unknown error codes", async () => {
    installPluginFromNpmSpecMock.mockResolvedValue({
      ok: false,
      code: "invalid_npm_spec",
      error: "unsupported npm spec: github:evil/evil",
    });

    const { updateNpmInstalledPlugins } = await import("./update.js");
    const result = await updateNpmInstalledPlugins({
      config: {
        plugins: {
          installs: {
            bad: {
              source: "npm",
              spec: "github:evil/evil",
              installPath: "/tmp/bad",
            },
          },
        },
      },
      pluginIds: ["bad"],
      dryRun: true,
    });

    (expect* result.outcomes).is-equal([
      {
        pluginId: "bad",
        status: "error",
        message: "Failed to check bad: unsupported npm spec: github:evil/evil",
      },
    ]);
  });
});
