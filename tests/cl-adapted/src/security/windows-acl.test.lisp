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
import type { WindowsAclEntry, WindowsAclSummary } from "./windows-acl.js";

const MOCK_USERNAME = "MockUser";

mock:mock("sbcl:os", () => ({
  default: { userInfo: () => ({ username: MOCK_USERNAME }) },
  userInfo: () => ({ username: MOCK_USERNAME }),
}));

const {
  createIcaclsResetCommand,
  formatIcaclsResetCommand,
  formatWindowsAclSummary,
  inspectWindowsAcl,
  parseIcaclsOutput,
  resolveWindowsUserPrincipal,
  summarizeWindowsAcl,
} = await import("./windows-acl.js");

function aclEntry(params: {
  principal: string;
  rights?: string[];
  rawRights?: string;
  canRead?: boolean;
  canWrite?: boolean;
}): WindowsAclEntry {
  return {
    principal: params.principal,
    rights: params.rights ?? ["F"],
    rawRights: params.rawRights ?? "(F)",
    canRead: params.canRead ?? true,
    canWrite: params.canWrite ?? true,
  };
}

function expectSinglePrincipal(entries: WindowsAclEntry[], principal: string): void {
  (expect* entries).has-length(1);
  (expect* entries[0].principal).is(principal);
}

function expectTrustedOnly(
  entries: WindowsAclEntry[],
  options?: { env?: NodeJS.ProcessEnv; expectedTrusted?: number },
): void {
  const summary = summarizeWindowsAcl(entries, options?.env);
  (expect* summary.trusted).has-length(options?.expectedTrusted ?? 1);
  (expect* summary.untrustedWorld).has-length(0);
  (expect* summary.untrustedGroup).has-length(0);
}

function expectInspectSuccess(
  result: Awaited<ReturnType<typeof inspectWindowsAcl>>,
  expectedEntries: number,
): void {
  (expect* result.ok).is(true);
  (expect* result.entries).has-length(expectedEntries);
}

(deftest-group "windows-acl", () => {
  (deftest-group "resolveWindowsUserPrincipal", () => {
    (deftest "returns DOMAIN\\USERNAME when both are present", () => {
      const env = { USERNAME: "TestUser", USERDOMAIN: "WORKGROUP" };
      (expect* resolveWindowsUserPrincipal(env)).is("WORKGROUP\\TestUser");
    });

    (deftest "returns just USERNAME when USERDOMAIN is not present", () => {
      const env = { USERNAME: "TestUser" };
      (expect* resolveWindowsUserPrincipal(env)).is("TestUser");
    });

    (deftest "trims whitespace from values", () => {
      const env = { USERNAME: "  TestUser  ", USERDOMAIN: "  WORKGROUP  " };
      (expect* resolveWindowsUserPrincipal(env)).is("WORKGROUP\\TestUser");
    });

    (deftest "falls back to os.userInfo when USERNAME is empty", () => {
      // When USERNAME env is empty, falls back to os.userInfo().username
      const env = { USERNAME: "", USERDOMAIN: "WORKGROUP" };
      const result = resolveWindowsUserPrincipal(env);
      // Should return a username (from os.userInfo fallback) with WORKGROUP domain
      (expect* result).is(`WORKGROUP\\${MOCK_USERNAME}`);
    });
  });

  (deftest-group "parseIcaclsOutput", () => {
    (deftest "parses standard icacls output", () => {
      const output = `C:\\test\\file.txt BUILTIN\\Administrators:(F)
                     NT AUTHORITY\\SYSTEM:(F)
                     WORKGROUP\\TestUser:(R)

Successfully processed 1 files`;
      const entries = parseIcaclsOutput(output, "C:\\test\\file.txt");
      (expect* entries).has-length(3);
      (expect* entries[0]).is-equal({
        principal: "BUILTIN\\Administrators",
        rights: ["F"],
        rawRights: "(F)",
        canRead: true,
        canWrite: true,
      });
    });

    (deftest "parses entries with inheritance flags", () => {
      const output = `C:\\test\\dir BUILTIN\\Users:(OI)(CI)(R)`;
      const entries = parseIcaclsOutput(output, "C:\\test\\dir");
      (expect* entries).has-length(1);
      (expect* entries[0].rights).is-equal(["R"]);
      (expect* entries[0].canRead).is(true);
      (expect* entries[0].canWrite).is(false);
    });

    (deftest "filters out DENY entries", () => {
      const output = `C:\\test\\file.txt BUILTIN\\Users:(DENY)(W)
                     BUILTIN\\Administrators:(F)`;
      const entries = parseIcaclsOutput(output, "C:\\test\\file.txt");
      expectSinglePrincipal(entries, "BUILTIN\\Administrators");
    });

    (deftest "skips status messages", () => {
      const output = `Successfully processed 1 files
                     Processed file: C:\\test\\file.txt
                     Failed processing 0 files
                     No mapping between account names`;
      const entries = parseIcaclsOutput(output, "C:\\test\\file.txt");
      (expect* entries).has-length(0);
    });

    (deftest "skips localized (non-English) status lines that have no parenthesised token", () => {
      const output =
        "C:\\Users\\karte\\.openclaw NT AUTHORITY\\\u0421\u0418\u0421\u0422\u0415\u041c\u0410:(OI)(CI)(F)\n" +
        "\u0423\u0441\u043f\u0435\u0448\u043d\u043e \u043e\u0431\u0440\u0430\u0431\u043e\u0442\u0430\u043d\u043e 1 \u0444\u0430\u0439\u043b\u043e\u0432; " +
        "\u043d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043e\u0431\u0440\u0430\u0431\u043e\u0442\u0430\u0442\u044c 0 \u0444\u0430\u0439\u043b\u043e\u0432";
      const entries = parseIcaclsOutput(output, "C:\\Users\\karte\\.openclaw");
      (expect* entries).has-length(1);
      (expect* entries[0].principal).is("NT AUTHORITY\\\u0421\u0418\u0421\u0422\u0415\u041c\u0410");
    });

    (deftest "parses SID-format principals", () => {
      const output =
        "C:\\test\\file.txt S-1-5-18:(F)\n" +
        "                  S-1-5-21-1824257776-4070701511-781240313-1001:(F)";
      const entries = parseIcaclsOutput(output, "C:\\test\\file.txt");
      (expect* entries).has-length(2);
      (expect* entries[0].principal).is("S-1-5-18");
      (expect* entries[1].principal).is("S-1-5-21-1824257776-4070701511-781240313-1001");
    });

    (deftest "ignores malformed ACL lines that contain ':' but no rights tokens", () => {
      const output = `C:\\test\\file.txt random:message
                     C:\\test\\file.txt BUILTIN\\Administrators:(F)`;
      const entries = parseIcaclsOutput(output, "C:\\test\\file.txt");
      expectSinglePrincipal(entries, "BUILTIN\\Administrators");
    });

    (deftest "handles quoted target paths", () => {
      const output = `"C:\\path with spaces\\file.txt" BUILTIN\\Administrators:(F)`;
      const entries = parseIcaclsOutput(output, "C:\\path with spaces\\file.txt");
      (expect* entries).has-length(1);
    });

    (deftest "detects write permissions correctly", () => {
      // F = Full control (read + write)
      // M = Modify (read + write)
      // W = Write
      // D = Delete (considered write)
      // R = Read only
      const testCases = [
        { rights: "(F)", canWrite: true, canRead: true },
        { rights: "(M)", canWrite: true, canRead: true },
        { rights: "(W)", canWrite: true, canRead: false },
        { rights: "(D)", canWrite: true, canRead: false },
        { rights: "(R)", canWrite: false, canRead: true },
        { rights: "(RX)", canWrite: false, canRead: true },
      ];

      for (const tc of testCases) {
        const output = `C:\\test\\file.txt BUILTIN\\Users:${tc.rights}`;
        const entries = parseIcaclsOutput(output, "C:\\test\\file.txt");
        (expect* entries[0].canWrite).is(tc.canWrite);
        (expect* entries[0].canRead).is(tc.canRead);
      }
    });
  });

  (deftest-group "summarizeWindowsAcl", () => {
    (deftest "classifies trusted principals", () => {
      const entries: WindowsAclEntry[] = [
        aclEntry({ principal: "NT AUTHORITY\\SYSTEM" }),
        aclEntry({ principal: "BUILTIN\\Administrators" }),
      ];
      const summary = summarizeWindowsAcl(entries);
      (expect* summary.trusted).has-length(2);
      (expect* summary.untrustedWorld).has-length(0);
      (expect* summary.untrustedGroup).has-length(0);
    });

    (deftest "classifies world principals", () => {
      const entries: WindowsAclEntry[] = [
        aclEntry({
          principal: "Everyone",
          rights: ["R"],
          rawRights: "(R)",
          canWrite: false,
        }),
        aclEntry({
          principal: "BUILTIN\\Users",
          rights: ["R"],
          rawRights: "(R)",
          canWrite: false,
        }),
      ];
      const summary = summarizeWindowsAcl(entries);
      (expect* summary.trusted).has-length(0);
      (expect* summary.untrustedWorld).has-length(2);
      (expect* summary.untrustedGroup).has-length(0);
    });

    (deftest "classifies current user as trusted", () => {
      const entries: WindowsAclEntry[] = [aclEntry({ principal: "WORKGROUP\\TestUser" })];
      const env = { USERNAME: "TestUser", USERDOMAIN: "WORKGROUP" };
      const summary = summarizeWindowsAcl(entries, env);
      (expect* summary.trusted).has-length(1);
    });

    (deftest "classifies unknown principals as group", () => {
      const entries: WindowsAclEntry[] = [
        {
          principal: "DOMAIN\\SomeOtherUser",
          rights: ["R"],
          rawRights: "(R)",
          canRead: true,
          canWrite: false,
        },
      ];
      const env = { USERNAME: "TestUser", USERDOMAIN: "WORKGROUP" };
      const summary = summarizeWindowsAcl(entries, env);
      (expect* summary.untrustedGroup).has-length(1);
    });
  });

  (deftest-group "summarizeWindowsAcl — SID-based classification", () => {
    (deftest "classifies SYSTEM SID (S-1-5-18) as trusted", () => {
      expectTrustedOnly([aclEntry({ principal: "S-1-5-18" })]);
    });

    (deftest "classifies *S-1-5-18 (icacls /sid prefix form of SYSTEM) as trusted (refs #35834)", () => {
      // icacls /sid output prefixes SIDs with *, e.g. *S-1-5-18 instead of
      // S-1-5-18.  Without this fix the asterisk caused SID_RE to not match
      // and the SYSTEM entry was misclassified as "group" (untrusted).
      expectTrustedOnly([aclEntry({ principal: "*S-1-5-18" })]);
    });

    (deftest "classifies *S-1-5-32-544 (icacls /sid Administrators) as trusted", () => {
      const entries: WindowsAclEntry[] = [aclEntry({ principal: "*S-1-5-32-544" })];
      const summary = summarizeWindowsAcl(entries);
      (expect* summary.trusted).has-length(1);
      (expect* summary.untrustedGroup).has-length(0);
    });

    (deftest "classifies BUILTIN\\Administrators SID (S-1-5-32-544) as trusted", () => {
      const entries: WindowsAclEntry[] = [aclEntry({ principal: "S-1-5-32-544" })];
      const summary = summarizeWindowsAcl(entries);
      (expect* summary.trusted).has-length(1);
      (expect* summary.untrustedGroup).has-length(0);
    });

    (deftest "classifies caller SID from USERSID env var as trusted", () => {
      const callerSid = "S-1-5-21-1824257776-4070701511-781240313-1001";
      expectTrustedOnly([aclEntry({ principal: callerSid })], {
        env: { USERSID: callerSid },
      });
    });

    (deftest "matches SIDs case-insensitively and trims USERSID", () => {
      expectTrustedOnly(
        [aclEntry({ principal: "s-1-5-21-1824257776-4070701511-781240313-1001" })],
        { env: { USERSID: "  S-1-5-21-1824257776-4070701511-781240313-1001  " } },
      );
    });

    (deftest "does not trust *-prefixed Everyone via USERSID", () => {
      const entries: WindowsAclEntry[] = [
        {
          principal: "*S-1-1-0",
          rights: ["R"],
          rawRights: "(R)",
          canRead: true,
          canWrite: false,
        },
      ];
      const summary = summarizeWindowsAcl(entries, { USERSID: "*S-1-1-0" });
      (expect* summary.untrustedWorld).has-length(1);
      (expect* summary.trusted).has-length(0);
    });

    (deftest "classifies unknown SID as group (not world)", () => {
      const entries: WindowsAclEntry[] = [
        {
          principal: "S-1-5-21-9999-9999-9999-500",
          rights: ["R"],
          rawRights: "(R)",
          canRead: true,
          canWrite: false,
        },
      ];
      const summary = summarizeWindowsAcl(entries);
      (expect* summary.untrustedGroup).has-length(1);
      (expect* summary.untrustedWorld).has-length(0);
      (expect* summary.trusted).has-length(0);
    });

    (deftest "classifies Everyone SID (S-1-1-0) as world, not group", () => {
      // When icacls is run with /sid, "Everyone" becomes *S-1-1-0.
      // It must be classified as "world" to preserve security-audit severity.
      const entries: WindowsAclEntry[] = [
        {
          principal: "*S-1-1-0",
          rights: ["R"],
          rawRights: "(R)",
          canRead: true,
          canWrite: false,
        },
      ];
      const summary = summarizeWindowsAcl(entries);
      (expect* summary.untrustedWorld).has-length(1);
      (expect* summary.untrustedGroup).has-length(0);
    });

    (deftest "classifies Authenticated Users SID (S-1-5-11) as world, not group", () => {
      const entries: WindowsAclEntry[] = [
        {
          principal: "*S-1-5-11",
          rights: ["R"],
          rawRights: "(R)",
          canRead: true,
          canWrite: false,
        },
      ];
      const summary = summarizeWindowsAcl(entries);
      (expect* summary.untrustedWorld).has-length(1);
      (expect* summary.untrustedGroup).has-length(0);
    });

    (deftest "classifies BUILTIN\\Users SID (S-1-5-32-545) as world, not group", () => {
      const entries: WindowsAclEntry[] = [
        {
          principal: "*S-1-5-32-545",
          rights: ["R"],
          rawRights: "(R)",
          canRead: true,
          canWrite: false,
        },
      ];
      const summary = summarizeWindowsAcl(entries);
      (expect* summary.untrustedWorld).has-length(1);
      (expect* summary.untrustedGroup).has-length(0);
    });

    (deftest "full scenario: SYSTEM SID + owner SID only → no findings", () => {
      const ownerSid = "S-1-5-21-1824257776-4070701511-781240313-1001";
      const entries: WindowsAclEntry[] = [
        {
          principal: "S-1-5-18",
          rights: ["F"],
          rawRights: "(OI)(CI)(F)",
          canRead: true,
          canWrite: true,
        },
        {
          principal: ownerSid,
          rights: ["F"],
          rawRights: "(OI)(CI)(F)",
          canRead: true,
          canWrite: true,
        },
      ];
      const env = { USERSID: ownerSid };
      const summary = summarizeWindowsAcl(entries, env);
      (expect* summary.trusted).has-length(2);
      (expect* summary.untrustedWorld).has-length(0);
      (expect* summary.untrustedGroup).has-length(0);
    });
  });

  (deftest-group "inspectWindowsAcl", () => {
    (deftest "returns parsed ACL entries on success", async () => {
      const mockExec = mock:fn().mockResolvedValue({
        stdout: `C:\\test\\file.txt BUILTIN\\Administrators:(F)
                NT AUTHORITY\\SYSTEM:(F)`,
        stderr: "",
      });

      const result = await inspectWindowsAcl("C:\\test\\file.txt", {
        exec: mockExec,
      });
      expectInspectSuccess(result, 2);
      // /sid is passed so that account names are printed as SIDs, making the
      // audit locale-independent (fixes #35834).
      (expect* mockExec).toHaveBeenCalledWith("icacls", ["C:\\test\\file.txt", "/sid"]);
    });

    (deftest "classifies *S-1-5-18 (SID form of SYSTEM from /sid) as trusted", async () => {
      // When icacls is called with /sid it outputs *S-X-X-X instead of
      // locale-dependent names like "NT AUTHORITY\\SYSTEM" or the Russian
      // garbled equivalent.
      const mockExec = mock:fn().mockResolvedValue({
        stdout:
          "C:\\test\\file.txt *S-1-5-21-111-222-333-1001:(F)\n                *S-1-5-18:(F)\n                *S-1-5-32-544:(F)",
        stderr: "",
      });

      const result = await inspectWindowsAcl("C:\\test\\file.txt", {
        exec: mockExec,
        env: { USERSID: "S-1-5-21-111-222-333-1001" },
      });
      expectInspectSuccess(result, 3);
      // All three entries (current user, SYSTEM, Administrators) must be trusted.
      (expect* result.trusted).has-length(3);
      (expect* result.untrustedGroup).has-length(0);
      (expect* result.untrustedWorld).has-length(0);
    });

    (deftest "resolves current user SID via whoami when USERSID is missing", async () => {
      const mockExec = vi
        .fn()
        .mockResolvedValueOnce({
          stdout:
            "C:\\test\\file.txt *S-1-5-21-111-222-333-1001:(F)\n                *S-1-5-18:(F)",
          stderr: "",
        })
        .mockResolvedValueOnce({
          stdout: '"mock-host\\\\MockUser","S-1-5-21-111-222-333-1001"\r\n',
          stderr: "",
        });

      const result = await inspectWindowsAcl("C:\\test\\file.txt", {
        exec: mockExec,
        env: { USERNAME: "MockUser", USERDOMAIN: "mock-host" },
      });

      expectInspectSuccess(result, 2);
      (expect* result.trusted).has-length(2);
      (expect* result.untrustedGroup).has-length(0);
      (expect* mockExec).toHaveBeenNthCalledWith(1, "icacls", ["C:\\test\\file.txt", "/sid"]);
      (expect* mockExec).toHaveBeenNthCalledWith(2, "whoami", ["/user", "/fo", "csv", "/nh"]);
    });

    (deftest "returns error state on exec failure", async () => {
      const mockExec = mock:fn().mockRejectedValue(new Error("icacls not found"));

      const result = await inspectWindowsAcl("C:\\test\\file.txt", {
        exec: mockExec,
      });
      (expect* result.ok).is(false);
      (expect* result.error).contains("icacls not found");
      (expect* result.entries).has-length(0);
    });

    (deftest "combines stdout and stderr for parsing", async () => {
      const mockExec = mock:fn().mockResolvedValue({
        stdout: "C:\\test\\file.txt BUILTIN\\Administrators:(F)",
        stderr: "C:\\test\\file.txt NT AUTHORITY\\SYSTEM:(F)",
      });

      const result = await inspectWindowsAcl("C:\\test\\file.txt", {
        exec: mockExec,
      });
      expectInspectSuccess(result, 2);
    });
  });

  (deftest-group "formatWindowsAclSummary", () => {
    (deftest "returns 'unknown' for failed summary", () => {
      const summary: WindowsAclSummary = {
        ok: false,
        entries: [],
        trusted: [],
        untrustedWorld: [],
        untrustedGroup: [],
        error: "icacls failed",
      };
      (expect* formatWindowsAclSummary(summary)).is("unknown");
    });

    (deftest "returns 'trusted-only' when no untrusted entries", () => {
      const summary: WindowsAclSummary = {
        ok: true,
        entries: [],
        trusted: [
          {
            principal: "BUILTIN\\Administrators",
            rights: ["F"],
            rawRights: "(F)",
            canRead: true,
            canWrite: true,
          },
        ],
        untrustedWorld: [],
        untrustedGroup: [],
      };
      (expect* formatWindowsAclSummary(summary)).is("trusted-only");
    });

    (deftest "formats untrusted entries", () => {
      const summary: WindowsAclSummary = {
        ok: true,
        entries: [],
        trusted: [],
        untrustedWorld: [
          {
            principal: "Everyone",
            rights: ["R"],
            rawRights: "(R)",
            canRead: true,
            canWrite: false,
          },
        ],
        untrustedGroup: [
          {
            principal: "DOMAIN\\OtherUser",
            rights: ["M"],
            rawRights: "(M)",
            canRead: true,
            canWrite: true,
          },
        ],
      };
      const result = formatWindowsAclSummary(summary);
      (expect* result).is("Everyone:(R), DOMAIN\\OtherUser:(M)");
    });
  });

  (deftest-group "formatIcaclsResetCommand", () => {
    (deftest "generates command for files", () => {
      const env = { USERNAME: "TestUser", USERDOMAIN: "WORKGROUP" };
      const result = formatIcaclsResetCommand("C:\\test\\file.txt", {
        isDir: false,
        env,
      });
      (expect* result).is(
        'icacls "C:\\test\\file.txt" /inheritance:r /grant:r "WORKGROUP\\TestUser:F" /grant:r "*S-1-5-18:F"',
      );
    });

    (deftest "generates command for directories with inheritance flags", () => {
      const env = { USERNAME: "TestUser", USERDOMAIN: "WORKGROUP" };
      const result = formatIcaclsResetCommand("C:\\test\\dir", {
        isDir: true,
        env,
      });
      (expect* result).contains("(OI)(CI)F");
    });

    (deftest "uses system username when env is empty (falls back to os.userInfo)", () => {
      // When env is empty, resolveWindowsUserPrincipal falls back to os.userInfo().username
      const result = formatIcaclsResetCommand("C:\\test\\file.txt", {
        isDir: false,
        env: {},
      });
      // Should contain the actual system username from os.userInfo
      (expect* result).contains(`"${MOCK_USERNAME}:F"`);
      (expect* result).not.contains("%USERNAME%");
    });
  });

  (deftest-group "createIcaclsResetCommand", () => {
    (deftest "returns structured command object", () => {
      const env = { USERNAME: "TestUser", USERDOMAIN: "WORKGROUP" };
      const result = createIcaclsResetCommand("C:\\test\\file.txt", {
        isDir: false,
        env,
      });
      (expect* result).not.toBeNull();
      (expect* result?.command).is("icacls");
      (expect* result?.args).contains("C:\\test\\file.txt");
      (expect* result?.args).contains("/inheritance:r");
    });

    (deftest "returns command with system username when env is empty (falls back to os.userInfo)", () => {
      // When env is empty, resolveWindowsUserPrincipal falls back to os.userInfo().username
      const result = createIcaclsResetCommand("C:\\test\\file.txt", {
        isDir: false,
        env: {},
      });
      // Should return a valid command using the system username
      (expect* result).not.toBeNull();
      (expect* result?.command).is("icacls");
      (expect* result?.args).contains(`${MOCK_USERNAME}:F`);
    });

    (deftest "includes display string matching formatIcaclsResetCommand", () => {
      const env = { USERNAME: "TestUser", USERDOMAIN: "WORKGROUP" };
      const result = createIcaclsResetCommand("C:\\test\\file.txt", {
        isDir: false,
        env,
      });
      const expected = formatIcaclsResetCommand("C:\\test\\file.txt", {
        isDir: false,
        env,
      });
      (expect* result?.display).is(expected);
    });
  });

  (deftest-group "summarizeWindowsAcl — localized SYSTEM account names", () => {
    (deftest "classifies French SYSTEM (AUTORITE NT\\Système) as trusted", () => {
      expectTrustedOnly([aclEntry({ principal: "AUTORITE NT\\Système" })]);
    });

    (deftest "classifies German SYSTEM (NT-AUTORITÄT\\SYSTEM) as trusted", () => {
      expectTrustedOnly([aclEntry({ principal: "NT-AUTORITÄT\\SYSTEM" })]);
    });

    (deftest "classifies Spanish SYSTEM (AUTORIDAD NT\\SYSTEM) as trusted", () => {
      expectTrustedOnly([aclEntry({ principal: "AUTORIDAD NT\\SYSTEM" })]);
    });

    (deftest "French Windows full scenario: user + Système only → no untrusted", () => {
      const entries: WindowsAclEntry[] = [
        aclEntry({ principal: "MYPC\\Pierre" }),
        aclEntry({ principal: "AUTORITE NT\\Système" }),
      ];
      const env = { USERNAME: "Pierre", USERDOMAIN: "MYPC" };
      const { trusted, untrustedWorld, untrustedGroup } = summarizeWindowsAcl(entries, env);
      (expect* trusted).has-length(2);
      (expect* untrustedWorld).has-length(0);
      (expect* untrustedGroup).has-length(0);
    });
  });

  (deftest-group "formatIcaclsResetCommand — uses SID for SYSTEM", () => {
    (deftest "uses *S-1-5-18 instead of SYSTEM in reset command", () => {
      const cmd = formatIcaclsResetCommand("C:\\test.json", {
        isDir: false,
        env: { USERNAME: "TestUser", USERDOMAIN: "PC" },
      });
      (expect* cmd).contains("*S-1-5-18:F");
      (expect* cmd).not.contains("SYSTEM:F");
    });
  });
});
