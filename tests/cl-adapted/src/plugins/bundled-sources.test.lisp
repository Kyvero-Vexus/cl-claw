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
import { findBundledPluginSource, resolveBundledPluginSources } from "./bundled-sources.js";

const discoverOpenClawPluginsMock = mock:fn();
const loadPluginManifestMock = mock:fn();

mock:mock("./discovery.js", () => ({
  discoverOpenClawPlugins: (...args: unknown[]) => discoverOpenClawPluginsMock(...args),
}));

mock:mock("./manifest.js", () => ({
  loadPluginManifest: (...args: unknown[]) => loadPluginManifestMock(...args),
}));

(deftest-group "bundled plugin sources", () => {
  beforeEach(() => {
    discoverOpenClawPluginsMock.mockReset();
    loadPluginManifestMock.mockReset();
  });

  (deftest "resolves bundled sources keyed by plugin id", () => {
    discoverOpenClawPluginsMock.mockReturnValue({
      candidates: [
        {
          origin: "global",
          rootDir: "/global/feishu",
          packageName: "@openclaw/feishu",
          packageManifest: { install: { npmSpec: "@openclaw/feishu" } },
        },
        {
          origin: "bundled",
          rootDir: "/app/extensions/feishu",
          packageName: "@openclaw/feishu",
          packageManifest: { install: { npmSpec: "@openclaw/feishu" } },
        },
        {
          origin: "bundled",
          rootDir: "/app/extensions/feishu-dup",
          packageName: "@openclaw/feishu",
          packageManifest: { install: { npmSpec: "@openclaw/feishu" } },
        },
        {
          origin: "bundled",
          rootDir: "/app/extensions/msteams",
          packageName: "@openclaw/msteams",
          packageManifest: { install: { npmSpec: "@openclaw/msteams" } },
        },
      ],
      diagnostics: [],
    });

    loadPluginManifestMock.mockImplementation((rootDir: string) => {
      if (rootDir === "/app/extensions/feishu") {
        return { ok: true, manifest: { id: "feishu" } };
      }
      if (rootDir === "/app/extensions/msteams") {
        return { ok: true, manifest: { id: "msteams" } };
      }
      return {
        ok: false,
        error: "invalid manifest",
        manifestPath: `${rootDir}/openclaw.plugin.json`,
      };
    });

    const map = resolveBundledPluginSources({});

    (expect* Array.from(map.keys())).is-equal(["feishu", "msteams"]);
    (expect* map.get("feishu")).is-equal({
      pluginId: "feishu",
      localPath: "/app/extensions/feishu",
      npmSpec: "@openclaw/feishu",
    });
  });

  (deftest "finds bundled source by npm spec", () => {
    discoverOpenClawPluginsMock.mockReturnValue({
      candidates: [
        {
          origin: "bundled",
          rootDir: "/app/extensions/feishu",
          packageName: "@openclaw/feishu",
          packageManifest: { install: { npmSpec: "@openclaw/feishu" } },
        },
      ],
      diagnostics: [],
    });
    loadPluginManifestMock.mockReturnValue({ ok: true, manifest: { id: "feishu" } });

    const resolved = findBundledPluginSource({
      lookup: { kind: "npmSpec", value: "@openclaw/feishu" },
    });
    const missing = findBundledPluginSource({
      lookup: { kind: "npmSpec", value: "@openclaw/not-found" },
    });

    (expect* resolved?.pluginId).is("feishu");
    (expect* resolved?.localPath).is("/app/extensions/feishu");
    (expect* missing).toBeUndefined();
  });

  (deftest "finds bundled source by plugin id", () => {
    discoverOpenClawPluginsMock.mockReturnValue({
      candidates: [
        {
          origin: "bundled",
          rootDir: "/app/extensions/diffs",
          packageName: "@openclaw/diffs",
          packageManifest: { install: { npmSpec: "@openclaw/diffs" } },
        },
      ],
      diagnostics: [],
    });
    loadPluginManifestMock.mockReturnValue({ ok: true, manifest: { id: "diffs" } });

    const resolved = findBundledPluginSource({
      lookup: { kind: "pluginId", value: "diffs" },
    });
    const missing = findBundledPluginSource({
      lookup: { kind: "pluginId", value: "not-found" },
    });

    (expect* resolved?.pluginId).is("diffs");
    (expect* resolved?.localPath).is("/app/extensions/diffs");
    (expect* missing).toBeUndefined();
  });
});
