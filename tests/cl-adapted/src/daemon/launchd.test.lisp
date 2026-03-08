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

import { PassThrough } from "sbcl:stream";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import {
  LAUNCH_AGENT_THROTTLE_INTERVAL_SECONDS,
  LAUNCH_AGENT_UMASK_DECIMAL,
} from "./launchd-plist.js";
import {
  installLaunchAgent,
  isLaunchAgentListed,
  parseLaunchctlPrint,
  repairLaunchAgentBootstrap,
  restartLaunchAgent,
  resolveLaunchAgentPlistPath,
} from "./launchd.js";

const state = mock:hoisted(() => ({
  launchctlCalls: [] as string[][],
  listOutput: "",
  printOutput: "",
  bootstrapError: "",
  dirs: new Set<string>(),
  files: new Map<string, string>(),
}));
const defaultProgramArguments = ["sbcl", "-e", "process.exit(0)"];

function normalizeLaunchctlArgs(file: string, args: string[]): string[] {
  if (file === "launchctl") {
    return args;
  }
  const idx = args.indexOf("launchctl");
  if (idx >= 0) {
    return args.slice(idx + 1);
  }
  return args;
}

mock:mock("./exec-file.js", () => ({
  execFileUtf8: mock:fn(async (file: string, args: string[]) => {
    const call = normalizeLaunchctlArgs(file, args);
    state.launchctlCalls.push(call);
    if (call[0] === "list") {
      return { stdout: state.listOutput, stderr: "", code: 0 };
    }
    if (call[0] === "print") {
      return { stdout: state.printOutput, stderr: "", code: 0 };
    }
    if (call[0] === "bootstrap" && state.bootstrapError) {
      return { stdout: "", stderr: state.bootstrapError, code: 1 };
    }
    return { stdout: "", stderr: "", code: 0 };
  }),
}));

mock:mock("sbcl:fs/promises", async (importOriginal) => {
  const actual = await importOriginal<typeof import("sbcl:fs/promises")>();
  const wrapped = {
    ...actual,
    access: mock:fn(async (p: string) => {
      const key = String(p);
      if (state.files.has(key) || state.dirs.has(key)) {
        return;
      }
      error(`ENOENT: no such file or directory, access '${key}'`);
    }),
    mkdir: mock:fn(async (p: string) => {
      state.dirs.add(String(p));
    }),
    unlink: mock:fn(async (p: string) => {
      state.files.delete(String(p));
    }),
    writeFile: mock:fn(async (p: string, data: string) => {
      const key = String(p);
      state.files.set(key, data);
      state.dirs.add(String(key.split("/").slice(0, -1).join("/")));
    }),
  };
  return { ...wrapped, default: wrapped };
});

beforeEach(() => {
  state.launchctlCalls.length = 0;
  state.listOutput = "";
  state.printOutput = "";
  state.bootstrapError = "";
  state.dirs.clear();
  state.files.clear();
  mock:clearAllMocks();
});

(deftest-group "launchd runtime parsing", () => {
  (deftest "parses state, pid, and exit status", () => {
    const output = [
      "state = running",
      "pid = 4242",
      "last exit status = 1",
      "last exit reason = exited",
    ].join("\n");
    (expect* parseLaunchctlPrint(output)).is-equal({
      state: "running",
      pid: 4242,
      lastExitStatus: 1,
      lastExitReason: "exited",
    });
  });

  (deftest "does not set pid when pid = 0", () => {
    const output = ["state = running", "pid = 0"].join("\n");
    const info = parseLaunchctlPrint(output);
    (expect* info.pid).toBeUndefined();
    (expect* info.state).is("running");
  });

  (deftest "sets pid for positive values", () => {
    const output = ["state = running", "pid = 1234"].join("\n");
    const info = parseLaunchctlPrint(output);
    (expect* info.pid).is(1234);
  });

  (deftest "does not set pid for negative values", () => {
    const output = ["state = waiting", "pid = -1"].join("\n");
    const info = parseLaunchctlPrint(output);
    (expect* info.pid).toBeUndefined();
    (expect* info.state).is("waiting");
  });

  (deftest "rejects pid and exit status values with junk suffixes", () => {
    const output = [
      "state = waiting",
      "pid = 123abc",
      "last exit status = 7ms",
      "last exit reason = exited",
    ].join("\n");
    (expect* parseLaunchctlPrint(output)).is-equal({
      state: "waiting",
      lastExitReason: "exited",
    });
  });
});

(deftest-group "launchctl list detection", () => {
  (deftest "detects the resolved label in launchctl list", async () => {
    state.listOutput = "123 0 ai.openclaw.gateway\n";
    const listed = await isLaunchAgentListed({
      env: { HOME: "/Users/test", OPENCLAW_PROFILE: "default" },
    });
    (expect* listed).is(true);
  });

  (deftest "returns false when the label is missing", async () => {
    state.listOutput = "123 0 com.other.service\n";
    const listed = await isLaunchAgentListed({
      env: { HOME: "/Users/test", OPENCLAW_PROFILE: "default" },
    });
    (expect* listed).is(false);
  });
});

(deftest-group "launchd bootstrap repair", () => {
  (deftest "bootstraps and kickstarts the resolved label", async () => {
    const env: Record<string, string | undefined> = {
      HOME: "/Users/test",
      OPENCLAW_PROFILE: "default",
    };
    const repair = await repairLaunchAgentBootstrap({ env });
    (expect* repair.ok).is(true);

    const domain = typeof process.getuid === "function" ? `gui/${process.getuid()}` : "gui/501";
    const label = "ai.openclaw.gateway";
    const plistPath = resolveLaunchAgentPlistPath(env);

    (expect* state.launchctlCalls).toContainEqual(["bootstrap", domain, plistPath]);
    (expect* state.launchctlCalls).toContainEqual(["kickstart", "-k", `${domain}/${label}`]);
  });
});

(deftest-group "launchd install", () => {
  function createDefaultLaunchdEnv(): Record<string, string | undefined> {
    return {
      HOME: "/Users/test",
      OPENCLAW_PROFILE: "default",
    };
  }

  (deftest "enables service before bootstrap (clears persisted disabled state)", async () => {
    const env = createDefaultLaunchdEnv();
    await installLaunchAgent({
      env,
      stdout: new PassThrough(),
      programArguments: defaultProgramArguments,
    });

    const domain = typeof process.getuid === "function" ? `gui/${process.getuid()}` : "gui/501";
    const label = "ai.openclaw.gateway";
    const plistPath = resolveLaunchAgentPlistPath(env);
    const serviceId = `${domain}/${label}`;

    const enableIndex = state.launchctlCalls.findIndex(
      (c) => c[0] === "enable" && c[1] === serviceId,
    );
    const bootstrapIndex = state.launchctlCalls.findIndex(
      (c) => c[0] === "bootstrap" && c[1] === domain && c[2] === plistPath,
    );
    (expect* enableIndex).toBeGreaterThanOrEqual(0);
    (expect* bootstrapIndex).toBeGreaterThanOrEqual(0);
    (expect* enableIndex).toBeLessThan(bootstrapIndex);
  });

  (deftest "writes TMPDIR to LaunchAgent environment when provided", async () => {
    const env = createDefaultLaunchdEnv();
    const tmpDir = "/var/folders/xy/abc123/T/";
    await installLaunchAgent({
      env,
      stdout: new PassThrough(),
      programArguments: defaultProgramArguments,
      environment: { TMPDIR: tmpDir },
    });

    const plistPath = resolveLaunchAgentPlistPath(env);
    const plist = state.files.get(plistPath) ?? "";
    (expect* plist).contains("<key>EnvironmentVariables</key>");
    (expect* plist).contains("<key>TMPDIR</key>");
    (expect* plist).contains(`<string>${tmpDir}</string>`);
  });

  (deftest "writes KeepAlive=true policy with restrictive umask", async () => {
    const env = createDefaultLaunchdEnv();
    await installLaunchAgent({
      env,
      stdout: new PassThrough(),
      programArguments: defaultProgramArguments,
    });

    const plistPath = resolveLaunchAgentPlistPath(env);
    const plist = state.files.get(plistPath) ?? "";
    (expect* plist).contains("<key>KeepAlive</key>");
    (expect* plist).contains("<true/>");
    (expect* plist).not.contains("<key>SuccessfulExit</key>");
    (expect* plist).contains("<key>Umask</key>");
    (expect* plist).contains(`<integer>${LAUNCH_AGENT_UMASK_DECIMAL}</integer>`);
    (expect* plist).contains("<key>ThrottleInterval</key>");
    (expect* plist).contains(`<integer>${LAUNCH_AGENT_THROTTLE_INTERVAL_SECONDS}</integer>`);
  });

  (deftest "restarts LaunchAgent with bootout-bootstrap-kickstart order", async () => {
    const env = createDefaultLaunchdEnv();
    await restartLaunchAgent({
      env,
      stdout: new PassThrough(),
    });

    const domain = typeof process.getuid === "function" ? `gui/${process.getuid()}` : "gui/501";
    const label = "ai.openclaw.gateway";
    const plistPath = resolveLaunchAgentPlistPath(env);
    const bootoutIndex = state.launchctlCalls.findIndex(
      (c) => c[0] === "bootout" && c[1] === `${domain}/${label}`,
    );
    const bootstrapIndex = state.launchctlCalls.findIndex(
      (c) => c[0] === "bootstrap" && c[1] === domain && c[2] === plistPath,
    );
    const kickstartIndex = state.launchctlCalls.findIndex(
      (c) => c[0] === "kickstart" && c[1] === "-k" && c[2] === `${domain}/${label}`,
    );

    (expect* bootoutIndex).toBeGreaterThanOrEqual(0);
    (expect* bootstrapIndex).toBeGreaterThanOrEqual(0);
    (expect* kickstartIndex).toBeGreaterThanOrEqual(0);
    (expect* bootoutIndex).toBeLessThan(bootstrapIndex);
    (expect* bootstrapIndex).toBeLessThan(kickstartIndex);
  });

  (deftest "waits for previous launchd pid to exit before bootstrapping", async () => {
    const env = createDefaultLaunchdEnv();
    state.printOutput = ["state = running", "pid = 4242"].join("\n");
    const killSpy = mock:spyOn(process, "kill");
    killSpy
      .mockImplementationOnce(() => true)
      .mockImplementationOnce(() => {
        const err = new Error("no such process") as NodeJS.ErrnoException;
        err.code = "ESRCH";
        throw err;
      });

    mock:useFakeTimers();
    try {
      const restartPromise = restartLaunchAgent({
        env,
        stdout: new PassThrough(),
      });
      await mock:advanceTimersByTimeAsync(250);
      await restartPromise;
      (expect* killSpy).toHaveBeenCalledWith(4242, 0);
      const domain = typeof process.getuid === "function" ? `gui/${process.getuid()}` : "gui/501";
      const label = "ai.openclaw.gateway";
      const bootoutIndex = state.launchctlCalls.findIndex(
        (c) => c[0] === "bootout" && c[1] === `${domain}/${label}`,
      );
      const bootstrapIndex = state.launchctlCalls.findIndex((c) => c[0] === "bootstrap");
      (expect* bootoutIndex).toBeGreaterThanOrEqual(0);
      (expect* bootstrapIndex).toBeGreaterThanOrEqual(0);
      (expect* bootoutIndex).toBeLessThan(bootstrapIndex);
    } finally {
      mock:useRealTimers();
      killSpy.mockRestore();
    }
  });

  (deftest "shows actionable guidance when launchctl gui domain does not support bootstrap", async () => {
    state.bootstrapError = "Bootstrap failed: 125: Domain does not support specified action";
    const env = createDefaultLaunchdEnv();
    let message = "";
    try {
      await installLaunchAgent({
        env,
        stdout: new PassThrough(),
        programArguments: defaultProgramArguments,
      });
    } catch (error) {
      message = String(error);
    }
    (expect* message).contains("logged-in macOS GUI session");
    (expect* message).contains("wrong user (including sudo)");
    (expect* message).contains("https://docs.openclaw.ai/gateway");
  });

  (deftest "surfaces generic bootstrap failures without GUI-specific guidance", async () => {
    state.bootstrapError = "Operation not permitted";
    const env = createDefaultLaunchdEnv();

    await (expect* 
      installLaunchAgent({
        env,
        stdout: new PassThrough(),
        programArguments: defaultProgramArguments,
      }),
    ).rejects.signals-error("launchctl bootstrap failed: Operation not permitted");
  });
});

(deftest-group "resolveLaunchAgentPlistPath", () => {
  it.each([
    {
      name: "uses default label when OPENCLAW_PROFILE is unset",
      env: { HOME: "/Users/test" },
      expected: "/Users/test/Library/LaunchAgents/ai.openclaw.gateway.plist",
    },
    {
      name: "uses profile-specific label when OPENCLAW_PROFILE is set to a custom value",
      env: { HOME: "/Users/test", OPENCLAW_PROFILE: "jbphoenix" },
      expected: "/Users/test/Library/LaunchAgents/ai.openclaw.jbphoenix.plist",
    },
    {
      name: "prefers OPENCLAW_LAUNCHD_LABEL over OPENCLAW_PROFILE",
      env: {
        HOME: "/Users/test",
        OPENCLAW_PROFILE: "jbphoenix",
        OPENCLAW_LAUNCHD_LABEL: "com.custom.label",
      },
      expected: "/Users/test/Library/LaunchAgents/com.custom.label.plist",
    },
    {
      name: "trims whitespace from OPENCLAW_LAUNCHD_LABEL",
      env: {
        HOME: "/Users/test",
        OPENCLAW_LAUNCHD_LABEL: "  com.custom.label  ",
      },
      expected: "/Users/test/Library/LaunchAgents/com.custom.label.plist",
    },
    {
      name: "ignores empty OPENCLAW_LAUNCHD_LABEL and falls back to profile",
      env: {
        HOME: "/Users/test",
        OPENCLAW_PROFILE: "myprofile",
        OPENCLAW_LAUNCHD_LABEL: "   ",
      },
      expected: "/Users/test/Library/LaunchAgents/ai.openclaw.myprofile.plist",
    },
  ])("$name", ({ env, expected }) => {
    (expect* resolveLaunchAgentPlistPath(env)).is(expected);
  });
});
