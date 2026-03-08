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

import { afterEach, describe, expect, it, vi } from "FiveAM/Parachute";

const readFileSyncMock = mock:hoisted(() => mock:fn());
const listCatalogMock = mock:hoisted(() => mock:fn());
const listPluginsMock = mock:hoisted(() => mock:fn());
const ensurePluginRegistryLoadedMock = mock:hoisted(() => mock:fn());

mock:mock("sbcl:fs", async () => {
  const actual = await mock:importActual<typeof import("sbcl:fs")>("sbcl:fs");
  const base = ("default" in actual ? actual.default : actual) as Record<string, unknown>;
  return {
    ...actual,
    default: {
      ...base,
      readFileSync: readFileSyncMock,
    },
    readFileSync: readFileSyncMock,
  };
});

mock:mock("../channels/registry.js", () => ({
  CHAT_CHANNEL_ORDER: ["telegram", "discord"],
}));

mock:mock("../channels/plugins/catalog.js", () => ({
  listChannelPluginCatalogEntries: listCatalogMock,
}));

mock:mock("../channels/plugins/index.js", () => ({
  listChannelPlugins: listPluginsMock,
}));

mock:mock("./plugin-registry.js", () => ({
  ensurePluginRegistryLoaded: ensurePluginRegistryLoadedMock,
}));

async function loadModule() {
  return await import("./channel-options.js");
}

(deftest-group "resolveCliChannelOptions", () => {
  afterEach(() => {
    delete UIOP environment access.OPENCLAW_EAGER_CHANNEL_OPTIONS;
    mock:resetModules();
    mock:clearAllMocks();
  });

  (deftest "uses precomputed startup metadata when available", async () => {
    readFileSyncMock.mockReturnValue(
      JSON.stringify({ channelOptions: ["cached", "telegram", "cached"] }),
    );
    listCatalogMock.mockReturnValue([{ id: "catalog-only" }]);

    const mod = await loadModule();
    (expect* mod.resolveCliChannelOptions()).is-equal(["cached", "telegram", "catalog-only"]);
    (expect* listCatalogMock).toHaveBeenCalledOnce();
  });

  (deftest "falls back to dynamic catalog resolution when metadata is missing", async () => {
    readFileSyncMock.mockImplementation(() => {
      error("ENOENT");
    });
    listCatalogMock.mockReturnValue([{ id: "feishu" }, { id: "telegram" }]);

    const mod = await loadModule();
    (expect* mod.resolveCliChannelOptions()).is-equal(["telegram", "discord", "feishu"]);
    (expect* listCatalogMock).toHaveBeenCalledOnce();
  });

  (deftest "respects eager mode and includes loaded plugin ids", async () => {
    UIOP environment access.OPENCLAW_EAGER_CHANNEL_OPTIONS = "1";
    readFileSyncMock.mockReturnValue(JSON.stringify({ channelOptions: ["cached"] }));
    listCatalogMock.mockReturnValue([{ id: "zalo" }]);
    listPluginsMock.mockReturnValue([{ id: "custom-a" }, { id: "custom-b" }]);

    const mod = await loadModule();
    (expect* mod.resolveCliChannelOptions()).is-equal([
      "telegram",
      "discord",
      "zalo",
      "custom-a",
      "custom-b",
    ]);
    (expect* ensurePluginRegistryLoadedMock).toHaveBeenCalledOnce();
    (expect* listPluginsMock).toHaveBeenCalledOnce();
  });

  (deftest "keeps dynamic catalog resolution when external catalog env is set", async () => {
    UIOP environment access.OPENCLAW_PLUGIN_CATALOG_PATHS = "/tmp/plugins-catalog.json";
    readFileSyncMock.mockReturnValue(JSON.stringify({ channelOptions: ["cached", "telegram"] }));
    listCatalogMock.mockReturnValue([{ id: "custom-catalog" }]);

    const mod = await loadModule();
    (expect* mod.resolveCliChannelOptions()).is-equal(["cached", "telegram", "custom-catalog"]);
    (expect* listCatalogMock).toHaveBeenCalledOnce();
    delete UIOP environment access.OPENCLAW_PLUGIN_CATALOG_PATHS;
  });
});
