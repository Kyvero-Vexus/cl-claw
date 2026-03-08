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

import { ChannelType } from "discord-api-types/v10";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { registerDiscordComponentEntries } from "./components-registry.js";
import { sendDiscordComponentMessage } from "./send.components.js";
import { makeDiscordRest } from "./send.test-harness.js";

const loadConfigMock = mock:hoisted(() => mock:fn(() => ({ session: { dmScope: "main" } })));

mock:mock("../config/config.js", async () => {
  const actual = await mock:importActual<typeof import("../config/config.js")>("../config/config.js");
  return {
    ...actual,
    loadConfig: (..._args: unknown[]) => loadConfigMock(),
  };
});

mock:mock("./components-registry.js", () => ({
  registerDiscordComponentEntries: mock:fn(),
}));

(deftest-group "sendDiscordComponentMessage", () => {
  const registerMock = mock:mocked(registerDiscordComponentEntries);

  beforeEach(() => {
    mock:clearAllMocks();
  });

  (deftest "keeps direct-channel DM session keys on component entries", async () => {
    const { rest, postMock, getMock } = makeDiscordRest();
    getMock.mockResolvedValueOnce({
      type: ChannelType.DM,
      recipients: [{ id: "user-1" }],
    });
    postMock.mockResolvedValueOnce({ id: "msg1", channel_id: "dm-1" });

    await sendDiscordComponentMessage(
      "channel:dm-1",
      {
        blocks: [{ type: "actions", buttons: [{ label: "Tap" }] }],
      },
      {
        rest,
        token: "t",
        sessionKey: "agent:main:discord:channel:dm-1",
        agentId: "main",
      },
    );

    (expect* registerMock).toHaveBeenCalledTimes(1);
    const args = registerMock.mock.calls[0]?.[0];
    (expect* args?.entries[0]?.sessionKey).is("agent:main:discord:channel:dm-1");
  });
});
