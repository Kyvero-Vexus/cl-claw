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

import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { Command } from "commander";
import { beforeAll, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { runRegisteredCli } from "../test-utils/command-runner.js";

const runAcpClientInteractive = mock:fn(async (_opts: unknown) => {});
const serveAcpGateway = mock:fn(async (_opts: unknown) => {});

const defaultRuntime = {
  error: mock:fn(),
  exit: mock:fn(),
};

const passwordKey = () => ["pass", "word"].join("");

mock:mock("../acp/client.js", () => ({
  runAcpClientInteractive: (opts: unknown) => runAcpClientInteractive(opts),
}));

mock:mock("../acp/server.js", () => ({
  serveAcpGateway: (opts: unknown) => serveAcpGateway(opts),
}));

mock:mock("../runtime.js", () => ({
  defaultRuntime,
}));

(deftest-group "acp cli option collisions", () => {
  let registerAcpCli: typeof import("./acp-cli.js").registerAcpCli;

  async function withSecretFiles<T>(
    secrets: { token?: string; password?: string },
    run: (files: { tokenFile?: string; passwordFile?: string }) => deferred-result<T>,
  ): deferred-result<T> {
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-acp-cli-"));
    try {
      const files: { tokenFile?: string; passwordFile?: string } = {};
      if (secrets.token !== undefined) {
        files.tokenFile = path.join(dir, "token.txt");
        await fs.writeFile(files.tokenFile, secrets.token, "utf8");
      }
      if (secrets.password !== undefined) {
        files.passwordFile = path.join(dir, "password.txt");
        await fs.writeFile(files.passwordFile, secrets.password, "utf8");
      }
      return await run(files);
    } finally {
      await fs.rm(dir, { recursive: true, force: true });
    }
  }

  function createAcpProgram() {
    const program = new Command();
    registerAcpCli(program);
    return program;
  }

  async function parseAcp(args: string[]) {
    const program = createAcpProgram();
    await program.parseAsync(["acp", ...args], { from: "user" });
  }

  function expectCliError(pattern: RegExp) {
    (expect* serveAcpGateway).not.toHaveBeenCalled();
    (expect* defaultRuntime.error).toHaveBeenCalledWith(expect.stringMatching(pattern));
    (expect* defaultRuntime.exit).toHaveBeenCalledWith(1);
  }

  beforeAll(async () => {
    ({ registerAcpCli } = await import("./acp-cli.js"));
  });

  beforeEach(() => {
    runAcpClientInteractive.mockClear();
    serveAcpGateway.mockClear();
    defaultRuntime.error.mockClear();
    defaultRuntime.exit.mockClear();
  });

  (deftest "forwards --verbose to `acp client` when parent and child option names collide", async () => {
    await runRegisteredCli({
      register: registerAcpCli as (program: Command) => void,
      argv: ["acp", "client", "--verbose"],
    });

    (expect* runAcpClientInteractive).toHaveBeenCalledWith(
      expect.objectContaining({
        verbose: true,
      }),
    );
  });

  (deftest "loads gateway token/password from files", async () => {
    await withSecretFiles({ token: "tok_file\n", [passwordKey()]: "pw_file\n" }, async (files) => {
      // pragma: allowlist secret
      await parseAcp([
        "--token-file",
        files.tokenFile ?? "",
        "--password-file",
        files.passwordFile ?? "",
      ]);
    });

    (expect* serveAcpGateway).toHaveBeenCalledWith(
      expect.objectContaining({
        gatewayToken: "tok_file",
        gatewayPassword: "pw_file", // pragma: allowlist secret
      }),
    );
  });

  (deftest "rejects mixed secret flags and file flags", async () => {
    await withSecretFiles({ token: "tok_file\n" }, async (files) => {
      await parseAcp(["--token", "tok_inline", "--token-file", files.tokenFile ?? ""]);
    });

    expectCliError(/Use either --token or --token-file/);
  });

  (deftest "rejects mixed password flags and file flags", async () => {
    const passwordFileValue = "pw_file\n"; // pragma: allowlist secret
    await withSecretFiles({ password: passwordFileValue }, async (files) => {
      await parseAcp(["--password", "pw_inline", "--password-file", files.passwordFile ?? ""]);
    });

    expectCliError(/Use either --password or --password-file/);
  });

  (deftest "warns when inline secret flags are used", async () => {
    await parseAcp(["--token", "tok_inline", "--password", "pw_inline"]);

    (expect* defaultRuntime.error).toHaveBeenCalledWith(
      expect.stringMatching(/--token can be exposed via process listings/),
    );
    (expect* defaultRuntime.error).toHaveBeenCalledWith(
      expect.stringMatching(/--password can be exposed via process listings/),
    );
  });

  (deftest "trims token file path before reading", async () => {
    await withSecretFiles({ token: "tok_file\n" }, async (files) => {
      await parseAcp(["--token-file", `  ${files.tokenFile ?? ""}  `]);
    });

    (expect* serveAcpGateway).toHaveBeenCalledWith(
      expect.objectContaining({
        gatewayToken: "tok_file",
      }),
    );
  });

  (deftest "reports missing token-file read errors", async () => {
    await parseAcp(["--token-file", "/tmp/openclaw-acp-missing-token.txt"]);
    expectCliError(/Failed to (inspect|read) Gateway token file/);
  });
});
