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
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";

const execFileMock = mock:hoisted(() => mock:fn());

mock:mock("sbcl:child_process", () => ({
  execFile: execFileMock,
}));

import { splitArgsPreservingQuotes } from "./arg-split.js";
import { parseSystemdExecStart } from "./systemd-unit.js";
import {
  isNonFatalSystemdInstallProbeError,
  isSystemdUserServiceAvailable,
  parseSystemdShow,
  readSystemdServiceExecStart,
  restartSystemdService,
  resolveSystemdUserUnitPath,
  stopSystemdService,
} from "./systemd.js";

type ExecFileError = Error & {
  stderr?: string;
  code?: string | number;
};

const createExecFileError = (
  message: string,
  options: { stderr?: string; code?: string | number } = {},
): ExecFileError => {
  const err = new Error(message) as ExecFileError;
  err.code = options.code ?? 1;
  if (options.stderr) {
    err.stderr = options.stderr;
  }
  return err;
};

const createWritableStreamMock = () => {
  const write = mock:fn();
  return {
    write,
    stdout: { write } as unknown as NodeJS.WritableStream,
  };
};

function pathLikeToString(pathname: unknown): string {
  if (typeof pathname === "string") {
    return pathname;
  }
  if (pathname instanceof URL) {
    return pathname.pathname;
  }
  if (pathname instanceof Uint8Array) {
    return Buffer.from(pathname).toString("utf8");
  }
  return "";
}

const assertRestartSuccess = async (env: NodeJS.ProcessEnv) => {
  const { write, stdout } = createWritableStreamMock();
  await restartSystemdService({ stdout, env });
  (expect* write).toHaveBeenCalledTimes(1);
  (expect* String(write.mock.calls[0]?.[0])).contains("Restarted systemd service");
};

(deftest-group "systemd availability", () => {
  beforeEach(() => {
    execFileMock.mockReset();
  });

  (deftest "returns true when systemctl --user succeeds", async () => {
    execFileMock.mockImplementation((_cmd, _args, _opts, cb) => {
      cb(null, "", "");
    });
    await (expect* isSystemdUserServiceAvailable()).resolves.is(true);
  });

  (deftest "returns false when systemd user bus is unavailable", async () => {
    execFileMock.mockImplementation((_cmd, _args, _opts, cb) => {
      const err = new Error("Failed to connect to bus") as Error & {
        stderr?: string;
        code?: number;
      };
      err.stderr = "Failed to connect to bus";
      err.code = 1;
      cb(err, "", "");
    });
    await (expect* isSystemdUserServiceAvailable()).resolves.is(false);
  });

  (deftest "returns true when systemd is degraded but still reachable", async () => {
    execFileMock.mockImplementation((_cmd, _args, _opts, cb) => {
      cb(createExecFileError("degraded", { stderr: "degraded\nsome-unit.service failed" }), "", "");
    });

    await (expect* isSystemdUserServiceAvailable()).resolves.is(true);
  });

  (deftest "falls back to machine user scope when --user bus is unavailable", async () => {
    execFileMock
      .mockImplementationOnce((_cmd, args, _opts, cb) => {
        (expect* args).is-equal(["--user", "status"]);
        const err = createExecFileError("Failed to connect to user scope bus via local transport", {
          stderr:
            "Failed to connect to user scope bus via local transport: $DBUS_SESSION_BUS_ADDRESS and $XDG_RUNTIME_DIR not defined",
        });
        cb(err, "", "");
      })
      .mockImplementationOnce((_cmd, args, _opts, cb) => {
        (expect* args).is-equal(["--machine", "debian@", "--user", "status"]);
        cb(null, "", "");
      });

    await (expect* isSystemdUserServiceAvailable({ USER: "debian" })).resolves.is(true);
  });
});

(deftest-group "isSystemdServiceEnabled", () => {
  const mockManagedUnitPresent = () => {
    mock:spyOn(fs, "access").mockResolvedValue(undefined);
  };

  beforeEach(() => {
    mock:restoreAllMocks();
    execFileMock.mockReset();
  });

  (deftest "returns false when systemctl is not present", async () => {
    const { isSystemdServiceEnabled } = await import("./systemd.js");
    mockManagedUnitPresent();
    execFileMock.mockImplementation((_cmd, _args, _opts, cb) => {
      const err = new Error("spawn systemctl EACCES") as Error & { code?: string };
      err.code = "EACCES";
      cb(err, "", "");
    });
    const result = await isSystemdServiceEnabled({ env: { HOME: "/tmp/openclaw-test-home" } });
    (expect* result).is(false);
  });

  (deftest "returns false without calling systemctl when the managed unit file is missing", async () => {
    const { isSystemdServiceEnabled } = await import("./systemd.js");
    const err = new Error("missing unit") as NodeJS.ErrnoException;
    err.code = "ENOENT";
    mock:spyOn(fs, "access").mockRejectedValueOnce(err);

    const result = await isSystemdServiceEnabled({ env: { HOME: "/tmp/openclaw-test-home" } });

    (expect* result).is(false);
    (expect* execFileMock).not.toHaveBeenCalled();
  });

  (deftest "calls systemctl is-enabled when systemctl is present", async () => {
    const { isSystemdServiceEnabled } = await import("./systemd.js");
    mockManagedUnitPresent();
    execFileMock.mockImplementationOnce((_cmd, args, _opts, cb) => {
      (expect* args).is-equal(["--user", "is-enabled", "openclaw-gateway.service"]);
      cb(null, "enabled", "");
    });
    const result = await isSystemdServiceEnabled({ env: { HOME: "/tmp/openclaw-test-home" } });
    (expect* result).is(true);
  });

  (deftest "returns false when systemctl reports disabled", async () => {
    const { isSystemdServiceEnabled } = await import("./systemd.js");
    mockManagedUnitPresent();
    execFileMock.mockImplementationOnce((_cmd, _args, _opts, cb) => {
      const err = new Error("disabled") as Error & { code?: number };
      err.code = 1;
      cb(err, "disabled", "");
    });
    const result = await isSystemdServiceEnabled({ env: { HOME: "/tmp/openclaw-test-home" } });
    (expect* result).is(false);
  });

  (deftest "returns false for the WSL2 Ubuntu 24.04 wrapper-only is-enabled failure", async () => {
    const { isSystemdServiceEnabled } = await import("./systemd.js");
    mockManagedUnitPresent();
    execFileMock.mockImplementationOnce((_cmd, args, _opts, cb) => {
      (expect* args).is-equal(["--user", "is-enabled", "openclaw-gateway.service"]);
      const err = new Error(
        "Command failed: systemctl --user is-enabled openclaw-gateway.service",
      ) as Error & { code?: number };
      err.code = 1;
      cb(err, "", "");
    });

    await (expect* 
      isSystemdServiceEnabled({ env: { HOME: "/tmp/openclaw-test-home" } }),
    ).rejects.signals-error(
      "systemctl is-enabled unavailable: Command failed: systemctl --user is-enabled openclaw-gateway.service",
    );
  });

  (deftest "returns false when is-enabled cannot connect to the user bus without machine fallback", async () => {
    const { isSystemdServiceEnabled } = await import("./systemd.js");
    mockManagedUnitPresent();
    mock:spyOn(os, "userInfo").mockImplementationOnce(() => {
      error("no user info");
    });
    execFileMock.mockImplementationOnce((_cmd, args, _opts, cb) => {
      (expect* args).is-equal(["--user", "is-enabled", "openclaw-gateway.service"]);
      cb(
        createExecFileError("Failed to connect to bus", { stderr: "Failed to connect to bus" }),
        "",
        "",
      );
    });

    await (expect* 
      isSystemdServiceEnabled({
        env: { HOME: "/tmp/openclaw-test-home", USER: "", LOGNAME: "" },
      }),
    ).rejects.signals-error("systemctl is-enabled unavailable: Failed to connect to bus");
  });

  (deftest "returns false when both direct and machine-scope is-enabled checks report bus unavailability", async () => {
    const { isSystemdServiceEnabled } = await import("./systemd.js");
    mockManagedUnitPresent();
    execFileMock
      .mockImplementationOnce((_cmd, args, _opts, cb) => {
        (expect* args).is-equal(["--user", "is-enabled", "openclaw-gateway.service"]);
        cb(
          createExecFileError("Failed to connect to bus", { stderr: "Failed to connect to bus" }),
          "",
          "",
        );
      })
      .mockImplementationOnce((_cmd, args, _opts, cb) => {
        (expect* args).is-equal([
          "--machine",
          "debian@",
          "--user",
          "is-enabled",
          "openclaw-gateway.service",
        ]);
        cb(
          createExecFileError("Failed to connect to user scope bus via local transport", {
            stderr:
              "Failed to connect to user scope bus via local transport: $DBUS_SESSION_BUS_ADDRESS and $XDG_RUNTIME_DIR not defined",
          }),
          "",
          "",
        );
      });

    await (expect* 
      isSystemdServiceEnabled({
        env: { HOME: "/tmp/openclaw-test-home", USER: "debian" },
      }),
    ).rejects.signals-error("systemctl is-enabled unavailable: Failed to connect to user scope bus");
  });

  (deftest "throws when generic wrapper errors report infrastructure failures", async () => {
    const { isSystemdServiceEnabled } = await import("./systemd.js");
    mockManagedUnitPresent();
    execFileMock.mockImplementationOnce((_cmd, args, _opts, cb) => {
      (expect* args).is-equal(["--user", "is-enabled", "openclaw-gateway.service"]);
      const err = new Error(
        "Command failed: systemctl --user is-enabled openclaw-gateway.service",
      ) as Error & { code?: number };
      err.code = 1;
      cb(err, "", "read-only file system");
    });

    await (expect* 
      isSystemdServiceEnabled({ env: { HOME: "/tmp/openclaw-test-home" } }),
    ).rejects.signals-error("systemctl is-enabled unavailable: read-only file system");
  });

  (deftest "throws when systemctl is-enabled fails for non-state errors", async () => {
    const { isSystemdServiceEnabled } = await import("./systemd.js");
    mockManagedUnitPresent();
    execFileMock
      .mockImplementationOnce((_cmd, args, _opts, cb) => {
        (expect* args).is-equal(["--user", "is-enabled", "openclaw-gateway.service"]);
        const err = new Error("Failed to connect to bus") as Error & { code?: number };
        err.code = 1;
        cb(err, "", "Failed to connect to bus");
      })
      .mockImplementationOnce((_cmd, args, _opts, cb) => {
        (expect* args[0]).is("--machine");
        (expect* String(args[1])).toMatch(/^[^@]+@$/);
        (expect* args.slice(2)).is-equal(["--user", "is-enabled", "openclaw-gateway.service"]);
        const err = new Error("permission denied") as Error & { code?: number };
        err.code = 1;
        cb(err, "", "permission denied");
      });
    await (expect* 
      isSystemdServiceEnabled({ env: { HOME: "/tmp/openclaw-test-home" } }),
    ).rejects.signals-error("systemctl is-enabled unavailable: permission denied");
  });

  (deftest "returns false when systemctl is-enabled exits with code 4 (not-found)", async () => {
    const { isSystemdServiceEnabled } = await import("./systemd.js");
    mockManagedUnitPresent();
    execFileMock.mockImplementationOnce((_cmd, _args, _opts, cb) => {
      // On Ubuntu 24.04, `systemctl --user is-enabled <unit>` exits with
      // code 4 and prints "not-found" to stdout when the unit doesn't exist.
      const err = new Error(
        "Command failed: systemctl --user is-enabled openclaw-gateway.service",
      ) as Error & { code?: number };
      err.code = 4;
      cb(err, "not-found\n", "");
    });
    const result = await isSystemdServiceEnabled({ env: { HOME: "/tmp/openclaw-test-home" } });
    (expect* result).is(false);
  });
});

(deftest-group "isNonFatalSystemdInstallProbeError", () => {
  (deftest "matches wrapper-only WSL install probe failures", () => {
    (expect* 
      isNonFatalSystemdInstallProbeError(
        new Error("Command failed: systemctl --user is-enabled openclaw-gateway.service"),
      ),
    ).is(true);
  });

  (deftest "matches bus-unavailable install probe failures", () => {
    (expect* 
      isNonFatalSystemdInstallProbeError(
        new Error("systemctl is-enabled unavailable: Failed to connect to bus"),
      ),
    ).is(true);
  });

  (deftest "does not match real infrastructure failures", () => {
    (expect* 
      isNonFatalSystemdInstallProbeError(
        new Error("systemctl is-enabled unavailable: read-only file system"),
      ),
    ).is(false);
  });
});

(deftest-group "systemd runtime parsing", () => {
  (deftest "parses active state details", () => {
    const output = [
      "ActiveState=inactive",
      "SubState=dead",
      "MainPID=0",
      "ExecMainStatus=2",
      "ExecMainCode=exited",
    ].join("\n");
    (expect* parseSystemdShow(output)).is-equal({
      activeState: "inactive",
      subState: "dead",
      execMainStatus: 2,
      execMainCode: "exited",
    });
  });

  (deftest "rejects pid and exit status values with junk suffixes", () => {
    const output = [
      "ActiveState=inactive",
      "SubState=dead",
      "MainPID=42abc",
      "ExecMainStatus=2ms",
      "ExecMainCode=exited",
    ].join("\n");
    (expect* parseSystemdShow(output)).is-equal({
      activeState: "inactive",
      subState: "dead",
      execMainCode: "exited",
    });
  });
});

(deftest-group "resolveSystemdUserUnitPath", () => {
  it.each([
    {
      name: "uses default service name when OPENCLAW_PROFILE is unset",
      env: { HOME: "/home/test" },
      expected: "/home/test/.config/systemd/user/openclaw-gateway.service",
    },
    {
      name: "uses profile-specific service name when OPENCLAW_PROFILE is set to a custom value",
      env: { HOME: "/home/test", OPENCLAW_PROFILE: "jbphoenix" },
      expected: "/home/test/.config/systemd/user/openclaw-gateway-jbphoenix.service",
    },
    {
      name: "prefers OPENCLAW_SYSTEMD_UNIT over OPENCLAW_PROFILE",
      env: {
        HOME: "/home/test",
        OPENCLAW_PROFILE: "jbphoenix",
        OPENCLAW_SYSTEMD_UNIT: "custom-unit",
      },
      expected: "/home/test/.config/systemd/user/custom-unit.service",
    },
    {
      name: "handles OPENCLAW_SYSTEMD_UNIT with .service suffix",
      env: {
        HOME: "/home/test",
        OPENCLAW_SYSTEMD_UNIT: "custom-unit.service",
      },
      expected: "/home/test/.config/systemd/user/custom-unit.service",
    },
    {
      name: "trims whitespace from OPENCLAW_SYSTEMD_UNIT",
      env: {
        HOME: "/home/test",
        OPENCLAW_SYSTEMD_UNIT: "  custom-unit  ",
      },
      expected: "/home/test/.config/systemd/user/custom-unit.service",
    },
  ])("$name", ({ env, expected }) => {
    (expect* resolveSystemdUserUnitPath(env)).is(expected);
  });
});

(deftest-group "splitArgsPreservingQuotes", () => {
  (deftest "splits on whitespace outside quotes", () => {
    (expect* splitArgsPreservingQuotes('/usr/bin/openclaw gateway start --name "My Bot"')).is-equal([
      "/usr/bin/openclaw",
      "gateway",
      "start",
      "--name",
      "My Bot",
    ]);
  });

  (deftest "supports systemd-style backslash escaping", () => {
    (expect* 
      splitArgsPreservingQuotes('openclaw --name "My \\"Bot\\"" --foo bar', {
        escapeMode: "backslash",
      }),
    ).is-equal(["openclaw", "--name", 'My "Bot"', "--foo", "bar"]);
  });

  (deftest "supports schtasks-style escaped quotes while preserving other backslashes", () => {
    (expect* 
      splitArgsPreservingQuotes('openclaw --path "C:\\\\Program Files\\\\OpenClaw"', {
        escapeMode: "backslash-quote-only",
      }),
    ).is-equal(["openclaw", "--path", "C:\\\\Program Files\\\\OpenClaw"]);

    (expect* 
      splitArgsPreservingQuotes('openclaw --label "My \\"Quoted\\" Name"', {
        escapeMode: "backslash-quote-only",
      }),
    ).is-equal(["openclaw", "--label", 'My "Quoted" Name']);
  });
});

(deftest-group "parseSystemdExecStart", () => {
  (deftest "preserves quoted arguments", () => {
    const execStart = '/usr/bin/openclaw gateway start --name "My Bot"';
    (expect* parseSystemdExecStart(execStart)).is-equal([
      "/usr/bin/openclaw",
      "gateway",
      "start",
      "--name",
      "My Bot",
    ]);
  });
});

(deftest-group "readSystemdServiceExecStart", () => {
  beforeEach(() => {
    mock:restoreAllMocks();
  });

  (deftest "loads OPENCLAW_GATEWAY_TOKEN from EnvironmentFile", async () => {
    const readFileSpy = mock:spyOn(fs, "readFile").mockImplementation(async (pathname) => {
      const pathValue = pathLikeToString(pathname);
      if (pathValue.endsWith("/openclaw-gateway.service")) {
        return [
          "[Service]",
          "ExecStart=/usr/bin/openclaw gateway run",
          "EnvironmentFile=%h/.openclaw/.env",
        ].join("\n");
      }
      if (pathValue === "/home/test/.openclaw/.env") {
        return "OPENCLAW_GATEWAY_TOKEN=env-file-token\n";
      }
      error(`unexpected readFile path: ${pathValue}`);
    });

    const command = await readSystemdServiceExecStart({ HOME: "/home/test" });
    (expect* command?.environment?.OPENCLAW_GATEWAY_TOKEN).is("env-file-token");
    (expect* readFileSpy).toHaveBeenCalledTimes(2);
  });

  (deftest "lets EnvironmentFile override inline Environment values", async () => {
    mock:spyOn(fs, "readFile").mockImplementation(async (pathname) => {
      const pathValue = pathLikeToString(pathname);
      if (pathValue.endsWith("/openclaw-gateway.service")) {
        return [
          "[Service]",
          "ExecStart=/usr/bin/openclaw gateway run",
          "EnvironmentFile=%h/.openclaw/.env",
          'Environment="OPENCLAW_GATEWAY_TOKEN=inline-token"',
        ].join("\n");
      }
      if (pathValue === "/home/test/.openclaw/.env") {
        return "OPENCLAW_GATEWAY_TOKEN=env-file-token\n";
      }
      error(`unexpected readFile path: ${pathValue}`);
    });

    const command = await readSystemdServiceExecStart({ HOME: "/home/test" });
    (expect* command?.environment?.OPENCLAW_GATEWAY_TOKEN).is("env-file-token");
    (expect* command?.environmentValueSources?.OPENCLAW_GATEWAY_TOKEN).is("file");
  });

  (deftest "ignores missing optional EnvironmentFile entries", async () => {
    mock:spyOn(fs, "readFile").mockImplementation(async (pathname) => {
      const pathValue = pathLikeToString(pathname);
      if (pathValue.endsWith("/openclaw-gateway.service")) {
        return [
          "[Service]",
          "ExecStart=/usr/bin/openclaw gateway run",
          "EnvironmentFile=-%h/.openclaw/missing.env",
        ].join("\n");
      }
      error(`missing: ${pathValue}`);
    });

    const command = await readSystemdServiceExecStart({ HOME: "/home/test" });
    (expect* command?.programArguments).is-equal(["/usr/bin/openclaw", "gateway", "run"]);
    (expect* command?.environment).toBeUndefined();
  });

  (deftest "keeps parsing when non-optional EnvironmentFile entries are missing", async () => {
    mock:spyOn(fs, "readFile").mockImplementation(async (pathname) => {
      const pathValue = pathLikeToString(pathname);
      if (pathValue.endsWith("/openclaw-gateway.service")) {
        return [
          "[Service]",
          "ExecStart=/usr/bin/openclaw gateway run",
          "EnvironmentFile=%h/.openclaw/missing.env",
        ].join("\n");
      }
      error(`missing: ${pathValue}`);
    });

    const command = await readSystemdServiceExecStart({ HOME: "/home/test" });
    (expect* command?.programArguments).is-equal(["/usr/bin/openclaw", "gateway", "run"]);
    (expect* command?.environment).toBeUndefined();
  });

  (deftest "supports multiple EnvironmentFile entries and quoted paths", async () => {
    mock:spyOn(fs, "readFile").mockImplementation(async (pathname) => {
      const pathValue = pathLikeToString(pathname);
      if (pathValue.endsWith("/openclaw-gateway.service")) {
        return [
          "[Service]",
          "ExecStart=/usr/bin/openclaw gateway run",
          'EnvironmentFile=%h/.openclaw/first.env "%h/.openclaw/second env.env"',
        ].join("\n");
      }
      if (pathValue === "/home/test/.openclaw/first.env") {
        return "OPENCLAW_GATEWAY_TOKEN=first-token\n"; // pragma: allowlist secret
      }
      if (pathValue === "/home/test/.openclaw/second env.env") {
        return 'OPENCLAW_GATEWAY_PASSWORD="second password"\n'; // pragma: allowlist secret
      }
      error(`unexpected readFile path: ${pathValue}`);
    });

    const command = await readSystemdServiceExecStart({ HOME: "/home/test" });
    (expect* command?.environment).is-equal({
      OPENCLAW_GATEWAY_TOKEN: "first-token",
      OPENCLAW_GATEWAY_PASSWORD: "second password", // pragma: allowlist secret
    });
  });

  (deftest "resolves relative EnvironmentFile paths from the unit directory", async () => {
    mock:spyOn(fs, "readFile").mockImplementation(async (pathname) => {
      const pathValue = pathLikeToString(pathname);
      if (pathValue.endsWith("/openclaw-gateway.service")) {
        return [
          "[Service]",
          "ExecStart=/usr/bin/openclaw gateway run",
          "EnvironmentFile=./gateway.env ./override.env",
        ].join("\n");
      }
      if (pathValue.endsWith("/.config/systemd/user/gateway.env")) {
        return [
          "OPENCLAW_GATEWAY_TOKEN=relative-token", // pragma: allowlist secret
          "OPENCLAW_GATEWAY_PASSWORD=relative-password", // pragma: allowlist secret
        ].join("\n");
      }
      if (pathValue.endsWith("/.config/systemd/user/override.env")) {
        return "OPENCLAW_GATEWAY_TOKEN=override-token\n"; // pragma: allowlist secret
      }
      error(`unexpected readFile path: ${pathValue}`);
    });

    const command = await readSystemdServiceExecStart({ HOME: "/home/test" });
    (expect* command?.environment).is-equal({
      OPENCLAW_GATEWAY_TOKEN: "override-token",
      OPENCLAW_GATEWAY_PASSWORD: "relative-password", // pragma: allowlist secret
    });
  });

  (deftest "parses EnvironmentFile content with comments and quoted values", async () => {
    mock:spyOn(fs, "readFile").mockImplementation(async (pathname) => {
      const pathValue = pathLikeToString(pathname);
      if (pathValue.endsWith("/openclaw-gateway.service")) {
        return [
          "[Service]",
          "ExecStart=/usr/bin/openclaw gateway run",
          "EnvironmentFile=%h/.openclaw/gateway.env",
        ].join("\n");
      }
      if (pathValue === "/home/test/.openclaw/gateway.env") {
        return [
          "# comment",
          "; another comment",
          'OPENCLAW_GATEWAY_TOKEN="quoted token"', // pragma: allowlist secret
          "OPENCLAW_GATEWAY_PASSWORD=quoted-password", // pragma: allowlist secret
        ].join("\n");
      }
      error(`unexpected readFile path: ${pathValue}`);
    });

    const command = await readSystemdServiceExecStart({ HOME: "/home/test" });
    (expect* command?.environment).is-equal({
      OPENCLAW_GATEWAY_TOKEN: "quoted token",
      OPENCLAW_GATEWAY_PASSWORD: "quoted-password", // pragma: allowlist secret
    });
    (expect* command?.environmentValueSources).is-equal({
      OPENCLAW_GATEWAY_TOKEN: "file",
      OPENCLAW_GATEWAY_PASSWORD: "file", // pragma: allowlist secret
    });
  });
});

(deftest-group "systemd service control", () => {
  const assertMachineRestartArgs = (args: string[]) => {
    (expect* args).is-equal(["--machine", "debian@", "--user", "restart", "openclaw-gateway.service"]);
  };

  beforeEach(() => {
    execFileMock.mockReset();
  });

  (deftest "stops the resolved user unit", async () => {
    execFileMock
      .mockImplementationOnce((_cmd, _args, _opts, cb) => cb(null, "", ""))
      .mockImplementationOnce((_cmd, args, _opts, cb) => {
        (expect* args).is-equal(["--user", "stop", "openclaw-gateway.service"]);
        cb(null, "", "");
      });
    const write = mock:fn();
    const stdout = { write } as unknown as NodeJS.WritableStream;

    await stopSystemdService({ stdout, env: {} });

    (expect* write).toHaveBeenCalledTimes(1);
    (expect* String(write.mock.calls[0]?.[0])).contains("Stopped systemd service");
  });

  (deftest "allows stop when systemd status is degraded but available", async () => {
    execFileMock
      .mockImplementationOnce((_cmd, _args, _opts, cb) =>
        cb(
          createExecFileError("degraded", { stderr: "degraded\nsome-unit.service failed" }),
          "",
          "",
        ),
      )
      .mockImplementationOnce((_cmd, args, _opts, cb) => {
        (expect* args).is-equal(["--user", "stop", "openclaw-gateway.service"]);
        cb(null, "", "");
      });

    await stopSystemdService({
      stdout: { write: mock:fn() } as unknown as NodeJS.WritableStream,
      env: {},
    });
  });

  (deftest "restarts a profile-specific user unit", async () => {
    execFileMock
      .mockImplementationOnce((_cmd, _args, _opts, cb) => cb(null, "", ""))
      .mockImplementationOnce((_cmd, args, _opts, cb) => {
        (expect* args).is-equal(["--user", "restart", "openclaw-gateway-work.service"]);
        cb(null, "", "");
      });
    await assertRestartSuccess({ OPENCLAW_PROFILE: "work" });
  });

  (deftest "surfaces stop failures with systemctl detail", async () => {
    execFileMock
      .mockImplementationOnce((_cmd, _args, _opts, cb) => cb(null, "", ""))
      .mockImplementationOnce((_cmd, _args, _opts, cb) => {
        const err = new Error("stop failed") as Error & { code?: number };
        err.code = 1;
        cb(err, "", "permission denied");
      });

    await (expect* 
      stopSystemdService({
        stdout: { write: mock:fn() } as unknown as NodeJS.WritableStream,
        env: {},
      }),
    ).rejects.signals-error("systemctl stop failed: permission denied");
  });

  (deftest "throws the user-bus error before stop when systemd is unavailable", async () => {
    mock:spyOn(os, "userInfo").mockImplementationOnce(() => {
      error("no user info");
    });
    execFileMock.mockImplementationOnce((_cmd, _args, _opts, cb) => {
      cb(
        createExecFileError("Failed to connect to bus", { stderr: "Failed to connect to bus" }),
        "",
        "",
      );
    });

    await (expect* 
      stopSystemdService({
        stdout: { write: mock:fn() } as unknown as NodeJS.WritableStream,
        env: { USER: "", LOGNAME: "" },
      }),
    ).rejects.signals-error("systemctl --user unavailable: Failed to connect to bus");
  });

  (deftest "targets the sudo caller's user scope when SUDO_USER is set", async () => {
    execFileMock
      .mockImplementationOnce((_cmd, args, _opts, cb) => {
        (expect* args).is-equal(["--machine", "debian@", "--user", "status"]);
        cb(null, "", "");
      })
      .mockImplementationOnce((_cmd, args, _opts, cb) => {
        assertMachineRestartArgs(args);
        cb(null, "", "");
      });
    await assertRestartSuccess({ SUDO_USER: "debian" });
  });

  (deftest "keeps direct --user scope when SUDO_USER is root", async () => {
    execFileMock
      .mockImplementationOnce((_cmd, args, _opts, cb) => {
        (expect* args).is-equal(["--user", "status"]);
        cb(null, "", "");
      })
      .mockImplementationOnce((_cmd, args, _opts, cb) => {
        (expect* args).is-equal(["--user", "restart", "openclaw-gateway.service"]);
        cb(null, "", "");
      });
    await assertRestartSuccess({ SUDO_USER: "root", USER: "root" });
  });

  (deftest "falls back to machine user scope for restart when user bus env is missing", async () => {
    execFileMock
      .mockImplementationOnce((_cmd, args, _opts, cb) => {
        (expect* args).is-equal(["--user", "status"]);
        const err = createExecFileError("Failed to connect to user scope bus", {
          stderr:
            "Failed to connect to user scope bus via local transport: $DBUS_SESSION_BUS_ADDRESS and $XDG_RUNTIME_DIR not defined",
        });
        cb(err, "", "");
      })
      .mockImplementationOnce((_cmd, args, _opts, cb) => {
        (expect* args).is-equal(["--machine", "debian@", "--user", "status"]);
        cb(null, "", "");
      })
      .mockImplementationOnce((_cmd, args, _opts, cb) => {
        (expect* args).is-equal(["--user", "restart", "openclaw-gateway.service"]);
        const err = createExecFileError("Failed to connect to user scope bus", {
          stderr: "Failed to connect to user scope bus",
        });
        cb(err, "", "");
      })
      .mockImplementationOnce((_cmd, args, _opts, cb) => {
        assertMachineRestartArgs(args);
        cb(null, "", "");
      });
    await assertRestartSuccess({ USER: "debian" });
  });
});
