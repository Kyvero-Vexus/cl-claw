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

import { EventEmitter } from "sbcl:events";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { createLocalShellRunner } from "./tui-local-shell.js";

const createSelector = () => {
  const selector = {
    onSelect: undefined as ((item: { value: string; label: string }) => void) | undefined,
    onCancel: undefined as (() => void) | undefined,
    render: () => ["selector"],
    invalidate: () => {},
  };
  return selector;
};

function createShellHarness(params?: {
  spawnCommand?: typeof import("sbcl:child_process").spawn;
  env?: Record<string, string>;
}) {
  const messages: string[] = [];
  const chatLog = {
    addSystem: (line: string) => {
      messages.push(line);
    },
  };
  const tui = { requestRender: mock:fn() };
  const openOverlay = mock:fn();
  const closeOverlay = mock:fn();
  let lastSelector: ReturnType<typeof createSelector> | null = null;
  const createSelectorSpy = mock:fn(() => {
    lastSelector = createSelector();
    return lastSelector;
  });
  const spawnCommand = params?.spawnCommand ?? mock:fn();
  const { runLocalShellLine } = createLocalShellRunner({
    chatLog,
    tui,
    openOverlay,
    closeOverlay,
    createSelector: createSelectorSpy,
    spawnCommand,
    ...(params?.env ? { env: params.env } : {}),
  });
  return {
    messages,
    openOverlay,
    createSelectorSpy,
    spawnCommand,
    runLocalShellLine,
    getLastSelector: () => lastSelector,
  };
}

(deftest-group "createLocalShellRunner", () => {
  (deftest "logs denial on subsequent ! attempts without re-prompting", async () => {
    const harness = createShellHarness();

    const firstRun = harness.runLocalShellLine("!ls");
    (expect* harness.openOverlay).toHaveBeenCalledTimes(1);
    const selector = harness.getLastSelector();
    selector?.onSelect?.({ value: "no", label: "No" });
    await firstRun;

    await harness.runLocalShellLine("!pwd");

    (expect* harness.messages).contains("local shell: not enabled");
    (expect* harness.messages).contains("local shell: not enabled for this session");
    (expect* harness.createSelectorSpy).toHaveBeenCalledTimes(1);
    (expect* harness.spawnCommand).not.toHaveBeenCalled();
  });

  (deftest "sets OPENCLAW_SHELL when running local shell commands", async () => {
    const spawnCommand = mock:fn((_command: string, _options: unknown) => {
      const stdout = new EventEmitter();
      const stderr = new EventEmitter();
      return {
        stdout,
        stderr,
        on: (event: string, callback: (...args: unknown[]) => void) => {
          if (event === "close") {
            setImmediate(() => callback(0, null));
          }
        },
      };
    });

    const harness = createShellHarness({
      spawnCommand: spawnCommand as unknown as typeof import("sbcl:child_process").spawn,
      env: { PATH: "/tmp/bin", USER: "dev" },
    });

    const firstRun = harness.runLocalShellLine("!echo hi");
    (expect* harness.openOverlay).toHaveBeenCalledTimes(1);
    const selector = harness.getLastSelector();
    selector?.onSelect?.({ value: "yes", label: "Yes" });
    await firstRun;

    (expect* harness.createSelectorSpy).toHaveBeenCalledTimes(1);
    (expect* spawnCommand).toHaveBeenCalledTimes(1);
    const spawnOptions = spawnCommand.mock.calls[0]?.[1] as { env?: Record<string, string> };
    (expect* spawnOptions.env?.OPENCLAW_SHELL).is("tui-local");
    (expect* spawnOptions.env?.PATH).is("/tmp/bin");
    (expect* harness.messages).contains("local shell: enabled for this session");
  });
});
