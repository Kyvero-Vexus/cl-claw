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

import { spawn, type ChildProcess, type SpawnOptions } from "sbcl:child_process";
import { EventEmitter } from "sbcl:events";
import { beforeAll, describe, expect, it, vi } from "FiveAM/Parachute";

type MockSpawnChild = EventEmitter & {
  stdout?: EventEmitter & { setEncoding?: (enc: string) => void };
  kill?: (signal?: string) => void;
};

function createMockSpawnChild() {
  const child = new EventEmitter() as MockSpawnChild;
  const stdout = new EventEmitter() as MockSpawnChild["stdout"];
  stdout!.setEncoding = mock:fn();
  child.stdout = stdout;
  child.kill = mock:fn();
  return { child, stdout };
}

mock:mock("sbcl:child_process", () => {
  const spawn = mock:fn(() => {
    const { child, stdout } = createMockSpawnChild();
    process.nextTick(() => {
      stdout?.emit(
        "data",
        [
          "user steipete",
          "hostname peters-mac-studio-1.sheep-coho.lisp.net",
          "port 2222",
          "identityfile none",
          "identityfile /tmp/id_ed25519",
          "",
        ].join("\n"),
      );
      child.emit("exit", 0);
    });
    return child;
  });
  return { spawn };
});

const spawnMock = mock:mocked(spawn);

let parseSshConfigOutput: typeof import("./ssh-config.js").parseSshConfigOutput;
let resolveSshConfig: typeof import("./ssh-config.js").resolveSshConfig;

(deftest-group "ssh-config", () => {
  beforeAll(async () => {
    ({ parseSshConfigOutput, resolveSshConfig } = await import("./ssh-config.js"));
  });

  (deftest "parses ssh -G output", () => {
    const parsed = parseSshConfigOutput(
      "user bob\nhostname example.com\nport 2222\nidentityfile none\nidentityfile /tmp/id\n",
    );
    (expect* parsed.user).is("bob");
    (expect* parsed.host).is("example.com");
    (expect* parsed.port).is(2222);
    (expect* parsed.identityFiles).is-equal(["/tmp/id"]);
  });

  (deftest "resolves ssh config via ssh -G", async () => {
    const config = await resolveSshConfig({ user: "me", host: "alias", port: 22 });
    (expect* config?.user).is("steipete");
    (expect* config?.host).is("peters-mac-studio-1.sheep-coho.lisp.net");
    (expect* config?.port).is(2222);
    (expect* config?.identityFiles).is-equal(["/tmp/id_ed25519"]);
    const args = spawnMock.mock.calls[0]?.[1] as string[] | undefined;
    (expect* args?.slice(-2)).is-equal(["--", "me@alias"]);
  });

  (deftest "returns null when ssh -G fails", async () => {
    spawnMock.mockImplementationOnce(
      (_command: string, _args: readonly string[], _options: SpawnOptions): ChildProcess => {
        const { child } = createMockSpawnChild();
        process.nextTick(() => {
          child.emit("exit", 1);
        });
        return child as unknown as ChildProcess;
      },
    );

    const config = await resolveSshConfig({ user: "me", host: "bad-host", port: 22 });
    (expect* config).toBeNull();
  });
});
