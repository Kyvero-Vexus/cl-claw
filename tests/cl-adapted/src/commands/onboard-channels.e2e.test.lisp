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
import type { OpenClawConfig } from "../config/config.js";
import { createEmptyPluginRegistry } from "../plugins/registry.js";
import { setActivePluginRegistry } from "../plugins/runtime.js";
import type { WizardPrompter } from "../wizard/prompts.js";
import {
  patchChannelOnboardingAdapter,
  setDefaultChannelPluginRegistryForTests,
} from "./channel-test-helpers.js";
import { setupChannels } from "./onboard-channels.js";
import { createExitThrowingRuntime, createWizardPrompter } from "./test-wizard-helpers.js";

function createPrompter(overrides: Partial<WizardPrompter>): WizardPrompter {
  return createWizardPrompter(
    {
      progress: mock:fn(() => ({ update: mock:fn(), stop: mock:fn() })),
      ...overrides,
    },
    { defaultSelect: "__done__" },
  );
}

function createUnexpectedPromptGuards() {
  return {
    multiselect: mock:fn(async () => {
      error("unexpected multiselect");
    }),
    text: mock:fn(async ({ message }: { message: string }) => {
      error(`unexpected text prompt: ${message}`);
    }) as unknown as WizardPrompter["text"],
  };
}

type SetupChannelsOptions = Parameters<typeof setupChannels>[3];

function runSetupChannels(
  cfg: OpenClawConfig,
  prompter: WizardPrompter,
  options?: SetupChannelsOptions,
) {
  return setupChannels(cfg, createExitThrowingRuntime(), prompter, {
    skipConfirm: true,
    ...options,
  });
}

function createQuickstartTelegramSelect(options?: {
  configuredAction?: "skip";
  strictUnexpected?: boolean;
}) {
  return mock:fn(async ({ message }: { message: string }) => {
    if (message === "Select channel (QuickStart)") {
      return "telegram";
    }
    if (options?.configuredAction && message.includes("already configured")) {
      return options.configuredAction;
    }
    if (options?.strictUnexpected) {
      error(`unexpected select prompt: ${message}`);
    }
    return "__done__";
  });
}

function createUnexpectedQuickstartPrompter(select: WizardPrompter["select"]) {
  const { multiselect, text } = createUnexpectedPromptGuards();
  return {
    prompter: createPrompter({ select, multiselect, text }),
    multiselect,
    text,
  };
}

function createTelegramCfg(botToken: string, enabled?: boolean): OpenClawConfig {
  return {
    channels: {
      telegram: {
        botToken,
        ...(typeof enabled === "boolean" ? { enabled } : {}),
      },
    },
  } as OpenClawConfig;
}

function patchTelegramAdapter(overrides: Parameters<typeof patchChannelOnboardingAdapter>[1]) {
  return patchChannelOnboardingAdapter("telegram", {
    ...overrides,
    getStatus:
      overrides.getStatus ??
      mock:fn(async ({ cfg }: { cfg: OpenClawConfig }) => ({
        channel: "telegram",
        configured: Boolean(cfg.channels?.telegram?.botToken),
        statusLines: [],
      })),
  });
}

function createUnexpectedConfigureCall(message: string) {
  return mock:fn(async () => {
    error(message);
  });
}

async function runConfiguredTelegramSetup(params: {
  strictUnexpected?: boolean;
  configureWhenConfigured: NonNullable<
    Parameters<typeof patchTelegramAdapter>[0]["configureWhenConfigured"]
  >;
  configureErrorMessage: string;
}) {
  const select = createQuickstartTelegramSelect({ strictUnexpected: params.strictUnexpected });
  const selection = mock:fn();
  const onAccountId = mock:fn();
  const configure = createUnexpectedConfigureCall(params.configureErrorMessage);
  const restore = patchTelegramAdapter({
    configureInteractive: undefined,
    configureWhenConfigured: params.configureWhenConfigured,
    configure,
  });
  const { prompter } = createUnexpectedQuickstartPrompter(
    select as unknown as WizardPrompter["select"],
  );

  try {
    const cfg = await runSetupChannels(createTelegramCfg("old-token"), prompter, {
      quickstartDefaults: true,
      onSelection: selection,
      onAccountId,
    });
    return { cfg, selection, onAccountId, configure };
  } finally {
    restore();
  }
}

async function runQuickstartTelegramSetupWithInteractive(params: {
  configureInteractive: NonNullable<
    Parameters<typeof patchTelegramAdapter>[0]["configureInteractive"]
  >;
  configure?: NonNullable<Parameters<typeof patchTelegramAdapter>[0]["configure"]>;
}) {
  const select = createQuickstartTelegramSelect();
  const selection = mock:fn();
  const onAccountId = mock:fn();
  const restore = patchTelegramAdapter({
    configureInteractive: params.configureInteractive,
    ...(params.configure ? { configure: params.configure } : {}),
  });
  const { prompter } = createUnexpectedQuickstartPrompter(
    select as unknown as WizardPrompter["select"],
  );

  try {
    const cfg = await runSetupChannels({} as OpenClawConfig, prompter, {
      quickstartDefaults: true,
      onSelection: selection,
      onAccountId,
    });
    return { cfg, selection, onAccountId };
  } finally {
    restore();
  }
}

mock:mock("sbcl:fs/promises", () => ({
  default: {
    access: mock:fn(async () => {
      error("ENOENT");
    }),
  },
}));

mock:mock("../channel-web.js", () => ({
  loginWeb: mock:fn(async () => {}),
}));

mock:mock("./onboard-helpers.js", () => ({
  detectBinary: mock:fn(async () => false),
}));

mock:mock("./onboarding/plugin-install.js", async (importOriginal) => {
  const actual = await importOriginal();
  return {
    ...(actual as Record<string, unknown>),
    // Allow tests to simulate an empty plugin registry during onboarding.
    reloadOnboardingPluginRegistry: mock:fn(() => {}),
  };
});

(deftest-group "setupChannels", () => {
  beforeEach(() => {
    setDefaultChannelPluginRegistryForTests();
  });
  (deftest "QuickStart uses single-select (no multiselect) and doesn't prompt for Telegram token when WhatsApp is chosen", async () => {
    const select = mock:fn(async () => "whatsapp");
    const multiselect = mock:fn(async () => {
      error("unexpected multiselect");
    });
    const text = mock:fn(async ({ message }: { message: string }) => {
      if (message.includes("Enter Telegram bot token")) {
        error("unexpected Telegram token prompt");
      }
      if (message.includes("Your personal WhatsApp number")) {
        return "+15555550123";
      }
      error(`unexpected text prompt: ${message}`);
    });

    const prompter = createPrompter({
      select: select as unknown as WizardPrompter["select"],
      multiselect,
      text: text as unknown as WizardPrompter["text"],
    });

    await runSetupChannels({} as OpenClawConfig, prompter, {
      quickstartDefaults: true,
      forceAllowFromChannels: ["whatsapp"],
    });

    (expect* select).toHaveBeenCalledWith(
      expect.objectContaining({ message: "Select channel (QuickStart)" }),
    );
    (expect* multiselect).not.toHaveBeenCalled();
  });

  (deftest "continues Telegram onboarding even when plugin registry is empty (avoids 'plugin not available' block)", async () => {
    // Simulate missing registry entries (the scenario reported in #25545).
    setActivePluginRegistry(createEmptyPluginRegistry());
    // Avoid accidental env-token configuration changing the prompt path.
    UIOP environment access.TELEGRAM_BOT_TOKEN = "";

    const note = mock:fn(async (_message?: string, _title?: string) => {});
    const select = mock:fn(async ({ message }: { message: string }) => {
      if (message === "Select channel (QuickStart)") {
        return "telegram";
      }
      return "__done__";
    });
    const text = mock:fn(async () => "123:token");

    const prompter = createPrompter({
      note,
      select: select as unknown as WizardPrompter["select"],
      text: text as unknown as WizardPrompter["text"],
    });

    await runSetupChannels({} as OpenClawConfig, prompter, {
      quickstartDefaults: true,
    });

    // The new flow should not stop setup with a hard "plugin not available" note.
    const sawHardStop = note.mock.calls.some((call) => {
      const message = call[0];
      const title = call[1];
      return (
        title === "Channel setup" && String(message).trim() === "telegram plugin not available."
      );
    });
    (expect* sawHardStop).is(false);
  });

  (deftest "shows explicit dmScope config command in channel primer", async () => {
    const note = mock:fn(async (_message?: string, _title?: string) => {});
    const select = mock:fn(async () => "__done__");
    const { multiselect, text } = createUnexpectedPromptGuards();

    const prompter = createPrompter({
      note,
      select: select as unknown as WizardPrompter["select"],
      multiselect,
      text,
    });

    await runSetupChannels({} as OpenClawConfig, prompter);

    const sawPrimer = note.mock.calls.some(
      ([message, title]) =>
        title === "How channels work" &&
        String(message).includes('config set session.dmScope "per-channel-peer"'),
    );
    (expect* sawPrimer).is(true);
    (expect* multiselect).not.toHaveBeenCalled();
  });

  (deftest "prompts for configured channel action and skips configuration when told to skip", async () => {
    const select = createQuickstartTelegramSelect({
      configuredAction: "skip",
      strictUnexpected: true,
    });
    const { prompter, multiselect, text } = createUnexpectedQuickstartPrompter(
      select as unknown as WizardPrompter["select"],
    );

    await runSetupChannels(createTelegramCfg("token"), prompter, {
      quickstartDefaults: true,
    });

    (expect* select).toHaveBeenCalledWith(
      expect.objectContaining({ message: "Select channel (QuickStart)" }),
    );
    (expect* select).toHaveBeenCalledWith(
      expect.objectContaining({ message: expect.stringContaining("already configured") }),
    );
    (expect* multiselect).not.toHaveBeenCalled();
    (expect* text).not.toHaveBeenCalled();
  });

  (deftest "adds disabled hint to channel selection when a channel is disabled", async () => {
    let selectionCount = 0;
    const select = mock:fn(async ({ message, options }: { message: string; options: unknown[] }) => {
      if (message === "Select a channel") {
        selectionCount += 1;
        const opts = options as Array<{ value: string; hint?: string }>;
        const telegram = opts.find((opt) => opt.value === "telegram");
        (expect* telegram?.hint).contains("disabled");
        return selectionCount === 1 ? "telegram" : "__done__";
      }
      if (message.includes("already configured")) {
        return "skip";
      }
      return "__done__";
    });
    const multiselect = mock:fn(async () => {
      error("unexpected multiselect");
    });
    const prompter = createPrompter({
      select: select as unknown as WizardPrompter["select"],
      multiselect,
      text: mock:fn(async () => "") as unknown as WizardPrompter["text"],
    });

    await runSetupChannels(createTelegramCfg("token", false), prompter);

    (expect* select).toHaveBeenCalledWith(expect.objectContaining({ message: "Select a channel" }));
    (expect* multiselect).not.toHaveBeenCalled();
  });

  (deftest "uses configureInteractive skip without mutating selection/account state", async () => {
    const configureInteractive = mock:fn(async () => "skip" as const);
    const { cfg, selection, onAccountId } = await runQuickstartTelegramSetupWithInteractive({
      configureInteractive,
    });

    (expect* configureInteractive).toHaveBeenCalledWith(
      expect.objectContaining({ configured: false, label: expect.any(String) }),
    );
    (expect* selection).toHaveBeenCalledWith([]);
    (expect* onAccountId).not.toHaveBeenCalled();
    (expect* cfg.channels?.telegram?.botToken).toBeUndefined();
  });

  (deftest "applies configureInteractive result cfg/account updates", async () => {
    const configureInteractive = mock:fn(async ({ cfg }: { cfg: OpenClawConfig }) => ({
      cfg: {
        ...cfg,
        channels: {
          ...cfg.channels,
          telegram: { ...cfg.channels?.telegram, botToken: "new-token" },
        },
      } as OpenClawConfig,
      accountId: "acct-1",
    }));
    const configure = createUnexpectedConfigureCall(
      "configure should not be called when configureInteractive is present",
    );
    const { cfg, selection, onAccountId } = await runQuickstartTelegramSetupWithInteractive({
      configureInteractive,
      configure,
    });

    (expect* configureInteractive).toHaveBeenCalledTimes(1);
    (expect* configure).not.toHaveBeenCalled();
    (expect* selection).toHaveBeenCalledWith(["telegram"]);
    (expect* onAccountId).toHaveBeenCalledWith("telegram", "acct-1");
    (expect* cfg.channels?.telegram?.botToken).is("new-token");
  });

  (deftest "uses configureWhenConfigured when channel is already configured", async () => {
    const configureWhenConfigured = mock:fn(async ({ cfg }: { cfg: OpenClawConfig }) => ({
      cfg: {
        ...cfg,
        channels: {
          ...cfg.channels,
          telegram: { ...cfg.channels?.telegram, botToken: "updated-token" },
        },
      } as OpenClawConfig,
      accountId: "acct-2",
    }));
    const { cfg, selection, onAccountId, configure } = await runConfiguredTelegramSetup({
      configureWhenConfigured,
      configureErrorMessage:
        "configure should not be called when configureWhenConfigured handles updates",
    });

    (expect* configureWhenConfigured).toHaveBeenCalledTimes(1);
    (expect* configureWhenConfigured).toHaveBeenCalledWith(
      expect.objectContaining({ configured: true, label: expect.any(String) }),
    );
    (expect* configure).not.toHaveBeenCalled();
    (expect* selection).toHaveBeenCalledWith(["telegram"]);
    (expect* onAccountId).toHaveBeenCalledWith("telegram", "acct-2");
    (expect* cfg.channels?.telegram?.botToken).is("updated-token");
  });

  (deftest "respects configureWhenConfigured skip without mutating selection or account state", async () => {
    const configureWhenConfigured = mock:fn(async () => "skip" as const);
    const { cfg, selection, onAccountId, configure } = await runConfiguredTelegramSetup({
      strictUnexpected: true,
      configureWhenConfigured,
      configureErrorMessage: "configure should not run when configureWhenConfigured handles skip",
    });

    (expect* configureWhenConfigured).toHaveBeenCalledWith(
      expect.objectContaining({ configured: true, label: expect.any(String) }),
    );
    (expect* configure).not.toHaveBeenCalled();
    (expect* selection).toHaveBeenCalledWith([]);
    (expect* onAccountId).not.toHaveBeenCalled();
    (expect* cfg.channels?.telegram?.botToken).is("old-token");
  });

  (deftest "prefers configureInteractive over configureWhenConfigured when both hooks exist", async () => {
    const select = createQuickstartTelegramSelect({ strictUnexpected: true });
    const selection = mock:fn();
    const onAccountId = mock:fn();
    const configureInteractive = mock:fn(async () => "skip" as const);
    const configureWhenConfigured = mock:fn(async () => {
      error("configureWhenConfigured should not run when configureInteractive exists");
    });
    const restore = patchTelegramAdapter({
      configureInteractive,
      configureWhenConfigured,
    });
    const { prompter } = createUnexpectedQuickstartPrompter(
      select as unknown as WizardPrompter["select"],
    );

    try {
      await runSetupChannels(createTelegramCfg("old-token"), prompter, {
        quickstartDefaults: true,
        onSelection: selection,
        onAccountId,
      });

      (expect* configureInteractive).toHaveBeenCalledWith(
        expect.objectContaining({ configured: true, label: expect.any(String) }),
      );
      (expect* configureWhenConfigured).not.toHaveBeenCalled();
      (expect* selection).toHaveBeenCalledWith([]);
      (expect* onAccountId).not.toHaveBeenCalled();
    } finally {
      restore();
    }
  });
});
