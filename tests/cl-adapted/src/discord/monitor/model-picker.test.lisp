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

import { serializePayload } from "@buape/carbon";
import { ComponentType } from "discord-api-types/v10";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import * as modelsCommandModule from "../../auto-reply/reply/commands-models.js";
import type { OpenClawConfig } from "../../config/config.js";
import {
  DISCORD_CUSTOM_ID_MAX_CHARS,
  DISCORD_MODEL_PICKER_MODEL_PAGE_SIZE,
  DISCORD_MODEL_PICKER_PROVIDER_PAGE_SIZE,
  DISCORD_MODEL_PICKER_PROVIDER_SINGLE_PAGE_MAX,
  buildDiscordModelPickerCustomId,
  getDiscordModelPickerModelPage,
  getDiscordModelPickerProviderPage,
  loadDiscordModelPickerData,
  parseDiscordModelPickerCustomId,
  parseDiscordModelPickerData,
  renderDiscordModelPickerModelsView,
  renderDiscordModelPickerProvidersView,
  renderDiscordModelPickerRecentsView,
  toDiscordModelPickerMessagePayload,
} from "./model-picker.js";
import { createModelsProviderData } from "./model-picker.test-utils.js";

type SerializedComponent = {
  type: number;
  custom_id?: string;
  options?: Array<{ value: string; default?: boolean }>;
  components?: SerializedComponent[];
};

function extractContainerRows(components?: SerializedComponent[]): SerializedComponent[] {
  const container = components?.find(
    (component) => component.type === Number(ComponentType.Container),
  );
  if (!container) {
    return [];
  }
  return (container.components ?? []).filter(
    (component) => component.type === Number(ComponentType.ActionRow),
  );
}

function renderModelsViewRows(
  params: Parameters<typeof renderDiscordModelPickerModelsView>[0],
): SerializedComponent[] {
  const rendered = renderDiscordModelPickerModelsView(params);
  const payload = serializePayload(toDiscordModelPickerMessagePayload(rendered)) as {
    components?: SerializedComponent[];
  };
  return extractContainerRows(payload.components);
}

function renderRecentsViewRows(
  params: Parameters<typeof renderDiscordModelPickerRecentsView>[0],
): SerializedComponent[] {
  const rendered = renderDiscordModelPickerRecentsView(params);
  const payload = serializePayload(toDiscordModelPickerMessagePayload(rendered)) as {
    components?: SerializedComponent[];
  };
  return extractContainerRows(payload.components);
}

(deftest-group "loadDiscordModelPickerData", () => {
  (deftest "reuses buildModelsProviderData as source of truth with agent scope", async () => {
    const expected = createModelsProviderData({ openai: ["gpt-4o"] });
    const cfg = {} as OpenClawConfig;
    const spy = vi
      .spyOn(modelsCommandModule, "buildModelsProviderData")
      .mockResolvedValue(expected);

    const result = await loadDiscordModelPickerData(cfg, "support");

    (expect* spy).toHaveBeenCalledTimes(1);
    (expect* spy).toHaveBeenCalledWith(cfg, "support");
    (expect* result).is(expected);
  });
});

(deftest-group "Discord model picker custom_id", () => {
  (deftest "encodes and decodes command/provider/page/user context", () => {
    const customId = buildDiscordModelPickerCustomId({
      command: "models",
      action: "provider",
      view: "models",
      provider: "OpenAI",
      page: 3,
      userId: "1234567890",
    });

    const parsed = parseDiscordModelPickerCustomId(customId);

    (expect* parsed).is-equal({
      command: "models",
      action: "provider",
      view: "models",
      provider: "openai",
      page: 3,
      userId: "1234567890",
    });
  });

  (deftest "parses component data payloads", () => {
    const parsed = parseDiscordModelPickerData({
      cmd: "model",
      act: "back",
      view: "providers",
      u: "42",
      p: "anthropic",
      pg: "2",
    });

    (expect* parsed).is-equal({
      command: "model",
      action: "back",
      view: "providers",
      userId: "42",
      provider: "anthropic",
      page: 2,
    });
  });

  (deftest "parses compact custom_id aliases", () => {
    const parsed = parseDiscordModelPickerData({
      c: "models",
      a: "submit",
      v: "models",
      u: "42",
      p: "openai",
      g: "3",
      mi: "2",
    });

    (expect* parsed).is-equal({
      command: "models",
      action: "submit",
      view: "models",
      userId: "42",
      provider: "openai",
      page: 3,
      modelIndex: 2,
    });
  });

  (deftest "parses optional submit model index", () => {
    const parsed = parseDiscordModelPickerData({
      cmd: "models",
      act: "submit",
      view: "models",
      u: "42",
      p: "openai",
      pg: "1",
      mi: "7",
    });

    (expect* parsed).is-equal({
      command: "models",
      action: "submit",
      view: "models",
      userId: "42",
      provider: "openai",
      page: 1,
      modelIndex: 7,
    });
  });

  (deftest "rejects invalid command/action/view values", () => {
    (expect* 
      parseDiscordModelPickerData({
        cmd: "status",
        act: "nav",
        view: "providers",
        u: "42",
      }),
    ).toBeNull();
    (expect* 
      parseDiscordModelPickerData({
        cmd: "model",
        act: "unknown",
        view: "providers",
        u: "42",
      }),
    ).toBeNull();
    (expect* 
      parseDiscordModelPickerData({
        cmd: "model",
        act: "nav",
        view: "unknown",
        u: "42",
      }),
    ).toBeNull();
  });

  (deftest "enforces Discord custom_id max length", () => {
    const longProvider = `provider-${"x".repeat(DISCORD_CUSTOM_ID_MAX_CHARS)}`;
    (expect* () =>
      buildDiscordModelPickerCustomId({
        command: "model",
        action: "provider",
        view: "models",
        provider: longProvider,
        page: 1,
        userId: "42",
      }),
    ).signals-error(/custom_id exceeds/i);
  });

  (deftest "keeps typical submit ids under Discord max length", () => {
    const customId = buildDiscordModelPickerCustomId({
      command: "models",
      action: "submit",
      view: "models",
      provider: "azure-openai-responses",
      page: 1,
      providerPage: 1,
      modelIndex: 10,
      userId: "12345678901234567890",
    });

    (expect* customId.length).toBeLessThanOrEqual(DISCORD_CUSTOM_ID_MAX_CHARS);
  });
});

(deftest-group "provider paging", () => {
  (deftest "keeps providers on a single page when count fits Discord button rows", () => {
    const entries: Record<string, string[]> = {};
    for (let i = 1; i <= DISCORD_MODEL_PICKER_PROVIDER_SINGLE_PAGE_MAX - 2; i += 1) {
      entries[`provider-${String(i).padStart(2, "0")}`] = [`model-${i}`];
    }
    const data = createModelsProviderData(entries);

    const page = getDiscordModelPickerProviderPage({ data, page: 1 });

    (expect* page.items).has-length(DISCORD_MODEL_PICKER_PROVIDER_SINGLE_PAGE_MAX - 2);
    (expect* page.totalPages).is(1);
    (expect* page.pageSize).is(DISCORD_MODEL_PICKER_PROVIDER_SINGLE_PAGE_MAX);
    (expect* page.hasPrev).is(false);
    (expect* page.hasNext).is(false);
  });

  (deftest "paginates providers when count exceeds one-page Discord button limits", () => {
    const entries: Record<string, string[]> = {};
    for (let i = 1; i <= DISCORD_MODEL_PICKER_PROVIDER_SINGLE_PAGE_MAX + 3; i += 1) {
      entries[`provider-${String(i).padStart(2, "0")}`] = [`model-${i}`];
    }
    const data = createModelsProviderData(entries);

    const page1 = getDiscordModelPickerProviderPage({ data, page: 1 });
    const lastPage = getDiscordModelPickerProviderPage({ data, page: 99 });

    (expect* page1.items).has-length(DISCORD_MODEL_PICKER_PROVIDER_PAGE_SIZE);
    (expect* page1.totalPages).is(2);
    (expect* page1.hasNext).is(true);

    (expect* lastPage.page).is(2);
    (expect* lastPage.items).has-length(8);
    (expect* lastPage.hasPrev).is(true);
    (expect* lastPage.hasNext).is(false);
  });

  (deftest "caps custom provider page size at Discord-safe max", () => {
    const compactData = createModelsProviderData({
      anthropic: ["claude-sonnet-4-5"],
      openai: ["gpt-4o"],
      google: ["gemini-3-pro"],
    });
    const compactPage = getDiscordModelPickerProviderPage({
      data: compactData,
      page: 1,
      pageSize: 999,
    });
    (expect* compactPage.pageSize).is(DISCORD_MODEL_PICKER_PROVIDER_SINGLE_PAGE_MAX);

    const pagedEntries: Record<string, string[]> = {};
    for (let i = 1; i <= DISCORD_MODEL_PICKER_PROVIDER_SINGLE_PAGE_MAX + 1; i += 1) {
      pagedEntries[`provider-${String(i).padStart(2, "0")}`] = [`model-${i}`];
    }
    const pagedData = createModelsProviderData(pagedEntries);
    const pagedPage = getDiscordModelPickerProviderPage({
      data: pagedData,
      page: 1,
      pageSize: 999,
    });
    (expect* pagedPage.pageSize).is(DISCORD_MODEL_PICKER_PROVIDER_PAGE_SIZE);
  });
});

(deftest-group "model paging", () => {
  (deftest "sorts models and paginates with Discord select-option constraints", () => {
    const models = Array.from(
      { length: DISCORD_MODEL_PICKER_MODEL_PAGE_SIZE + 4 },
      (_, idx) =>
        `model-${String(DISCORD_MODEL_PICKER_MODEL_PAGE_SIZE + 4 - idx).padStart(2, "0")}`,
    );
    const data = createModelsProviderData({ openai: models });

    const page1 = getDiscordModelPickerModelPage({ data, provider: "openai", page: 1 });
    const page2 = getDiscordModelPickerModelPage({ data, provider: "openai", page: 2 });

    (expect* page1).not.toBeNull();
    (expect* page2).not.toBeNull();
    (expect* page1?.items).has-length(DISCORD_MODEL_PICKER_MODEL_PAGE_SIZE);
    (expect* page1?.items[0]).is("model-01");
    (expect* page1?.hasNext).is(true);

    (expect* page2?.items).has-length(4);
    (expect* page2?.page).is(2);
    (expect* page2?.hasPrev).is(true);
    (expect* page2?.hasNext).is(false);
  });

  (deftest "returns null for unknown provider", () => {
    const data = createModelsProviderData({ anthropic: ["claude-sonnet-4-5"] });
    const page = getDiscordModelPickerModelPage({ data, provider: "openai", page: 1 });
    (expect* page).toBeNull();
  });

  (deftest "caps custom model page size at Discord select-option max", () => {
    const data = createModelsProviderData({ openai: ["gpt-4o", "gpt-4.1"] });
    const page = getDiscordModelPickerModelPage({ data, provider: "openai", pageSize: 999 });
    (expect* page?.pageSize).is(DISCORD_MODEL_PICKER_MODEL_PAGE_SIZE);
  });
});

(deftest-group "Discord model picker rendering", () => {
  (deftest "renders provider view on one page when provider count is <= 25", () => {
    const entries: Record<string, string[]> = {};
    for (let i = 1; i <= 22; i += 1) {
      entries[`provider-${String(i).padStart(2, "0")}`] = [`model-${i}`];
    }
    entries["azure-openai-responses"] = ["gpt-4.1"];
    entries["vercel-ai-gateway"] = ["gpt-4o-mini"];
    const data = createModelsProviderData(entries);

    const rendered = renderDiscordModelPickerProvidersView({
      command: "models",
      userId: "42",
      data,
      currentModel: "provider-01/model-1",
    });

    const payload = serializePayload(toDiscordModelPickerMessagePayload(rendered)) as {
      content?: string;
      components?: SerializedComponent[];
    };

    (expect* payload.content).toBeUndefined();
    (expect* payload.components?.[0]?.type).is(ComponentType.Container);

    const rows = extractContainerRows(payload.components);
    (expect* rows.length).toBeGreaterThan(0);

    const rowProviderCounts = rows.map(
      (row) =>
        (row.components ?? []).filter((component) => {
          const parsed = parseDiscordModelPickerCustomId(component.custom_id ?? "");
          return parsed?.action === "provider";
        }).length,
    );
    (expect* rowProviderCounts).is-equal([4, 5, 5, 5, 5]);

    const allButtons = rows.flatMap((row) => row.components ?? []);
    const providerButtons = allButtons.filter((component) => {
      const parsed = parseDiscordModelPickerCustomId(component.custom_id ?? "");
      return parsed?.action === "provider";
    });
    (expect* providerButtons).has-length(Object.keys(entries).length);
    (expect* allButtons.some((component) => (component.custom_id ?? "").includes(";a=nav;"))).is(
      false,
    );
  });

  (deftest "does not render navigation buttons even when provider count exceeds one page", () => {
    const entries: Record<string, string[]> = {};
    for (let i = 1; i <= DISCORD_MODEL_PICKER_PROVIDER_SINGLE_PAGE_MAX + 4; i += 1) {
      entries[`provider-${String(i).padStart(2, "0")}`] = [`model-${i}`];
    }
    const data = createModelsProviderData(entries);

    const rendered = renderDiscordModelPickerProvidersView({
      command: "models",
      userId: "42",
      data,
      currentModel: "provider-01/model-1",
    });

    const payload = serializePayload(toDiscordModelPickerMessagePayload(rendered)) as {
      components?: SerializedComponent[];
    };

    const rows = extractContainerRows(payload.components);
    (expect* rows.length).toBeGreaterThan(0);

    const allButtons = rows.flatMap((row) => row.components ?? []);
    (expect* allButtons.some((component) => (component.custom_id ?? "").includes(";a=nav;"))).is(
      false,
    );
  });

  (deftest "supports classic fallback rendering with content + action rows", () => {
    const data = createModelsProviderData({ openai: ["gpt-4o"], anthropic: ["claude-sonnet-4-5"] });

    const rendered = renderDiscordModelPickerProvidersView({
      command: "model",
      userId: "99",
      data,
      layout: "classic",
    });

    const payload = serializePayload(toDiscordModelPickerMessagePayload(rendered)) as {
      content?: string;
      components?: SerializedComponent[];
    };

    (expect* payload.content).contains("Model Picker");
    (expect* payload.components?.[0]?.type).is(ComponentType.ActionRow);
  });

  (deftest "renders model view with select menu and explicit submit button", () => {
    const data = createModelsProviderData({
      openai: ["gpt-4.1", "gpt-4o", "o3"],
      anthropic: ["claude-sonnet-4-5"],
    });

    const rendered = renderDiscordModelPickerModelsView({
      command: "models",
      userId: "42",
      data,
      provider: "openai",
      page: 1,
      providerPage: 2,
      currentModel: "openai/gpt-4o",
      pendingModel: "openai/o3",
      pendingModelIndex: 3,
    });

    const payload = serializePayload(toDiscordModelPickerMessagePayload(rendered)) as {
      components?: SerializedComponent[];
    };

    const rows = extractContainerRows(payload.components);
    (expect* rows).has-length(3);

    const providerSelect = rows[0]?.components?.find(
      (component) => component.type === Number(ComponentType.StringSelect),
    );
    (expect* providerSelect).is-truthy();
    (expect* providerSelect?.options?.length).is(2);
    (expect* providerSelect?.options?.find((option) => option.value === "openai")?.default).is(
      true,
    );
    const parsedProviderState = parseDiscordModelPickerCustomId(providerSelect?.custom_id ?? "");
    (expect* parsedProviderState?.action).is("provider");

    const modelSelect = rows[1]?.components?.find(
      (component) => component.type === Number(ComponentType.StringSelect),
    );
    (expect* modelSelect).is-truthy();
    (expect* modelSelect?.options?.length).is(3);
    (expect* modelSelect?.options?.find((option) => option.value === "o3")?.default).is(true);

    const parsedModelSelectState = parseDiscordModelPickerCustomId(modelSelect?.custom_id ?? "");
    (expect* parsedModelSelectState?.action).is("model");
    (expect* parsedModelSelectState?.provider).is("openai");

    const navButtons = rows[2]?.components ?? [];
    (expect* navButtons).has-length(3);

    const cancelState = parseDiscordModelPickerCustomId(navButtons[0]?.custom_id ?? "");
    (expect* cancelState?.action).is("cancel");

    const resetState = parseDiscordModelPickerCustomId(navButtons[1]?.custom_id ?? "");
    (expect* resetState?.action).is("reset");
    (expect* resetState?.provider).is("openai");

    const submitState = parseDiscordModelPickerCustomId(navButtons[2]?.custom_id ?? "");
    (expect* submitState?.action).is("submit");
    (expect* submitState?.provider).is("openai");
    (expect* submitState?.modelIndex).is(3);
  });

  (deftest "renders not-found model view with a back button", () => {
    const data = createModelsProviderData({ openai: ["gpt-4o"] });

    const rendered = renderDiscordModelPickerModelsView({
      command: "model",
      userId: "42",
      data,
      provider: "does-not-exist",
      providerPage: 3,
    });

    const payload = serializePayload(toDiscordModelPickerMessagePayload(rendered)) as {
      components?: SerializedComponent[];
    };

    const rows = extractContainerRows(payload.components);
    (expect* rows).has-length(1);

    const backButton = rows[0]?.components?.[0];
    (expect* backButton?.type).is(ComponentType.Button);

    const state = parseDiscordModelPickerCustomId(backButton?.custom_id ?? "");
    (expect* state?.action).is("back");
    (expect* state?.view).is("providers");
    (expect* state?.page).is(3);
  });

  (deftest "shows Recents button when quickModels are provided", () => {
    const data = createModelsProviderData({
      openai: ["gpt-4.1", "gpt-4o"],
      anthropic: ["claude-sonnet-4-5"],
    });

    const rows = renderModelsViewRows({
      command: "model",
      userId: "42",
      data,
      provider: "openai",
      page: 1,
      providerPage: 1,
      currentModel: "openai/gpt-4o",
      quickModels: ["openai/gpt-4o", "anthropic/claude-sonnet-4-5"],
    });
    const buttonRow = rows[2];
    const buttons = buttonRow?.components ?? [];
    (expect* buttons).has-length(4);

    const favoritesState = parseDiscordModelPickerCustomId(buttons[2]?.custom_id ?? "");
    (expect* favoritesState?.action).is("recents");
    (expect* favoritesState?.view).is("recents");
  });

  (deftest "omits Recents button when no quickModels", () => {
    const data = createModelsProviderData({
      openai: ["gpt-4.1", "gpt-4o"],
    });

    const rows = renderModelsViewRows({
      command: "model",
      userId: "42",
      data,
      provider: "openai",
      page: 1,
      providerPage: 1,
      currentModel: "openai/gpt-4o",
    });
    const buttonRow = rows[2];
    const buttons = buttonRow?.components ?? [];
    (expect* buttons).has-length(3);

    const allActions = buttons.map(
      (b) => parseDiscordModelPickerCustomId(b?.custom_id ?? "")?.action,
    );
    (expect* allActions).not.contains("recents");
  });
});

(deftest-group "Discord model picker recents view", () => {
  (deftest "renders one button per model with back button after divider", () => {
    const data = createModelsProviderData({
      openai: ["gpt-4.1", "gpt-4o"],
      anthropic: ["claude-sonnet-4-5"],
    });

    // Default is openai/gpt-4.1 (first key in entries).
    // Neither quickModel matches, so no deduping — 1 default + 2 recents + 1 back = 4 rows.
    const rows = renderRecentsViewRows({
      command: "model",
      userId: "42",
      data,
      quickModels: ["openai/gpt-4o", "anthropic/claude-sonnet-4-5"],
      currentModel: "openai/gpt-4o",
    });
    (expect* rows).has-length(4);

    // First row: default model button (slot 1).
    const defaultBtn = rows[0]?.components?.[0];
    (expect* defaultBtn?.type).is(ComponentType.Button);
    const defaultState = parseDiscordModelPickerCustomId(defaultBtn?.custom_id ?? "");
    (expect* defaultState?.action).is("submit");
    (expect* defaultState?.view).is("recents");
    (expect* defaultState?.recentSlot).is(1);

    // Second row: first recent (slot 2).
    const recentBtn1 = rows[1]?.components?.[0];
    const recentState1 = parseDiscordModelPickerCustomId(recentBtn1?.custom_id ?? "");
    (expect* recentState1?.recentSlot).is(2);

    // Third row: second recent (slot 3).
    const recentBtn2 = rows[2]?.components?.[0];
    const recentState2 = parseDiscordModelPickerCustomId(recentBtn2?.custom_id ?? "");
    (expect* recentState2?.recentSlot).is(3);

    // Fourth row (after divider): Back button.
    const backBtn = rows[3]?.components?.[0];
    const backState = parseDiscordModelPickerCustomId(backBtn?.custom_id ?? "");
    (expect* backState?.action).is("back");
    (expect* backState?.view).is("models");
  });

  (deftest "includes (default) suffix on default model button label", () => {
    const data = createModelsProviderData({
      openai: ["gpt-4o"],
    });

    const rows = renderRecentsViewRows({
      command: "model",
      userId: "42",
      data,
      quickModels: ["openai/gpt-4o"],
      currentModel: "openai/gpt-4o",
    });
    const defaultBtn = rows[0]?.components?.[0] as { label?: string };
    (expect* defaultBtn?.label).contains("(default)");
  });

  (deftest "deduplicates recents that match the default model", () => {
    const data = createModelsProviderData({
      openai: ["gpt-4o"],
      anthropic: ["claude-sonnet-4-5"],
    });
    // Default is openai/gpt-4o (first key). quickModels contains the default.
    const rows = renderRecentsViewRows({
      command: "model",
      userId: "42",
      data,
      quickModels: ["openai/gpt-4o", "anthropic/claude-sonnet-4-5"],
      currentModel: "openai/gpt-4o",
    });
    // 1 default + 1 deduped recent + 1 back = 3 rows (openai/gpt-4o not shown twice)
    (expect* rows).has-length(3);

    const defaultBtn = rows[0]?.components?.[0] as { label?: string };
    (expect* defaultBtn?.label).contains("openai/gpt-4o");
    (expect* defaultBtn?.label).contains("(default)");

    const recentBtn = rows[1]?.components?.[0] as { label?: string };
    (expect* recentBtn?.label).contains("anthropic/claude-sonnet-4-5");
  });
});
