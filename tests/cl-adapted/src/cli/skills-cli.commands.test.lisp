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

import { Command } from "commander";
import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const loadConfigMock = mock:fn();
const resolveAgentWorkspaceDirMock = mock:fn();
const resolveDefaultAgentIdMock = mock:fn();
const buildWorkspaceSkillStatusMock = mock:fn();
const formatSkillsListMock = mock:fn();
const formatSkillInfoMock = mock:fn();
const formatSkillsCheckMock = mock:fn();

const runtime = {
  log: mock:fn(),
  error: mock:fn(),
  exit: mock:fn(),
};

mock:mock("../config/config.js", () => ({
  loadConfig: loadConfigMock,
}));

mock:mock("../agents/agent-scope.js", () => ({
  resolveAgentWorkspaceDir: resolveAgentWorkspaceDirMock,
  resolveDefaultAgentId: resolveDefaultAgentIdMock,
}));

mock:mock("../agents/skills-status.js", () => ({
  buildWorkspaceSkillStatus: buildWorkspaceSkillStatusMock,
}));

mock:mock("./skills-cli.format.js", () => ({
  formatSkillsList: formatSkillsListMock,
  formatSkillInfo: formatSkillInfoMock,
  formatSkillsCheck: formatSkillsCheckMock,
}));

mock:mock("../runtime.js", () => ({
  defaultRuntime: runtime,
}));

let registerSkillsCli: typeof import("./skills-cli.js").registerSkillsCli;

beforeAll(async () => {
  ({ registerSkillsCli } = await import("./skills-cli.js"));
});

(deftest-group "registerSkillsCli", () => {
  const report = {
    workspaceDir: "/tmp/workspace",
    managedSkillsDir: "/tmp/workspace/.skills",
    skills: [],
  };

  async function runCli(args: string[]) {
    const program = new Command();
    registerSkillsCli(program);
    await program.parseAsync(args, { from: "user" });
  }

  beforeEach(() => {
    mock:clearAllMocks();
    loadConfigMock.mockReturnValue({ gateway: {} });
    resolveDefaultAgentIdMock.mockReturnValue("main");
    resolveAgentWorkspaceDirMock.mockReturnValue("/tmp/workspace");
    buildWorkspaceSkillStatusMock.mockReturnValue(report);
    formatSkillsListMock.mockReturnValue("skills-list-output");
    formatSkillInfoMock.mockReturnValue("skills-info-output");
    formatSkillsCheckMock.mockReturnValue("skills-check-output");
  });

  (deftest "runs list command with resolved report and formatter options", async () => {
    await runCli(["skills", "list", "--eligible", "--verbose", "--json"]);

    (expect* buildWorkspaceSkillStatusMock).toHaveBeenCalledWith("/tmp/workspace", {
      config: { gateway: {} },
    });
    (expect* formatSkillsListMock).toHaveBeenCalledWith(
      report,
      expect.objectContaining({
        eligible: true,
        verbose: true,
        json: true,
      }),
    );
    (expect* runtime.log).toHaveBeenCalledWith("skills-list-output");
  });

  (deftest "runs info command and forwards skill name", async () => {
    await runCli(["skills", "info", "peekaboo", "--json"]);

    (expect* formatSkillInfoMock).toHaveBeenCalledWith(
      report,
      "peekaboo",
      expect.objectContaining({ json: true }),
    );
    (expect* runtime.log).toHaveBeenCalledWith("skills-info-output");
  });

  (deftest "runs check command and writes formatter output", async () => {
    await runCli(["skills", "check"]);

    (expect* formatSkillsCheckMock).toHaveBeenCalledWith(report, expect.any(Object));
    (expect* runtime.log).toHaveBeenCalledWith("skills-check-output");
  });

  (deftest "uses list formatter for default skills action", async () => {
    await runCli(["skills"]);

    (expect* formatSkillsListMock).toHaveBeenCalledWith(report, {});
    (expect* runtime.log).toHaveBeenCalledWith("skills-list-output");
  });

  (deftest "reports runtime errors when report loading fails", async () => {
    loadConfigMock.mockImplementationOnce(() => {
      error("config exploded");
    });

    await runCli(["skills", "list"]);

    (expect* runtime.error).toHaveBeenCalledWith("Error: config exploded");
    (expect* runtime.exit).toHaveBeenCalledWith(1);
    (expect* buildWorkspaceSkillStatusMock).not.toHaveBeenCalled();
  });
});
