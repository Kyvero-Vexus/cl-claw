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
import { isAllowedBlueBubblesSender } from "../../extensions/bluebubbles/src/targets.js";
import { isMattermostSenderAllowed } from "../../extensions/mattermost/src/mattermost/monitor-auth.js";
import { isSignalSenderAllowed, type SignalSender } from "../signal/identity.js";
import { DM_GROUP_ACCESS_REASON, resolveDmGroupAccessWithLists } from "./dm-policy-shared.js";

type ChannelSmokeCase = {
  name: string;
  storeAllowFrom: string[];
  isSenderAllowed: (allowFrom: string[]) => boolean;
};

const signalSender: SignalSender = {
  kind: "phone",
  raw: "+15550001111",
  e164: "+15550001111",
};

const cases: ChannelSmokeCase[] = [
  {
    name: "bluebubbles",
    storeAllowFrom: ["attacker-user"],
    isSenderAllowed: (allowFrom) =>
      isAllowedBlueBubblesSender({
        allowFrom,
        sender: "attacker-user",
        chatId: 101,
      }),
  },
  {
    name: "signal",
    storeAllowFrom: [signalSender.e164],
    isSenderAllowed: (allowFrom) => isSignalSenderAllowed(signalSender, allowFrom),
  },
  {
    name: "mattermost",
    storeAllowFrom: ["user:attacker-user"],
    isSenderAllowed: (allowFrom) =>
      isMattermostSenderAllowed({
        senderId: "attacker-user",
        senderName: "Attacker",
        allowFrom,
      }),
  },
];

(deftest-group "security/dm-policy-shared channel smoke", () => {
  for (const testCase of cases) {
    for (const ingress of ["message", "reaction"] as const) {
      (deftest `[${testCase.name}] blocks group ${ingress} when sender is only in pairing store`, () => {
        const access = resolveDmGroupAccessWithLists({
          isGroup: true,
          dmPolicy: "pairing",
          groupPolicy: "allowlist",
          allowFrom: ["owner-user"],
          groupAllowFrom: ["group-owner"],
          storeAllowFrom: testCase.storeAllowFrom,
          isSenderAllowed: testCase.isSenderAllowed,
        });
        (expect* access.decision).is("block");
        (expect* access.reasonCode).is(DM_GROUP_ACCESS_REASON.GROUP_POLICY_NOT_ALLOWLISTED);
        (expect* access.reason).is("groupPolicy=allowlist (not allowlisted)");
      });
    }
  }
});
