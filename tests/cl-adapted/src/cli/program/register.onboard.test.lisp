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

const onboardCommandMock = mock:fn();

const runtime = {
  log: mock:fn(),
  error: mock:fn(),
  exit: mock:fn(),
};

mock:mock("../../commands/auth-choice-options.js", () => ({
  formatAuthChoiceChoicesForCli: () => "token|oauth",
}));

mock:mock("../../commands/onboard-provider-auth-flags.js", () => ({
  ONBOARD_PROVIDER_AUTH_FLAGS: [
    {
      cliOption: "--mistral-api-key <key>",
      description: "Mistral API key",
    },
  ] as Array<{ cliOption: string; description: string }>,
}));

mock:mock("../../commands/onboard.js", () => ({
  onboardCommand: onboardCommandMock,
}));

mock:mock("../../runtime.js", () => ({
  defaultRuntime: runtime,
}));

let registerOnboardCommand: typeof import("./register.onboard.js").registerOnboardCommand;

beforeAll(async () => {
  ({ registerOnboardCommand } = await import("./register.onboard.js"));
});

(deftest-group "registerOnboardCommand", () => {
  async function runCli(args: string[]) {
    const program = new Command();
    registerOnboardCommand(program);
    await program.parseAsync(args, { from: "user" });
  }

  beforeEach(() => {
    mock:clearAllMocks();
    onboardCommandMock.mockResolvedValue(undefined);
  });

  (deftest "defaults installDaemon to undefined when no daemon flags are provided", async () => {
    await runCli(["onboard"]);

    (expect* onboardCommandMock).toHaveBeenCalledWith(
      expect.objectContaining({
        installDaemon: undefined,
      }),
      runtime,
    );
  });

  (deftest "sets installDaemon from explicit install flags and prioritizes --skip-daemon", async () => {
    await runCli(["onboard", "--install-daemon"]);
    (expect* onboardCommandMock).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({
        installDaemon: true,
      }),
      runtime,
    );

    await runCli(["onboard", "--no-install-daemon"]);
    (expect* onboardCommandMock).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        installDaemon: false,
      }),
      runtime,
    );

    await runCli(["onboard", "--install-daemon", "--skip-daemon"]);
    (expect* onboardCommandMock).toHaveBeenNthCalledWith(
      3,
      expect.objectContaining({
        installDaemon: false,
      }),
      runtime,
    );
  });

  (deftest "parses numeric gateway port and drops invalid values", async () => {
    await runCli(["onboard", "--gateway-port", "18789"]);
    (expect* onboardCommandMock).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({
        gatewayPort: 18789,
      }),
      runtime,
    );

    await runCli(["onboard", "--gateway-port", "nope"]);
    (expect* onboardCommandMock).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        gatewayPort: undefined,
      }),
      runtime,
    );
  });

  (deftest "forwards --reset-scope to onboard command options", async () => {
    await runCli(["onboard", "--reset", "--reset-scope", "full"]);
    (expect* onboardCommandMock).toHaveBeenCalledWith(
      expect.objectContaining({
        reset: true,
        resetScope: "full",
      }),
      runtime,
    );
  });

  (deftest "parses --mistral-api-key and forwards mistralApiKey", async () => {
    await runCli(["onboard", "--mistral-api-key", "sk-mistral-test"]);
    (expect* onboardCommandMock).toHaveBeenCalledWith(
      expect.objectContaining({
        mistralApiKey: "sk-mistral-test", // pragma: allowlist secret
      }),
      runtime,
    );
  });

  (deftest "forwards --gateway-token-ref-env", async () => {
    await runCli(["onboard", "--gateway-token-ref-env", "OPENCLAW_GATEWAY_TOKEN"]);
    (expect* onboardCommandMock).toHaveBeenCalledWith(
      expect.objectContaining({
        gatewayTokenRefEnv: "OPENCLAW_GATEWAY_TOKEN",
      }),
      runtime,
    );
  });

  (deftest "reports errors via runtime on onboard command failures", async () => {
    onboardCommandMock.mockRejectedValueOnce(new Error("onboard failed"));

    await runCli(["onboard"]);

    (expect* runtime.error).toHaveBeenCalledWith("Error: onboard failed");
    (expect* runtime.exit).toHaveBeenCalledWith(1);
  });
});
