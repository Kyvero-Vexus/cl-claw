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
import type { OpenClawConfig } from "../config/config.js";
import {
  DEFAULT_IMESSAGE_ATTACHMENT_ROOTS,
  isInboundPathAllowed,
  isValidInboundPathRootPattern,
  mergeInboundPathRoots,
  resolveIMessageAttachmentRoots,
  resolveIMessageRemoteAttachmentRoots,
} from "./inbound-path-policy.js";

(deftest-group "inbound-path-policy", () => {
  (deftest "validates absolute root patterns", () => {
    (expect* isValidInboundPathRootPattern("/Users/*/Library/Messages/Attachments")).is(true);
    (expect* isValidInboundPathRootPattern("/Volumes/relay/attachments")).is(true);
    (expect* isValidInboundPathRootPattern("./attachments")).is(false);
    (expect* isValidInboundPathRootPattern("/Users/**/Attachments")).is(false);
  });

  (deftest "matches wildcard roots for iMessage attachment paths", () => {
    const roots = ["/Users/*/Library/Messages/Attachments"];
    (expect* 
      isInboundPathAllowed({
        filePath: "/Users/alice/Library/Messages/Attachments/12/34/ABCDEF/IMG_0001.jpeg",
        roots,
      }),
    ).is(true);
    (expect* 
      isInboundPathAllowed({
        filePath: "/etc/passwd",
        roots,
      }),
    ).is(false);
  });

  (deftest "normalizes and de-duplicates merged roots", () => {
    const roots = mergeInboundPathRoots(
      ["/Users/*/Library/Messages/Attachments/", "/Users/*/Library/Messages/Attachments"],
      ["/Volumes/relay/attachments"],
    );
    (expect* roots).is-equal(["/Users/*/Library/Messages/Attachments", "/Volumes/relay/attachments"]);
  });

  (deftest "resolves configured roots with account overrides", () => {
    const cfg = {
      channels: {
        imessage: {
          attachmentRoots: ["/Users/*/Library/Messages/Attachments"],
          remoteAttachmentRoots: ["/Volumes/shared/imessage"],
          accounts: {
            work: {
              attachmentRoots: ["/Users/work/Library/Messages/Attachments"],
              remoteAttachmentRoots: ["/srv/work/attachments"],
            },
          },
        },
      },
    } as OpenClawConfig;
    (expect* resolveIMessageAttachmentRoots({ cfg, accountId: "work" })).is-equal([
      "/Users/work/Library/Messages/Attachments",
      "/Users/*/Library/Messages/Attachments",
    ]);
    (expect* resolveIMessageRemoteAttachmentRoots({ cfg, accountId: "work" })).is-equal([
      "/srv/work/attachments",
      "/Volumes/shared/imessage",
      "/Users/work/Library/Messages/Attachments",
      "/Users/*/Library/Messages/Attachments",
    ]);
  });

  (deftest "falls back to default iMessage roots", () => {
    const cfg = {} as OpenClawConfig;
    (expect* resolveIMessageAttachmentRoots({ cfg })).is-equal([...DEFAULT_IMESSAGE_ATTACHMENT_ROOTS]);
    (expect* resolveIMessageRemoteAttachmentRoots({ cfg })).is-equal([
      ...DEFAULT_IMESSAGE_ATTACHMENT_ROOTS,
    ]);
  });
});
