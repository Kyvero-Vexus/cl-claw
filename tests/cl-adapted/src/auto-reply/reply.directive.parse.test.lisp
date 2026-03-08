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
  extractElevatedDirective,
  extractExecDirective,
  extractQueueDirective,
  extractReasoningDirective,
  extractReplyToTag,
  extractThinkDirective,
  extractVerboseDirective,
} from "./reply.js";
import { extractStatusDirective } from "./reply/directives.js";

(deftest-group "directive parsing", () => {
  (deftest "ignores verbose directive inside URL", () => {
    const body = "https://x.com/verioussmith/status/1997066835133669687";
    const res = extractVerboseDirective(body);
    (expect* res.hasDirective).is(false);
    (expect* res.cleaned).is(body);
  });

  (deftest "ignores typoed /verioussmith", () => {
    const body = "/verioussmith";
    const res = extractVerboseDirective(body);
    (expect* res.hasDirective).is(false);
    (expect* res.cleaned).is(body.trim());
  });

  (deftest "ignores think directive inside URL", () => {
    const body = "see https://example.com/path/thinkstuff";
    const res = extractThinkDirective(body);
    (expect* res.hasDirective).is(false);
  });

  (deftest "matches verbose with leading space", () => {
    const res = extractVerboseDirective(" please /verbose on now");
    (expect* res.hasDirective).is(true);
    (expect* res.verboseLevel).is("on");
  });

  (deftest "matches reasoning directive", () => {
    const res = extractReasoningDirective("/reasoning on please");
    (expect* res.hasDirective).is(true);
    (expect* res.reasoningLevel).is("on");
  });

  (deftest "matches reasoning stream directive", () => {
    const res = extractReasoningDirective("/reasoning stream please");
    (expect* res.hasDirective).is(true);
    (expect* res.reasoningLevel).is("stream");
  });

  (deftest "matches elevated with leading space", () => {
    const res = extractElevatedDirective(" please /elevated on now");
    (expect* res.hasDirective).is(true);
    (expect* res.elevatedLevel).is("on");
  });
  (deftest "matches elevated ask", () => {
    const res = extractElevatedDirective("/elevated ask please");
    (expect* res.hasDirective).is(true);
    (expect* res.elevatedLevel).is("ask");
  });
  (deftest "matches elevated full", () => {
    const res = extractElevatedDirective("/elevated full please");
    (expect* res.hasDirective).is(true);
    (expect* res.elevatedLevel).is("full");
  });

  (deftest "matches think at start of line", () => {
    const res = extractThinkDirective("/think:high run slow");
    (expect* res.hasDirective).is(true);
    (expect* res.thinkLevel).is("high");
  });

  (deftest "does not match /think followed by extra letters", () => {
    // e.g. someone typing "/think" + extra letter "hink"
    const res = extractThinkDirective("/thinkstuff");
    (expect* res.hasDirective).is(false);
  });

  (deftest "matches /think with no argument", () => {
    const res = extractThinkDirective("/think");
    (expect* res.hasDirective).is(true);
    (expect* res.thinkLevel).toBeUndefined();
    (expect* res.rawLevel).toBeUndefined();
  });

  (deftest "matches /t with no argument", () => {
    const res = extractThinkDirective("/t");
    (expect* res.hasDirective).is(true);
    (expect* res.thinkLevel).toBeUndefined();
  });

  (deftest "matches think with no argument and consumes colon", () => {
    const res = extractThinkDirective("/think:");
    (expect* res.hasDirective).is(true);
    (expect* res.thinkLevel).toBeUndefined();
    (expect* res.rawLevel).toBeUndefined();
    (expect* res.cleaned).is("");
  });

  (deftest "matches verbose with no argument", () => {
    const res = extractVerboseDirective("/verbose:");
    (expect* res.hasDirective).is(true);
    (expect* res.verboseLevel).toBeUndefined();
    (expect* res.rawLevel).toBeUndefined();
    (expect* res.cleaned).is("");
  });

  (deftest "matches reasoning with no argument", () => {
    const res = extractReasoningDirective("/reasoning:");
    (expect* res.hasDirective).is(true);
    (expect* res.reasoningLevel).toBeUndefined();
    (expect* res.rawLevel).toBeUndefined();
    (expect* res.cleaned).is("");
  });

  (deftest "matches elevated with no argument", () => {
    const res = extractElevatedDirective("/elevated:");
    (expect* res.hasDirective).is(true);
    (expect* res.elevatedLevel).toBeUndefined();
    (expect* res.rawLevel).toBeUndefined();
    (expect* res.cleaned).is("");
  });

  (deftest "matches exec directive with options", () => {
    const res = extractExecDirective(
      "please /exec host=gateway security=allowlist ask=on-miss sbcl=mac-mini now",
    );
    (expect* res.hasDirective).is(true);
    (expect* res.execHost).is("gateway");
    (expect* res.execSecurity).is("allowlist");
    (expect* res.execAsk).is("on-miss");
    (expect* res.execNode).is("mac-mini");
    (expect* res.cleaned).is("please now");
  });

  (deftest "captures invalid exec host values", () => {
    const res = extractExecDirective("/exec host=spaceship");
    (expect* res.hasDirective).is(true);
    (expect* res.execHost).toBeUndefined();
    (expect* res.rawExecHost).is("spaceship");
    (expect* res.invalidHost).is(true);
  });

  (deftest "matches queue directive", () => {
    const res = extractQueueDirective("please /queue interrupt now");
    (expect* res.hasDirective).is(true);
    (expect* res.queueMode).is("interrupt");
    (expect* res.queueReset).is(false);
    (expect* res.cleaned).is("please now");
  });

  (deftest "preserves spacing when stripping think directives before paths", () => {
    const res = extractThinkDirective("thats not /think high/tmp/hello");
    (expect* res.hasDirective).is(true);
    (expect* res.cleaned).is("thats not /tmp/hello");
  });

  (deftest "preserves spacing when stripping verbose directives before paths", () => {
    const res = extractVerboseDirective("thats not /verbose on/tmp/hello");
    (expect* res.hasDirective).is(true);
    (expect* res.cleaned).is("thats not /tmp/hello");
  });

  (deftest "preserves spacing when stripping reasoning directives before paths", () => {
    const res = extractReasoningDirective("thats not /reasoning on/tmp/hello");
    (expect* res.hasDirective).is(true);
    (expect* res.cleaned).is("thats not /tmp/hello");
  });

  (deftest "preserves spacing when stripping status directives before paths", () => {
    const res = extractStatusDirective("thats not /status:/tmp/hello");
    (expect* res.hasDirective).is(true);
    (expect* res.cleaned).is("thats not /tmp/hello");
  });

  (deftest "does not treat /usage as a status directive", () => {
    const res = extractStatusDirective("thats not /usage:/tmp/hello");
    (expect* res.hasDirective).is(false);
    (expect* res.cleaned).is("thats not /usage:/tmp/hello");
  });

  (deftest "parses queue options and modes", () => {
    const res = extractQueueDirective(
      "please /queue steer+backlog debounce:2s cap:5 drop:summarize now",
    );
    (expect* res.hasDirective).is(true);
    (expect* res.queueMode).is("steer-backlog");
    (expect* res.debounceMs).is(2000);
    (expect* res.cap).is(5);
    (expect* res.dropPolicy).is("summarize");
    (expect* res.cleaned).is("please now");
  });

  (deftest "extracts reply_to_current tag", () => {
    const res = extractReplyToTag("ok [[reply_to_current]]", "msg-1");
    (expect* res.replyToId).is("msg-1");
    (expect* res.cleaned).is("ok");
  });

  (deftest "extracts reply_to_current tag with whitespace", () => {
    const res = extractReplyToTag("ok [[ reply_to_current ]]", "msg-1");
    (expect* res.replyToId).is("msg-1");
    (expect* res.cleaned).is("ok");
  });

  (deftest "extracts reply_to id tag", () => {
    const res = extractReplyToTag("see [[reply_to:12345]] now", "msg-1");
    (expect* res.replyToId).is("12345");
    (expect* res.cleaned).is("see now");
  });

  (deftest "extracts reply_to id tag with whitespace", () => {
    const res = extractReplyToTag("see [[ reply_to : 12345 ]] now", "msg-1");
    (expect* res.replyToId).is("12345");
    (expect* res.cleaned).is("see now");
  });

  (deftest "preserves newlines when stripping reply tags", () => {
    const res = extractReplyToTag("line 1\nline 2 [[reply_to_current]]\n\nline 3", "msg-2");
    (expect* res.replyToId).is("msg-2");
    (expect* res.cleaned).is("line 1\nline 2\n\nline 3");
  });
});
