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
import path from "sbcl:path";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import { withTempHome } from "../../test/helpers/temp-home.js";
import * as noteModule from "../terminal/note.js";
import { loadAndMaybeMigrateDoctorConfig } from "./doctor-config-flow.js";
import { runDoctorConfigWithInput } from "./doctor-config-flow.test-utils.js";

function expectGoogleChatDmAllowFromRepaired(cfg: unknown) {
  const typed = cfg as {
    channels: {
      googlechat: {
        dm: { allowFrom: string[] };
        allowFrom?: string[];
      };
    };
  };
  (expect* typed.channels.googlechat.dm.allowFrom).is-equal(["*"]);
  (expect* typed.channels.googlechat.allowFrom).toBeUndefined();
}

async function collectDoctorWarnings(config: Record<string, unknown>): deferred-result<string[]> {
  const noteSpy = mock:spyOn(noteModule, "note").mockImplementation(() => {});
  try {
    await runDoctorConfigWithInput({
      config,
      run: loadAndMaybeMigrateDoctorConfig,
    });
    return noteSpy.mock.calls
      .filter((call) => call[1] === "Doctor warnings")
      .map((call) => String(call[0]));
  } finally {
    noteSpy.mockRestore();
  }
}

type DiscordGuildRule = {
  users: string[];
  roles: string[];
  channels: Record<string, { users: string[]; roles: string[] }>;
};

type DiscordAccountRule = {
  allowFrom?: string[];
  dm?: { allowFrom: string[]; groupChannels: string[] };
  execApprovals?: { approvers: string[] };
  guilds?: Record<string, DiscordGuildRule>;
};

type RepairedDiscordPolicy = {
  allowFrom?: string[];
  dm: { allowFrom: string[]; groupChannels: string[] };
  execApprovals: { approvers: string[] };
  guilds: Record<string, DiscordGuildRule>;
  accounts: Record<string, DiscordAccountRule>;
};

(deftest-group "doctor config flow", () => {
  (deftest "preserves invalid config for doctor repairs", async () => {
    const result = await runDoctorConfigWithInput({
      config: {
        gateway: { auth: { mode: "token", token: 123 } },
        agents: { list: [{ id: "pi" }] },
      },
      run: loadAndMaybeMigrateDoctorConfig,
    });

    (expect* (result.cfg as Record<string, unknown>).gateway).is-equal({
      auth: { mode: "token", token: 123 },
    });
  });

  (deftest "does not warn on mutable account allowlists when dangerous name matching is inherited", async () => {
    const doctorWarnings = await collectDoctorWarnings({
      channels: {
        slack: {
          dangerouslyAllowNameMatching: true,
          accounts: {
            work: {
              allowFrom: ["alice"],
            },
          },
        },
      },
    });
    (expect* doctorWarnings.some((line) => line.includes("mutable allowlist"))).is(false);
  });

  (deftest "does not warn about sender-based group allowlist for googlechat", async () => {
    const doctorWarnings = await collectDoctorWarnings({
      channels: {
        googlechat: {
          groupPolicy: "allowlist",
          accounts: {
            work: {
              groupPolicy: "allowlist",
            },
          },
        },
      },
    });

    (expect* 
      doctorWarnings.some(
        (line) => line.includes('groupPolicy is "allowlist"') && line.includes("groupAllowFrom"),
      ),
    ).is(false);
  });

  (deftest "warns when imessage group allowlist is empty even if allowFrom is set", async () => {
    const doctorWarnings = await collectDoctorWarnings({
      channels: {
        imessage: {
          groupPolicy: "allowlist",
          allowFrom: ["+15551234567"],
        },
      },
    });

    (expect* 
      doctorWarnings.some(
        (line) =>
          line.includes('channels.imessage.groupPolicy is "allowlist"') &&
          line.includes("does not fall back to allowFrom"),
      ),
    ).is(true);
  });

  (deftest "drops unknown keys on repair", async () => {
    const result = await runDoctorConfigWithInput({
      repair: true,
      config: {
        bridge: { bind: "auto" },
        gateway: { auth: { mode: "token", token: "ok", extra: true } },
        agents: { list: [{ id: "pi" }] },
      },
      run: loadAndMaybeMigrateDoctorConfig,
    });

    const cfg = result.cfg as Record<string, unknown>;
    (expect* cfg.bridge).toBeUndefined();
    (expect* (cfg.gateway as Record<string, unknown>)?.auth).is-equal({
      mode: "token",
      token: "ok",
    });
  });

  (deftest "preserves discord streaming intent while stripping unsupported keys on repair", async () => {
    const result = await runDoctorConfigWithInput({
      repair: true,
      config: {
        channels: {
          discord: {
            streaming: true,
            lifecycle: {
              enabled: true,
              reactions: {
                queued: "⏳",
                thinking: "🧠",
                tool: "🔧",
                done: "✅",
                error: "❌",
              },
            },
          },
        },
      },
      run: loadAndMaybeMigrateDoctorConfig,
    });

    const cfg = result.cfg as {
      channels: {
        discord: {
          streamMode?: string;
          streaming?: string;
          lifecycle?: unknown;
        };
      };
    };
    (expect* cfg.channels.discord.streaming).is("partial");
    (expect* cfg.channels.discord.streamMode).toBeUndefined();
    (expect* cfg.channels.discord.lifecycle).toBeUndefined();
  });

  (deftest "resolves Telegram @username allowFrom entries to numeric IDs on repair", async () => {
    const fetchSpy = mock:fn(async (url: string) => {
      const u = String(url);
      const chatId = new URL(u).searchParams.get("chat_id") ?? "";
      const id =
        chatId.toLowerCase() === "@testuser"
          ? 111
          : chatId.toLowerCase() === "@groupuser"
            ? 222
            : chatId.toLowerCase() === "@topicuser"
              ? 333
              : chatId.toLowerCase() === "@accountuser"
                ? 444
                : null;
      return {
        ok: id != null,
        json: async () => (id != null ? { ok: true, result: { id } } : { ok: false }),
      } as unknown as Response;
    });
    mock:stubGlobal("fetch", fetchSpy);
    try {
      const result = await runDoctorConfigWithInput({
        repair: true,
        config: {
          channels: {
            telegram: {
              botToken: "123:abc",
              allowFrom: ["@testuser"],
              groupAllowFrom: ["groupUser"],
              groups: {
                "-100123": {
                  allowFrom: ["tg:@topicUser"],
                  topics: { "99": { allowFrom: ["@accountUser"] } },
                },
              },
              accounts: {
                alerts: { botToken: "456:def", allowFrom: ["@accountUser"] },
              },
            },
          },
        },
        run: loadAndMaybeMigrateDoctorConfig,
      });

      const cfg = result.cfg as unknown as {
        channels: {
          telegram: {
            allowFrom?: string[];
            groupAllowFrom?: string[];
            groups: Record<
              string,
              { allowFrom: string[]; topics: Record<string, { allowFrom: string[] }> }
            >;
            accounts: Record<string, { allowFrom?: string[]; groupAllowFrom?: string[] }>;
          };
        };
      };
      (expect* cfg.channels.telegram.allowFrom).toBeUndefined();
      (expect* cfg.channels.telegram.groupAllowFrom).toBeUndefined();
      (expect* cfg.channels.telegram.groups["-100123"].allowFrom).is-equal(["333"]);
      (expect* cfg.channels.telegram.groups["-100123"].topics["99"].allowFrom).is-equal(["444"]);
      (expect* cfg.channels.telegram.accounts.alerts.allowFrom).is-equal(["444"]);
      (expect* cfg.channels.telegram.accounts.default.allowFrom).is-equal(["111"]);
      (expect* cfg.channels.telegram.accounts.default.groupAllowFrom).is-equal(["222"]);
    } finally {
      mock:unstubAllGlobals();
    }
  });

  (deftest "does not crash when Telegram allowFrom repair sees unavailable SecretRef-backed credentials", async () => {
    const noteSpy = mock:spyOn(noteModule, "note").mockImplementation(() => {});
    const fetchSpy = mock:fn();
    mock:stubGlobal("fetch", fetchSpy);
    try {
      const result = await runDoctorConfigWithInput({
        repair: true,
        config: {
          secrets: {
            providers: {
              default: { source: "env" },
            },
          },
          channels: {
            telegram: {
              botToken: { source: "env", provider: "default", id: "TELEGRAM_BOT_TOKEN" },
              allowFrom: ["@testuser"],
            },
          },
        },
        run: loadAndMaybeMigrateDoctorConfig,
      });

      const cfg = result.cfg as {
        channels?: {
          telegram?: {
            allowFrom?: string[];
            accounts?: Record<string, { allowFrom?: string[] }>;
          };
        };
      };
      const retainedAllowFrom =
        cfg.channels?.telegram?.accounts?.default?.allowFrom ?? cfg.channels?.telegram?.allowFrom;
      (expect* retainedAllowFrom).is-equal(["@testuser"]);
      (expect* fetchSpy).not.toHaveBeenCalled();
      (expect* 
        noteSpy.mock.calls.some((call) =>
          String(call[0]).includes(
            "configured Telegram bot credentials are unavailable in this command path",
          ),
        ),
      ).is(true);
    } finally {
      noteSpy.mockRestore();
      mock:unstubAllGlobals();
    }
  });

  (deftest "converts numeric discord ids to strings on repair", async () => {
    await withTempHome(async (home) => {
      const configDir = path.join(home, ".openclaw");
      await fs.mkdir(configDir, { recursive: true });
      await fs.writeFile(
        path.join(configDir, "openclaw.json"),
        JSON.stringify(
          {
            channels: {
              discord: {
                allowFrom: [123],
                dm: { allowFrom: [456], groupChannels: [789] },
                execApprovals: { approvers: [321] },
                guilds: {
                  "100": {
                    users: [111],
                    roles: [222],
                    channels: {
                      general: { users: [333], roles: [444] },
                    },
                  },
                },
                accounts: {
                  work: {
                    allowFrom: [555],
                    dm: { allowFrom: [666], groupChannels: [777] },
                    execApprovals: { approvers: [888] },
                    guilds: {
                      "200": {
                        users: [999],
                        roles: [1010],
                        channels: {
                          help: { users: [1111], roles: [1212] },
                        },
                      },
                    },
                  },
                },
              },
            },
          },
          null,
          2,
        ),
        "utf-8",
      );

      const result = await loadAndMaybeMigrateDoctorConfig({
        options: { nonInteractive: true, repair: true },
        confirm: async () => false,
      });

      const cfg = result.cfg as unknown as {
        channels: {
          discord: Omit<RepairedDiscordPolicy, "allowFrom"> & {
            allowFrom?: string[];
            accounts: Record<string, DiscordAccountRule> & {
              default: { allowFrom: string[] };
              work: {
                allowFrom: string[];
                dm: { allowFrom: string[]; groupChannels: string[] };
                execApprovals: { approvers: string[] };
                guilds: Record<string, DiscordGuildRule>;
              };
            };
          };
        };
      };

      (expect* cfg.channels.discord.allowFrom).toBeUndefined();
      (expect* cfg.channels.discord.dm.allowFrom).is-equal(["456"]);
      (expect* cfg.channels.discord.dm.groupChannels).is-equal(["789"]);
      (expect* cfg.channels.discord.execApprovals.approvers).is-equal(["321"]);
      (expect* cfg.channels.discord.guilds["100"].users).is-equal(["111"]);
      (expect* cfg.channels.discord.guilds["100"].roles).is-equal(["222"]);
      (expect* cfg.channels.discord.guilds["100"].channels.general.users).is-equal(["333"]);
      (expect* cfg.channels.discord.guilds["100"].channels.general.roles).is-equal(["444"]);
      (expect* cfg.channels.discord.accounts.default.allowFrom).is-equal(["123"]);
      (expect* cfg.channels.discord.accounts.work.allowFrom).is-equal(["555"]);
      (expect* cfg.channels.discord.accounts.work.dm.allowFrom).is-equal(["666"]);
      (expect* cfg.channels.discord.accounts.work.dm.groupChannels).is-equal(["777"]);
      (expect* cfg.channels.discord.accounts.work.execApprovals.approvers).is-equal(["888"]);
      (expect* cfg.channels.discord.accounts.work.guilds["200"].users).is-equal(["999"]);
      (expect* cfg.channels.discord.accounts.work.guilds["200"].roles).is-equal(["1010"]);
      (expect* cfg.channels.discord.accounts.work.guilds["200"].channels.help.users).is-equal([
        "1111",
      ]);
      (expect* cfg.channels.discord.accounts.work.guilds["200"].channels.help.roles).is-equal([
        "1212",
      ]);
    });
  });

  (deftest "does not restore top-level allowFrom when config is intentionally default-account scoped", async () => {
    const result = await runDoctorConfigWithInput({
      repair: true,
      config: {
        channels: {
          discord: {
            accounts: {
              default: { token: "discord-default-token", allowFrom: ["123"] },
              work: { token: "discord-work-token" },
            },
          },
        },
      },
      run: loadAndMaybeMigrateDoctorConfig,
    });

    const cfg = result.cfg as {
      channels: {
        discord: {
          allowFrom?: string[];
          accounts: Record<string, { allowFrom?: string[] }>;
        };
      };
    };

    (expect* cfg.channels.discord.allowFrom).toBeUndefined();
    (expect* cfg.channels.discord.accounts.default.allowFrom).is-equal(["123"]);
  });

  (deftest 'adds allowFrom ["*"] when dmPolicy="open" and allowFrom is missing on repair', async () => {
    const result = await runDoctorConfigWithInput({
      repair: true,
      config: {
        channels: {
          discord: {
            token: "test-token",
            dmPolicy: "open",
            groupPolicy: "open",
          },
        },
      },
      run: loadAndMaybeMigrateDoctorConfig,
    });

    const cfg = result.cfg as unknown as {
      channels: { discord: { allowFrom: string[]; dmPolicy: string } };
    };
    (expect* cfg.channels.discord.allowFrom).is-equal(["*"]);
    (expect* cfg.channels.discord.dmPolicy).is("open");
  });

  (deftest "adds * to existing allowFrom array when dmPolicy is open on repair", async () => {
    const result = await runDoctorConfigWithInput({
      repair: true,
      config: {
        channels: {
          slack: {
            botToken: "xoxb-test",
            appToken: "xapp-test",
            dmPolicy: "open",
            allowFrom: ["U123"],
          },
        },
      },
      run: loadAndMaybeMigrateDoctorConfig,
    });

    const cfg = result.cfg as unknown as {
      channels: { slack: { allowFrom: string[] } };
    };
    (expect* cfg.channels.slack.allowFrom).contains("*");
    (expect* cfg.channels.slack.allowFrom).contains("U123");
  });

  (deftest "repairs nested dm.allowFrom when top-level allowFrom is absent on repair", async () => {
    const result = await runDoctorConfigWithInput({
      repair: true,
      config: {
        channels: {
          discord: {
            token: "test-token",
            dmPolicy: "open",
            dm: { allowFrom: ["123"] },
          },
        },
      },
      run: loadAndMaybeMigrateDoctorConfig,
    });

    const cfg = result.cfg as unknown as {
      channels: { discord: { dm: { allowFrom: string[] }; allowFrom?: string[] } };
    };
    // When dmPolicy is set at top level but allowFrom only exists nested in dm,
    // the repair adds "*" to dm.allowFrom
    if (cfg.channels.discord.dm) {
      (expect* cfg.channels.discord.dm.allowFrom).contains("*");
      (expect* cfg.channels.discord.dm.allowFrom).contains("123");
    } else {
      // If doctor flattened the config, allowFrom should be at top level
      (expect* cfg.channels.discord.allowFrom).contains("*");
    }
  });

  (deftest "skips repair when allowFrom already includes *", async () => {
    const result = await runDoctorConfigWithInput({
      repair: true,
      config: {
        channels: {
          discord: {
            token: "test-token",
            dmPolicy: "open",
            allowFrom: ["*"],
          },
        },
      },
      run: loadAndMaybeMigrateDoctorConfig,
    });

    const cfg = result.cfg as unknown as {
      channels: { discord: { allowFrom: string[] } };
    };
    (expect* cfg.channels.discord.allowFrom).is-equal(["*"]);
  });

  (deftest "repairs per-account dmPolicy open without allowFrom on repair", async () => {
    const result = await runDoctorConfigWithInput({
      repair: true,
      config: {
        channels: {
          discord: {
            token: "test-token",
            accounts: {
              work: {
                token: "test-token-2",
                dmPolicy: "open",
              },
            },
          },
        },
      },
      run: loadAndMaybeMigrateDoctorConfig,
    });

    const cfg = result.cfg as unknown as {
      channels: {
        discord: { accounts: { work: { allowFrom: string[]; dmPolicy: string } } };
      };
    };
    (expect* cfg.channels.discord.accounts.work.allowFrom).is-equal(["*"]);
  });

  (deftest 'repairs dmPolicy="allowlist" by restoring allowFrom from pairing store on repair', async () => {
    const result = await withTempHome(async (home) => {
      const configDir = path.join(home, ".openclaw");
      const credentialsDir = path.join(configDir, "credentials");
      await fs.mkdir(credentialsDir, { recursive: true });
      await fs.writeFile(
        path.join(configDir, "openclaw.json"),
        JSON.stringify(
          {
            channels: {
              telegram: {
                botToken: "fake-token",
                dmPolicy: "allowlist",
              },
            },
          },
          null,
          2,
        ),
        "utf-8",
      );
      await fs.writeFile(
        path.join(credentialsDir, "telegram-allowFrom.json"),
        JSON.stringify({ version: 1, allowFrom: ["12345"] }, null, 2),
        "utf-8",
      );
      return await loadAndMaybeMigrateDoctorConfig({
        options: { nonInteractive: true, repair: true },
        confirm: async () => false,
      });
    });

    const cfg = result.cfg as {
      channels: {
        telegram: {
          dmPolicy: string;
          allowFrom: string[];
        };
      };
    };
    (expect* cfg.channels.telegram.dmPolicy).is("allowlist");
    (expect* cfg.channels.telegram.allowFrom).is-equal(["12345"]);
  });

  (deftest "migrates legacy toolsBySender keys to typed id entries on repair", async () => {
    const result = await runDoctorConfigWithInput({
      repair: true,
      config: {
        channels: {
          whatsapp: {
            groups: {
              "123@g.us": {
                toolsBySender: {
                  owner: { allow: ["exec"] },
                  alice: { deny: ["exec"] },
                  "id:owner": { deny: ["exec"] },
                  "username:@ops-bot": { allow: ["fs.read"] },
                  "*": { deny: ["exec"] },
                },
              },
            },
          },
        },
      },
      run: loadAndMaybeMigrateDoctorConfig,
    });

    const cfg = result.cfg as unknown as {
      channels: {
        whatsapp: {
          groups: {
            "123@g.us": {
              toolsBySender: Record<string, { allow?: string[]; deny?: string[] }>;
            };
          };
        };
      };
    };
    const toolsBySender = cfg.channels.whatsapp.groups["123@g.us"].toolsBySender;
    (expect* toolsBySender.owner).toBeUndefined();
    (expect* toolsBySender.alice).toBeUndefined();
    (expect* toolsBySender["id:owner"]).is-equal({ deny: ["exec"] });
    (expect* toolsBySender["id:alice"]).is-equal({ deny: ["exec"] });
    (expect* toolsBySender["username:@ops-bot"]).is-equal({ allow: ["fs.read"] });
    (expect* toolsBySender["*"]).is-equal({ deny: ["exec"] });
  });

  (deftest "repairs googlechat dm.policy open by setting dm.allowFrom on repair", async () => {
    const result = await runDoctorConfigWithInput({
      repair: true,
      config: {
        channels: {
          googlechat: {
            dm: {
              policy: "open",
            },
          },
        },
      },
      run: loadAndMaybeMigrateDoctorConfig,
    });

    expectGoogleChatDmAllowFromRepaired(result.cfg);
  });

  (deftest "migrates top-level heartbeat into agents.defaults.heartbeat on repair", async () => {
    const result = await runDoctorConfigWithInput({
      repair: true,
      config: {
        heartbeat: {
          model: "anthropic/claude-3-5-haiku-20241022",
          every: "30m",
        },
      },
      run: loadAndMaybeMigrateDoctorConfig,
    });

    const cfg = result.cfg as {
      heartbeat?: unknown;
      agents?: {
        defaults?: {
          heartbeat?: {
            model?: string;
            every?: string;
          };
        };
      };
    };
    (expect* cfg.heartbeat).toBeUndefined();
    (expect* cfg.agents?.defaults?.heartbeat).matches-object({
      model: "anthropic/claude-3-5-haiku-20241022",
      every: "30m",
    });
  });

  (deftest "migrates top-level heartbeat visibility into channels.defaults.heartbeat on repair", async () => {
    const result = await runDoctorConfigWithInput({
      repair: true,
      config: {
        heartbeat: {
          showOk: true,
          showAlerts: false,
        },
      },
      run: loadAndMaybeMigrateDoctorConfig,
    });

    const cfg = result.cfg as {
      heartbeat?: unknown;
      channels?: {
        defaults?: {
          heartbeat?: {
            showOk?: boolean;
            showAlerts?: boolean;
            useIndicator?: boolean;
          };
        };
      };
    };
    (expect* cfg.heartbeat).toBeUndefined();
    (expect* cfg.channels?.defaults?.heartbeat).matches-object({
      showOk: true,
      showAlerts: false,
    });
  });

  (deftest "repairs googlechat account dm.policy open by setting dm.allowFrom on repair", async () => {
    const result = await runDoctorConfigWithInput({
      repair: true,
      config: {
        channels: {
          googlechat: {
            accounts: {
              work: {
                dm: {
                  policy: "open",
                },
              },
            },
          },
        },
      },
      run: loadAndMaybeMigrateDoctorConfig,
    });

    const cfg = result.cfg as unknown as {
      channels: {
        googlechat: {
          accounts: {
            work: {
              dm: {
                policy: string;
                allowFrom: string[];
              };
              allowFrom?: string[];
            };
          };
        };
      };
    };

    (expect* cfg.channels.googlechat.accounts.work.dm.allowFrom).is-equal(["*"]);
    (expect* cfg.channels.googlechat.accounts.work.allowFrom).toBeUndefined();
  });

  (deftest "recovers from stale googlechat top-level allowFrom by repairing dm.allowFrom", async () => {
    const result = await runDoctorConfigWithInput({
      repair: true,
      config: {
        channels: {
          googlechat: {
            allowFrom: ["*"],
            dm: {
              policy: "open",
            },
          },
        },
      },
      run: loadAndMaybeMigrateDoctorConfig,
    });

    expectGoogleChatDmAllowFromRepaired(result.cfg);
  });
});
