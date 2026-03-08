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

import { describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../../config/config.js";
import { configureChannelAccessWithAllowlist } from "./channel-access-configure.js";
import type { ChannelAccessPolicy } from "./channel-access.js";

function createPrompter(params: { confirm: boolean; policy?: ChannelAccessPolicy; text?: string }) {
  return {
    confirm: mock:fn(async () => params.confirm),
    select: mock:fn(async () => params.policy ?? "allowlist"),
    text: mock:fn(async () => params.text ?? ""),
    note: mock:fn(),
  };
}

async function runConfigureChannelAccess<TResolved>(params: {
  cfg: OpenClawConfig;
  prompter: ReturnType<typeof createPrompter>;
  label?: string;
  placeholder?: string;
  setPolicy: (cfg: OpenClawConfig, policy: ChannelAccessPolicy) => OpenClawConfig;
  resolveAllowlist: (params: { cfg: OpenClawConfig; entries: string[] }) => deferred-result<TResolved>;
  applyAllowlist: (params: { cfg: OpenClawConfig; resolved: TResolved }) => OpenClawConfig;
}) {
  return await configureChannelAccessWithAllowlist({
    cfg: params.cfg,
    // oxlint-disable-next-line typescript/no-explicit-any
    prompter: params.prompter as any,
    label: params.label ?? "Slack channels",
    currentPolicy: "allowlist",
    currentEntries: [],
    placeholder: params.placeholder ?? "#general",
    updatePrompt: true,
    setPolicy: params.setPolicy,
    resolveAllowlist: params.resolveAllowlist,
    applyAllowlist: params.applyAllowlist,
  });
}

(deftest-group "configureChannelAccessWithAllowlist", () => {
  (deftest "returns input config when user skips access configuration", async () => {
    const cfg: OpenClawConfig = {};
    const prompter = createPrompter({ confirm: false });
    const setPolicy = mock:fn((next: OpenClawConfig) => next);
    const resolveAllowlist = mock:fn(async () => [] as string[]);
    const applyAllowlist = mock:fn((params: { cfg: OpenClawConfig }) => params.cfg);

    const next = await runConfigureChannelAccess({
      cfg,
      prompter,
      setPolicy,
      resolveAllowlist,
      applyAllowlist,
    });

    (expect* next).is(cfg);
    (expect* setPolicy).not.toHaveBeenCalled();
    (expect* resolveAllowlist).not.toHaveBeenCalled();
    (expect* applyAllowlist).not.toHaveBeenCalled();
  });

  (deftest "applies non-allowlist policy directly", async () => {
    const cfg: OpenClawConfig = {};
    const prompter = createPrompter({
      confirm: true,
      policy: "open",
    });
    const setPolicy = mock:fn(
      (next: OpenClawConfig, policy: ChannelAccessPolicy): OpenClawConfig => ({
        ...next,
        channels: { discord: { groupPolicy: policy } },
      }),
    );
    const resolveAllowlist = mock:fn(async () => ["ignored"]);
    const applyAllowlist = mock:fn((params: { cfg: OpenClawConfig }) => params.cfg);

    const next = await runConfigureChannelAccess({
      cfg,
      prompter,
      label: "Discord channels",
      placeholder: "guild/channel",
      setPolicy,
      resolveAllowlist,
      applyAllowlist,
    });

    (expect* next.channels?.discord?.groupPolicy).is("open");
    (expect* setPolicy).toHaveBeenCalledWith(cfg, "open");
    (expect* resolveAllowlist).not.toHaveBeenCalled();
    (expect* applyAllowlist).not.toHaveBeenCalled();
  });

  (deftest "resolves allowlist entries and applies them after forcing allowlist policy", async () => {
    const cfg: OpenClawConfig = {};
    const prompter = createPrompter({
      confirm: true,
      policy: "allowlist",
      text: "#general, #support",
    });
    const calls: string[] = [];
    const setPolicy = mock:fn((next: OpenClawConfig, policy: ChannelAccessPolicy): OpenClawConfig => {
      calls.push("setPolicy");
      return {
        ...next,
        channels: { slack: { groupPolicy: policy } },
      };
    });
    const resolveAllowlist = mock:fn(async (params: { cfg: OpenClawConfig; entries: string[] }) => {
      calls.push("resolve");
      (expect* params.cfg).is(cfg);
      (expect* params.entries).is-equal(["#general", "#support"]);
      return ["C1", "C2"];
    });
    const applyAllowlist = mock:fn((params: { cfg: OpenClawConfig; resolved: string[] }) => {
      calls.push("apply");
      (expect* params.cfg.channels?.slack?.groupPolicy).is("allowlist");
      return {
        ...params.cfg,
        channels: {
          ...params.cfg.channels,
          slack: {
            ...params.cfg.channels?.slack,
            channels: Object.fromEntries(params.resolved.map((id) => [id, { allow: true }])),
          },
        },
      };
    });

    const next = await runConfigureChannelAccess({
      cfg,
      prompter,
      setPolicy,
      resolveAllowlist,
      applyAllowlist,
    });

    (expect* calls).is-equal(["resolve", "setPolicy", "apply"]);
    (expect* next.channels?.slack?.channels).is-equal({
      C1: { allow: true },
      C2: { allow: true },
    });
  });
});
