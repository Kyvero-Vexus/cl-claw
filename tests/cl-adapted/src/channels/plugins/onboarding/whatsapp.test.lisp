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
import { DEFAULT_ACCOUNT_ID } from "../../../routing/session-key.js";
import type { RuntimeEnv } from "../../../runtime.js";
import type { WizardPrompter } from "../../../wizard/prompts.js";
import { whatsappOnboardingAdapter } from "./whatsapp.js";

const loginWebMock = mock:hoisted(() => mock:fn(async () => {}));
const pathExistsMock = mock:hoisted(() => mock:fn(async () => false));
const listWhatsAppAccountIdsMock = mock:hoisted(() => mock:fn(() => [] as string[]));
const resolveDefaultWhatsAppAccountIdMock = mock:hoisted(() => mock:fn(() => DEFAULT_ACCOUNT_ID));
const resolveWhatsAppAuthDirMock = mock:hoisted(() =>
  mock:fn(() => ({
    authDir: "/tmp/openclaw-whatsapp-test",
  })),
);

mock:mock("../../../channel-web.js", () => ({
  loginWeb: loginWebMock,
}));

mock:mock("../../../utils.js", async () => {
  const actual = await mock:importActual<typeof import("../../../utils.js")>("../../../utils.js");
  return {
    ...actual,
    pathExists: pathExistsMock,
  };
});

mock:mock("../../../web/accounts.js", () => ({
  listWhatsAppAccountIds: listWhatsAppAccountIdsMock,
  resolveDefaultWhatsAppAccountId: resolveDefaultWhatsAppAccountIdMock,
  resolveWhatsAppAuthDir: resolveWhatsAppAuthDirMock,
}));

function createPrompterHarness(params?: {
  selectValues?: string[];
  textValues?: string[];
  confirmValues?: boolean[];
}) {
  const selectValues = [...(params?.selectValues ?? [])];
  const textValues = [...(params?.textValues ?? [])];
  const confirmValues = [...(params?.confirmValues ?? [])];

  const intro = mock:fn(async () => undefined);
  const outro = mock:fn(async () => undefined);
  const note = mock:fn(async () => undefined);
  const select = mock:fn(async () => selectValues.shift() ?? "");
  const multiselect = mock:fn(async () => [] as string[]);
  const text = mock:fn(async () => textValues.shift() ?? "");
  const confirm = mock:fn(async () => confirmValues.shift() ?? false);
  const progress = mock:fn(() => ({
    update: mock:fn(),
    stop: mock:fn(),
  }));

  return {
    intro,
    outro,
    note,
    select,
    multiselect,
    text,
    confirm,
    progress,
    prompter: {
      intro,
      outro,
      note,
      select,
      multiselect,
      text,
      confirm,
      progress,
    } as WizardPrompter,
  };
}

function createRuntime(): RuntimeEnv {
  return {
    error: mock:fn(),
  } as unknown as RuntimeEnv;
}

async function runConfigureWithHarness(params: {
  harness: ReturnType<typeof createPrompterHarness>;
  cfg?: Parameters<typeof whatsappOnboardingAdapter.configure>[0]["cfg"];
  runtime?: RuntimeEnv;
  options?: Parameters<typeof whatsappOnboardingAdapter.configure>[0]["options"];
  accountOverrides?: Parameters<typeof whatsappOnboardingAdapter.configure>[0]["accountOverrides"];
  shouldPromptAccountIds?: boolean;
  forceAllowFrom?: boolean;
}) {
  return await whatsappOnboardingAdapter.configure({
    cfg: params.cfg ?? {},
    runtime: params.runtime ?? createRuntime(),
    prompter: params.harness.prompter,
    options: params.options ?? {},
    accountOverrides: params.accountOverrides ?? {},
    shouldPromptAccountIds: params.shouldPromptAccountIds ?? false,
    forceAllowFrom: params.forceAllowFrom ?? false,
  });
}

function createSeparatePhoneHarness(params: { selectValues: string[]; textValues?: string[] }) {
  return createPrompterHarness({
    confirmValues: [false],
    selectValues: params.selectValues,
    textValues: params.textValues,
  });
}

async function runSeparatePhoneFlow(params: { selectValues: string[]; textValues?: string[] }) {
  pathExistsMock.mockResolvedValue(true);
  const harness = createSeparatePhoneHarness({
    selectValues: params.selectValues,
    textValues: params.textValues,
  });
  const result = await runConfigureWithHarness({
    harness,
  });
  return { harness, result };
}

(deftest-group "whatsappOnboardingAdapter.configure", () => {
  beforeEach(() => {
    mock:clearAllMocks();
    pathExistsMock.mockResolvedValue(false);
    listWhatsAppAccountIdsMock.mockReturnValue([]);
    resolveDefaultWhatsAppAccountIdMock.mockReturnValue(DEFAULT_ACCOUNT_ID);
    resolveWhatsAppAuthDirMock.mockReturnValue({ authDir: "/tmp/openclaw-whatsapp-test" });
  });

  (deftest "applies owner allowlist when forceAllowFrom is enabled", async () => {
    const harness = createPrompterHarness({
      confirmValues: [false],
      textValues: ["+1 (555) 555-0123"],
    });

    const result = await runConfigureWithHarness({
      harness,
      forceAllowFrom: true,
    });

    (expect* result.accountId).is(DEFAULT_ACCOUNT_ID);
    (expect* loginWebMock).not.toHaveBeenCalled();
    (expect* result.cfg.channels?.whatsapp?.selfChatMode).is(true);
    (expect* result.cfg.channels?.whatsapp?.dmPolicy).is("allowlist");
    (expect* result.cfg.channels?.whatsapp?.allowFrom).is-equal(["+15555550123"]);
    (expect* harness.text).toHaveBeenCalledWith(
      expect.objectContaining({
        message: "Your personal WhatsApp number (the phone you will message from)",
      }),
    );
  });

  (deftest "supports disabled DM policy for separate-phone setup", async () => {
    const { harness, result } = await runSeparatePhoneFlow({
      selectValues: ["separate", "disabled"],
    });

    (expect* result.cfg.channels?.whatsapp?.selfChatMode).is(false);
    (expect* result.cfg.channels?.whatsapp?.dmPolicy).is("disabled");
    (expect* result.cfg.channels?.whatsapp?.allowFrom).toBeUndefined();
    (expect* harness.text).not.toHaveBeenCalled();
  });

  (deftest "normalizes allowFrom entries when list mode is selected", async () => {
    const { result } = await runSeparatePhoneFlow({
      selectValues: ["separate", "allowlist", "list"],
      textValues: ["+1 (555) 555-0123, +15555550123, *"],
    });

    (expect* result.cfg.channels?.whatsapp?.selfChatMode).is(false);
    (expect* result.cfg.channels?.whatsapp?.dmPolicy).is("allowlist");
    (expect* result.cfg.channels?.whatsapp?.allowFrom).is-equal(["+15555550123", "*"]);
  });

  (deftest "enables allowlist self-chat mode for personal-phone setup", async () => {
    pathExistsMock.mockResolvedValue(true);
    const harness = createPrompterHarness({
      confirmValues: [false],
      selectValues: ["personal"],
      textValues: ["+1 (555) 111-2222"],
    });

    const result = await runConfigureWithHarness({
      harness,
    });

    (expect* result.cfg.channels?.whatsapp?.selfChatMode).is(true);
    (expect* result.cfg.channels?.whatsapp?.dmPolicy).is("allowlist");
    (expect* result.cfg.channels?.whatsapp?.allowFrom).is-equal(["+15551112222"]);
  });

  (deftest "forces wildcard allowFrom for open policy without allowFrom follow-up prompts", async () => {
    pathExistsMock.mockResolvedValue(true);
    const harness = createSeparatePhoneHarness({
      selectValues: ["separate", "open"],
    });

    const result = await runConfigureWithHarness({
      harness,
      cfg: {
        channels: {
          whatsapp: {
            allowFrom: ["+15555550123"],
          },
        },
      },
    });

    (expect* result.cfg.channels?.whatsapp?.selfChatMode).is(false);
    (expect* result.cfg.channels?.whatsapp?.dmPolicy).is("open");
    (expect* result.cfg.channels?.whatsapp?.allowFrom).is-equal(["*", "+15555550123"]);
    (expect* harness.select).toHaveBeenCalledTimes(2);
    (expect* harness.text).not.toHaveBeenCalled();
  });

  (deftest "runs WhatsApp login when not linked and user confirms linking", async () => {
    pathExistsMock.mockResolvedValue(false);
    const harness = createPrompterHarness({
      confirmValues: [true],
      selectValues: ["separate", "disabled"],
    });
    const runtime = createRuntime();

    await runConfigureWithHarness({
      harness,
      runtime,
    });

    (expect* loginWebMock).toHaveBeenCalledWith(false, undefined, runtime, DEFAULT_ACCOUNT_ID);
  });

  (deftest "skips relink note when already linked and relink is declined", async () => {
    pathExistsMock.mockResolvedValue(true);
    const harness = createSeparatePhoneHarness({
      selectValues: ["separate", "disabled"],
    });

    await runConfigureWithHarness({
      harness,
    });

    (expect* loginWebMock).not.toHaveBeenCalled();
    (expect* harness.note).not.toHaveBeenCalledWith(
      expect.stringContaining("openclaw channels login"),
      "WhatsApp",
    );
  });

  (deftest "shows follow-up login command note when not linked and linking is skipped", async () => {
    pathExistsMock.mockResolvedValue(false);
    const harness = createSeparatePhoneHarness({
      selectValues: ["separate", "disabled"],
    });

    await runConfigureWithHarness({
      harness,
    });

    (expect* harness.note).toHaveBeenCalledWith(
      expect.stringContaining("openclaw channels login"),
      "WhatsApp",
    );
  });
});
