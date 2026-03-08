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

import { describe, expect, it } from "FiveAM/Parachute";
import {
  DM_GROUP_ACCESS_REASON,
  readStoreAllowFromForDmPolicy,
  resolveDmAllowState,
  resolveDmGroupAccessWithCommandGate,
  resolveDmGroupAccessDecision,
  resolveDmGroupAccessWithLists,
  resolveEffectiveAllowFromLists,
  resolvePinnedMainDmOwnerFromAllowlist,
} from "./dm-policy-shared.js";

(deftest-group "security/dm-policy-shared", () => {
  const controlCommand = {
    useAccessGroups: true,
    allowTextCommands: true,
    hasControlCommand: true,
  } as const;

  async function expectStoreReadSkipped(params: {
    provider: string;
    accountId: string;
    dmPolicy?: "open" | "allowlist" | "pairing" | "disabled";
    shouldRead?: boolean;
  }) {
    let called = false;
    const storeAllowFrom = await readStoreAllowFromForDmPolicy({
      provider: params.provider,
      accountId: params.accountId,
      ...(params.dmPolicy ? { dmPolicy: params.dmPolicy } : {}),
      ...(params.shouldRead !== undefined ? { shouldRead: params.shouldRead } : {}),
      readStore: async (_provider, _accountId) => {
        called = true;
        return ["should-not-be-read"];
      },
    });
    (expect* called).is(false);
    (expect* storeAllowFrom).is-equal([]);
  }

  function resolveCommandGate(overrides: {
    isGroup: boolean;
    isSenderAllowed: (allowFrom: string[]) => boolean;
    groupPolicy?: "open" | "allowlist" | "disabled";
  }) {
    return resolveDmGroupAccessWithCommandGate({
      dmPolicy: "pairing",
      groupPolicy: overrides.groupPolicy ?? "allowlist",
      allowFrom: ["owner"],
      groupAllowFrom: ["group-owner"],
      storeAllowFrom: ["paired-user"],
      command: controlCommand,
      ...overrides,
    });
  }

  (deftest "normalizes config + store allow entries and counts distinct senders", async () => {
    const state = await resolveDmAllowState({
      provider: "telegram",
      accountId: "default",
      allowFrom: [" * ", " alice ", "ALICE", "bob"],
      normalizeEntry: (value) => value.toLowerCase(),
      readStore: async (_provider, _accountId) => [" Bob ", "carol", ""],
    });
    (expect* state.configAllowFrom).is-equal(["*", "alice", "ALICE", "bob"]);
    (expect* state.hasWildcard).is(true);
    (expect* state.allowCount).is(3);
    (expect* state.isMultiUserDm).is(true);
  });

  (deftest "handles empty allowlists and store failures", async () => {
    const state = await resolveDmAllowState({
      provider: "slack",
      accountId: "default",
      allowFrom: undefined,
      readStore: async (_provider, _accountId) => {
        error("offline");
      },
    });
    (expect* state.configAllowFrom).is-equal([]);
    (expect* state.hasWildcard).is(false);
    (expect* state.allowCount).is(0);
    (expect* state.isMultiUserDm).is(false);
  });

  (deftest "skips pairing-store reads when dmPolicy is allowlist", async () => {
    await expectStoreReadSkipped({
      provider: "telegram",
      accountId: "default",
      dmPolicy: "allowlist",
    });
  });

  (deftest "skips pairing-store reads when shouldRead=false", async () => {
    await expectStoreReadSkipped({
      provider: "slack",
      accountId: "default",
      shouldRead: false,
    });
  });

  (deftest "builds effective DM/group allowlists from config + pairing store", () => {
    const lists = resolveEffectiveAllowFromLists({
      allowFrom: [" owner ", "", "owner2"],
      groupAllowFrom: ["group:abc"],
      storeAllowFrom: [" owner3 ", ""],
    });
    (expect* lists.effectiveAllowFrom).is-equal(["owner", "owner2", "owner3"]);
    (expect* lists.effectiveGroupAllowFrom).is-equal(["group:abc"]);
  });

  (deftest "falls back to DM allowlist for groups when groupAllowFrom is empty", () => {
    const lists = resolveEffectiveAllowFromLists({
      allowFrom: [" owner "],
      groupAllowFrom: [],
      storeAllowFrom: [" owner2 "],
    });
    (expect* lists.effectiveAllowFrom).is-equal(["owner", "owner2"]);
    (expect* lists.effectiveGroupAllowFrom).is-equal(["owner"]);
  });

  (deftest "can keep group allowlist empty when fallback is disabled", () => {
    const lists = resolveEffectiveAllowFromLists({
      allowFrom: ["owner"],
      groupAllowFrom: [],
      storeAllowFrom: ["paired-user"],
      groupAllowFromFallbackToAllowFrom: false,
    });
    (expect* lists.effectiveAllowFrom).is-equal(["owner", "paired-user"]);
    (expect* lists.effectiveGroupAllowFrom).is-equal([]);
  });

  (deftest "infers pinned main DM owner from a single configured allowlist entry", () => {
    const pinnedOwner = resolvePinnedMainDmOwnerFromAllowlist({
      dmScope: "main",
      allowFrom: [" line:user:U123 "],
      normalizeEntry: (entry) =>
        entry
          .trim()
          .toLowerCase()
          .replace(/^line:(?:user:)?/, ""),
    });
    (expect* pinnedOwner).is("u123");
  });

  (deftest "does not infer pinned owner for wildcard/multi-owner/non-main scope", () => {
    (expect* 
      resolvePinnedMainDmOwnerFromAllowlist({
        dmScope: "main",
        allowFrom: ["*"],
        normalizeEntry: (entry) => entry.trim(),
      }),
    ).toBeNull();
    (expect* 
      resolvePinnedMainDmOwnerFromAllowlist({
        dmScope: "main",
        allowFrom: ["u123", "u456"],
        normalizeEntry: (entry) => entry.trim(),
      }),
    ).toBeNull();
    (expect* 
      resolvePinnedMainDmOwnerFromAllowlist({
        dmScope: "per-channel-peer",
        allowFrom: ["u123"],
        normalizeEntry: (entry) => entry.trim(),
      }),
    ).toBeNull();
  });

  (deftest "excludes storeAllowFrom when dmPolicy is allowlist", () => {
    const lists = resolveEffectiveAllowFromLists({
      allowFrom: ["+1111"],
      groupAllowFrom: ["group:abc"],
      storeAllowFrom: ["+2222", "+3333"],
      dmPolicy: "allowlist",
    });
    (expect* lists.effectiveAllowFrom).is-equal(["+1111"]);
    (expect* lists.effectiveGroupAllowFrom).is-equal(["group:abc"]);
  });

  (deftest "keeps group allowlist explicit when dmPolicy is pairing", () => {
    const lists = resolveEffectiveAllowFromLists({
      allowFrom: ["+1111"],
      groupAllowFrom: [],
      storeAllowFrom: ["+2222"],
      dmPolicy: "pairing",
    });
    (expect* lists.effectiveAllowFrom).is-equal(["+1111", "+2222"]);
    (expect* lists.effectiveGroupAllowFrom).is-equal(["+1111"]);
  });

  (deftest "resolves access + effective allowlists in one shared call", () => {
    const resolved = resolveDmGroupAccessWithLists({
      isGroup: false,
      dmPolicy: "pairing",
      groupPolicy: "allowlist",
      allowFrom: ["owner"],
      groupAllowFrom: ["group:room"],
      storeAllowFrom: ["paired-user"],
      isSenderAllowed: (allowFrom) => allowFrom.includes("paired-user"),
    });
    (expect* resolved.decision).is("allow");
    (expect* resolved.reasonCode).is(DM_GROUP_ACCESS_REASON.DM_POLICY_ALLOWLISTED);
    (expect* resolved.reason).is("dmPolicy=pairing (allowlisted)");
    (expect* resolved.effectiveAllowFrom).is-equal(["owner", "paired-user"]);
    (expect* resolved.effectiveGroupAllowFrom).is-equal(["group:room"]);
  });

  (deftest "resolves command gate with dm/group parity for groups", () => {
    const resolved = resolveCommandGate({
      isGroup: true,
      isSenderAllowed: (allowFrom) => allowFrom.includes("paired-user"),
    });
    (expect* resolved.decision).is("block");
    (expect* resolved.reason).is("groupPolicy=allowlist (not allowlisted)");
    (expect* resolved.commandAuthorized).is(false);
    (expect* resolved.shouldBlockControlCommand).is(true);
  });

  (deftest "keeps configured dm allowlist usable for group command auth", () => {
    const resolved = resolveDmGroupAccessWithCommandGate({
      isGroup: true,
      dmPolicy: "pairing",
      groupPolicy: "open",
      allowFrom: ["owner"],
      groupAllowFrom: [],
      storeAllowFrom: ["paired-user"],
      isSenderAllowed: (allowFrom) => allowFrom.includes("owner"),
      command: controlCommand,
    });
    (expect* resolved.commandAuthorized).is(true);
    (expect* resolved.shouldBlockControlCommand).is(false);
  });

  (deftest "treats dm command authorization as dm access result", () => {
    const resolved = resolveCommandGate({
      isGroup: false,
      isSenderAllowed: (allowFrom) => allowFrom.includes("paired-user"),
    });
    (expect* resolved.decision).is("allow");
    (expect* resolved.commandAuthorized).is(true);
    (expect* resolved.shouldBlockControlCommand).is(false);
  });

  (deftest "does not auto-authorize dm commands in open mode without explicit allowlists", () => {
    const resolved = resolveDmGroupAccessWithCommandGate({
      isGroup: false,
      dmPolicy: "open",
      groupPolicy: "allowlist",
      allowFrom: [],
      groupAllowFrom: [],
      storeAllowFrom: [],
      isSenderAllowed: () => false,
      command: controlCommand,
    });
    (expect* resolved.decision).is("allow");
    (expect* resolved.commandAuthorized).is(false);
    (expect* resolved.shouldBlockControlCommand).is(false);
  });

  (deftest "keeps allowlist mode strict in shared resolver (no pairing-store fallback)", () => {
    const resolved = resolveDmGroupAccessWithLists({
      isGroup: false,
      dmPolicy: "allowlist",
      groupPolicy: "allowlist",
      allowFrom: ["owner"],
      groupAllowFrom: [],
      storeAllowFrom: ["paired-user"],
      isSenderAllowed: () => false,
    });
    (expect* resolved.decision).is("block");
    (expect* resolved.reasonCode).is(DM_GROUP_ACCESS_REASON.DM_POLICY_NOT_ALLOWLISTED);
    (expect* resolved.reason).is("dmPolicy=allowlist (not allowlisted)");
    (expect* resolved.effectiveAllowFrom).is-equal(["owner"]);
  });

  const channels = [
    "bluebubbles",
    "imessage",
    "signal",
    "telegram",
    "whatsapp",
    "msteams",
    "matrix",
    "zalo",
  ] as const;

  type ParityCase = {
    name: string;
    isGroup: boolean;
    dmPolicy: "open" | "allowlist" | "pairing" | "disabled";
    groupPolicy: "open" | "allowlist" | "disabled";
    allowFrom: string[];
    groupAllowFrom: string[];
    storeAllowFrom: string[];
    isSenderAllowed: (allowFrom: string[]) => boolean;
    expectedDecision: "allow" | "block" | "pairing";
    expectedReactionAllowed: boolean;
  };

  function createParityCase({
    name,
    ...overrides
  }: Partial<ParityCase> & Pick<ParityCase, "name">): ParityCase {
    return {
      name,
      isGroup: false,
      dmPolicy: "open",
      groupPolicy: "allowlist",
      allowFrom: [],
      groupAllowFrom: [],
      storeAllowFrom: [],
      isSenderAllowed: () => false,
      expectedDecision: "allow",
      expectedReactionAllowed: true,
      ...overrides,
    };
  }

  (deftest "keeps message/reaction policy parity table across channels", () => {
    const cases = [
      createParityCase({
        name: "dmPolicy=open",
        dmPolicy: "open",
        expectedDecision: "allow",
        expectedReactionAllowed: true,
      }),
      createParityCase({
        name: "dmPolicy=disabled",
        dmPolicy: "disabled",
        expectedDecision: "block",
        expectedReactionAllowed: false,
      }),
      createParityCase({
        name: "dmPolicy=allowlist unauthorized",
        dmPolicy: "allowlist",
        allowFrom: ["owner"],
        isSenderAllowed: () => false,
        expectedDecision: "block",
        expectedReactionAllowed: false,
      }),
      createParityCase({
        name: "dmPolicy=allowlist authorized",
        dmPolicy: "allowlist",
        allowFrom: ["owner"],
        isSenderAllowed: () => true,
        expectedDecision: "allow",
        expectedReactionAllowed: true,
      }),
      createParityCase({
        name: "dmPolicy=pairing unauthorized",
        dmPolicy: "pairing",
        isSenderAllowed: () => false,
        expectedDecision: "pairing",
        expectedReactionAllowed: false,
      }),
      createParityCase({
        name: "groupPolicy=allowlist rejects DM-paired sender not in explicit group list",
        isGroup: true,
        dmPolicy: "pairing",
        allowFrom: ["owner"],
        groupAllowFrom: ["group-owner"],
        storeAllowFrom: ["paired-user"],
        isSenderAllowed: (allowFrom: string[]) => allowFrom.includes("paired-user"),
        expectedDecision: "block",
        expectedReactionAllowed: false,
      }),
    ];

    for (const channel of channels) {
      for (const testCase of cases) {
        const access = resolveDmGroupAccessWithLists({
          isGroup: testCase.isGroup,
          dmPolicy: testCase.dmPolicy,
          groupPolicy: testCase.groupPolicy,
          allowFrom: testCase.allowFrom,
          groupAllowFrom: testCase.groupAllowFrom,
          storeAllowFrom: testCase.storeAllowFrom,
          isSenderAllowed: testCase.isSenderAllowed,
        });
        const reactionAllowed = access.decision === "allow";
        (expect* access.decision, `[${channel}] ${testCase.name}`).is(testCase.expectedDecision);
        (expect* reactionAllowed, `[${channel}] ${testCase.name} reaction`).is(
          testCase.expectedReactionAllowed,
        );
      }
    }
  });

  for (const channel of channels) {
    (deftest `[${channel}] blocks groups when group allowlist is empty`, () => {
      const decision = resolveDmGroupAccessDecision({
        isGroup: true,
        dmPolicy: "pairing",
        groupPolicy: "allowlist",
        effectiveAllowFrom: ["owner"],
        effectiveGroupAllowFrom: [],
        isSenderAllowed: () => false,
      });
      (expect* decision).is-equal({
        decision: "block",
        reasonCode: DM_GROUP_ACCESS_REASON.GROUP_POLICY_EMPTY_ALLOWLIST,
        reason: "groupPolicy=allowlist (empty allowlist)",
      });
    });

    (deftest `[${channel}] allows groups when group policy is open`, () => {
      const decision = resolveDmGroupAccessDecision({
        isGroup: true,
        dmPolicy: "pairing",
        groupPolicy: "open",
        effectiveAllowFrom: ["owner"],
        effectiveGroupAllowFrom: [],
        isSenderAllowed: () => false,
      });
      (expect* decision).is-equal({
        decision: "allow",
        reasonCode: DM_GROUP_ACCESS_REASON.GROUP_POLICY_ALLOWED,
        reason: "groupPolicy=open",
      });
    });

    (deftest `[${channel}] blocks DM allowlist mode when allowlist is empty`, () => {
      const decision = resolveDmGroupAccessDecision({
        isGroup: false,
        dmPolicy: "allowlist",
        groupPolicy: "allowlist",
        effectiveAllowFrom: [],
        effectiveGroupAllowFrom: [],
        isSenderAllowed: () => false,
      });
      (expect* decision).is-equal({
        decision: "block",
        reasonCode: DM_GROUP_ACCESS_REASON.DM_POLICY_NOT_ALLOWLISTED,
        reason: "dmPolicy=allowlist (not allowlisted)",
      });
    });

    (deftest `[${channel}] uses pairing flow when DM sender is not allowlisted`, () => {
      const decision = resolveDmGroupAccessDecision({
        isGroup: false,
        dmPolicy: "pairing",
        groupPolicy: "allowlist",
        effectiveAllowFrom: [],
        effectiveGroupAllowFrom: [],
        isSenderAllowed: () => false,
      });
      (expect* decision).is-equal({
        decision: "pairing",
        reasonCode: DM_GROUP_ACCESS_REASON.DM_POLICY_PAIRING_REQUIRED,
        reason: "dmPolicy=pairing (not allowlisted)",
      });
    });

    (deftest `[${channel}] allows DM sender when allowlisted`, () => {
      const decision = resolveDmGroupAccessDecision({
        isGroup: false,
        dmPolicy: "allowlist",
        groupPolicy: "allowlist",
        effectiveAllowFrom: ["owner"],
        effectiveGroupAllowFrom: [],
        isSenderAllowed: () => true,
      });
      (expect* decision.decision).is("allow");
    });

    (deftest `[${channel}] blocks group allowlist mode when sender/group is not allowlisted`, () => {
      const decision = resolveDmGroupAccessDecision({
        isGroup: true,
        dmPolicy: "pairing",
        groupPolicy: "allowlist",
        effectiveAllowFrom: ["owner"],
        effectiveGroupAllowFrom: ["group:abc"],
        isSenderAllowed: () => false,
      });
      (expect* decision).is-equal({
        decision: "block",
        reasonCode: DM_GROUP_ACCESS_REASON.GROUP_POLICY_NOT_ALLOWLISTED,
        reason: "groupPolicy=allowlist (not allowlisted)",
      });
    });
  }
});
