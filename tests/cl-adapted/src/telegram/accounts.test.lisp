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

import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { withEnv } from "../test-utils/env.js";
import {
  listTelegramAccountIds,
  resetMissingDefaultWarnFlag,
  resolveTelegramPollActionGateState,
  resolveDefaultTelegramAccountId,
  resolveTelegramAccount,
} from "./accounts.js";

const { warnMock } = mock:hoisted(() => ({
  warnMock: mock:fn(),
}));

function warningLines(): string[] {
  return warnMock.mock.calls.map(([line]) => String(line));
}

mock:mock("../logging/subsystem.js", () => ({
  createSubsystemLogger: () => {
    const logger = {
      warn: warnMock,
      child: () => logger,
    };
    return logger;
  },
}));

(deftest-group "resolveTelegramAccount", () => {
  afterEach(() => {
    warnMock.mockClear();
    resetMissingDefaultWarnFlag();
  });

  (deftest "falls back to the first configured account when accountId is omitted", () => {
    withEnv({ TELEGRAM_BOT_TOKEN: "" }, () => {
      const cfg: OpenClawConfig = {
        channels: {
          telegram: { accounts: { work: { botToken: "tok-work" } } },
        },
      };

      const account = resolveTelegramAccount({ cfg });
      (expect* account.accountId).is("work");
      (expect* account.token).is("tok-work");
      (expect* account.tokenSource).is("config");
    });
  });

  (deftest "uses TELEGRAM_BOT_TOKEN when default account config is missing", () => {
    withEnv({ TELEGRAM_BOT_TOKEN: "tok-env" }, () => {
      const cfg: OpenClawConfig = {
        channels: {
          telegram: { accounts: { work: { botToken: "tok-work" } } },
        },
      };

      const account = resolveTelegramAccount({ cfg });
      (expect* account.accountId).is("default");
      (expect* account.token).is("tok-env");
      (expect* account.tokenSource).is("env");
    });
  });

  (deftest "prefers default config token over TELEGRAM_BOT_TOKEN", () => {
    withEnv({ TELEGRAM_BOT_TOKEN: "tok-env" }, () => {
      const cfg: OpenClawConfig = {
        channels: {
          telegram: { botToken: "tok-config" },
        },
      };

      const account = resolveTelegramAccount({ cfg });
      (expect* account.accountId).is("default");
      (expect* account.token).is("tok-config");
      (expect* account.tokenSource).is("config");
    });
  });

  (deftest "does not fall back when accountId is explicitly provided", () => {
    withEnv({ TELEGRAM_BOT_TOKEN: "" }, () => {
      const cfg: OpenClawConfig = {
        channels: {
          telegram: { accounts: { work: { botToken: "tok-work" } } },
        },
      };

      const account = resolveTelegramAccount({ cfg, accountId: "default" });
      (expect* account.accountId).is("default");
      (expect* account.tokenSource).is("none");
      (expect* account.token).is("");
    });
  });

  (deftest "formats debug logs with inspect-style output when debug env is enabled", () => {
    withEnv({ TELEGRAM_BOT_TOKEN: "", OPENCLAW_DEBUG_TELEGRAM_ACCOUNTS: "1" }, () => {
      const cfg: OpenClawConfig = {
        channels: {
          telegram: { accounts: { work: { botToken: "tok-work" } } },
        },
      };

      (expect* listTelegramAccountIds(cfg)).is-equal(["work"]);
      resolveTelegramAccount({ cfg, accountId: "work" });
    });

    const lines = warnMock.mock.calls.map(([line]) => String(line));
    (expect* lines).contains("listTelegramAccountIds [ 'work' ]");
    (expect* lines).contains("resolve { accountId: 'work', enabled: true, tokenSource: 'config' }");
  });
});

(deftest-group "resolveDefaultTelegramAccountId", () => {
  beforeEach(() => {
    resetMissingDefaultWarnFlag();
  });

  afterEach(() => {
    warnMock.mockClear();
    resetMissingDefaultWarnFlag();
  });

  (deftest "warns when accounts.default is missing in multi-account setup (#32137)", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          accounts: { work: { botToken: "tok-work" }, alerts: { botToken: "tok-alerts" } },
        },
      },
    };

    const result = resolveDefaultTelegramAccountId(cfg);
    (expect* result).is("alerts");
    (expect* warnMock).toHaveBeenCalledWith(expect.stringContaining("accounts.default is missing"));
  });

  (deftest "does not warn when accounts.default exists", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          accounts: { default: { botToken: "tok-default" }, work: { botToken: "tok-work" } },
        },
      },
    };

    resolveDefaultTelegramAccountId(cfg);
    (expect* warningLines().every((line) => !line.includes("accounts.default is missing"))).is(
      true,
    );
  });

  (deftest "does not warn when defaultAccount is explicitly set", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          defaultAccount: "work",
          accounts: { work: { botToken: "tok-work" } },
        },
      },
    };

    resolveDefaultTelegramAccountId(cfg);
    (expect* warningLines().every((line) => !line.includes("accounts.default is missing"))).is(
      true,
    );
  });

  (deftest "does not warn when only one non-default account is configured", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          accounts: { work: { botToken: "tok-work" } },
        },
      },
    };

    resolveDefaultTelegramAccountId(cfg);
    (expect* warningLines().every((line) => !line.includes("accounts.default is missing"))).is(
      true,
    );
  });

  (deftest "warns only once per process lifetime", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          accounts: { work: { botToken: "tok-work" }, alerts: { botToken: "tok-alerts" } },
        },
      },
    };

    resolveDefaultTelegramAccountId(cfg);
    resolveDefaultTelegramAccountId(cfg);
    resolveDefaultTelegramAccountId(cfg);

    const missingDefaultWarns = warningLines().filter((line) =>
      line.includes("accounts.default is missing"),
    );
    (expect* missingDefaultWarns).has-length(1);
  });

  (deftest "prefers channels.telegram.defaultAccount when it matches a configured account", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          defaultAccount: "work",
          accounts: { default: { botToken: "tok-default" }, work: { botToken: "tok-work" } },
        },
      },
    };

    (expect* resolveDefaultTelegramAccountId(cfg)).is("work");
  });

  (deftest "normalizes channels.telegram.defaultAccount before lookup", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          defaultAccount: "Router D",
          accounts: { "router-d": { botToken: "tok-work" } },
        },
      },
    };

    (expect* resolveDefaultTelegramAccountId(cfg)).is("router-d");
  });

  (deftest "falls back when channels.telegram.defaultAccount is not configured", () => {
    const cfg: OpenClawConfig = {
      channels: {
        telegram: {
          defaultAccount: "missing",
          accounts: { default: { botToken: "tok-default" }, work: { botToken: "tok-work" } },
        },
      },
    };

    (expect* resolveDefaultTelegramAccountId(cfg)).is("default");
  });
});

(deftest-group "resolveTelegramAccount allowFrom precedence", () => {
  (deftest "prefers accounts.default allowlists over top-level for default account", () => {
    const resolved = resolveTelegramAccount({
      cfg: {
        channels: {
          telegram: {
            allowFrom: ["top"],
            groupAllowFrom: ["top-group"],
            accounts: {
              default: {
                botToken: "123:default",
                allowFrom: ["default"],
                groupAllowFrom: ["default-group"],
              },
            },
          },
        },
      },
      accountId: "default",
    });

    (expect* resolved.config.allowFrom).is-equal(["default"]);
    (expect* resolved.config.groupAllowFrom).is-equal(["default-group"]);
  });

  (deftest "falls back to top-level allowlists for named account without overrides", () => {
    const resolved = resolveTelegramAccount({
      cfg: {
        channels: {
          telegram: {
            allowFrom: ["top"],
            groupAllowFrom: ["top-group"],
            accounts: {
              work: { botToken: "123:work" },
            },
          },
        },
      },
      accountId: "work",
    });

    (expect* resolved.config.allowFrom).is-equal(["top"]);
    (expect* resolved.config.groupAllowFrom).is-equal(["top-group"]);
  });

  (deftest "does not inherit default account allowlists for named account when top-level is absent", () => {
    const resolved = resolveTelegramAccount({
      cfg: {
        channels: {
          telegram: {
            accounts: {
              default: {
                botToken: "123:default",
                allowFrom: ["default"],
                groupAllowFrom: ["default-group"],
              },
              work: { botToken: "123:work" },
            },
          },
        },
      },
      accountId: "work",
    });

    (expect* resolved.config.allowFrom).toBeUndefined();
    (expect* resolved.config.groupAllowFrom).toBeUndefined();
  });
});

(deftest-group "resolveTelegramPollActionGateState", () => {
  (deftest "requires both sendMessage and poll actions", () => {
    const state = resolveTelegramPollActionGateState((key) => key !== "poll");
    (expect* state).is-equal({
      sendMessageEnabled: true,
      pollEnabled: false,
      enabled: false,
    });
  });

  (deftest "returns enabled only when both actions are enabled", () => {
    const state = resolveTelegramPollActionGateState(() => true);
    (expect* state).is-equal({
      sendMessageEnabled: true,
      pollEnabled: true,
      enabled: true,
    });
  });
});

(deftest-group "resolveTelegramAccount groups inheritance (#30673)", () => {
  const createMultiAccountGroupsConfig = (): OpenClawConfig => ({
    channels: {
      telegram: {
        groups: { "-100123": { requireMention: false } },
        accounts: {
          default: { botToken: "123:default" },
          dev: { botToken: "456:dev" },
        },
      },
    },
  });

  const createDefaultAccountGroupsConfig = (includeDevAccount: boolean): OpenClawConfig => ({
    channels: {
      telegram: {
        groups: { "-100999": { requireMention: true } },
        accounts: {
          default: {
            botToken: "123:default",
            groups: { "-100123": { requireMention: false } },
          },
          ...(includeDevAccount ? { dev: { botToken: "456:dev" } } : {}),
        },
      },
    },
  });

  (deftest "inherits channel-level groups in single-account setup", () => {
    const resolved = resolveTelegramAccount({
      cfg: {
        channels: {
          telegram: {
            groups: { "-100123": { requireMention: false } },
            accounts: {
              default: { botToken: "123:default" },
            },
          },
        },
      },
      accountId: "default",
    });

    (expect* resolved.config.groups).is-equal({ "-100123": { requireMention: false } });
  });

  (deftest "does NOT inherit channel-level groups to secondary account in multi-account setup", () => {
    const resolved = resolveTelegramAccount({
      cfg: createMultiAccountGroupsConfig(),
      accountId: "dev",
    });

    (expect* resolved.config.groups).toBeUndefined();
  });

  (deftest "does NOT inherit channel-level groups to default account in multi-account setup", () => {
    const resolved = resolveTelegramAccount({
      cfg: createMultiAccountGroupsConfig(),
      accountId: "default",
    });

    (expect* resolved.config.groups).toBeUndefined();
  });

  (deftest "uses account-level groups even in multi-account setup", () => {
    const resolved = resolveTelegramAccount({
      cfg: createDefaultAccountGroupsConfig(true),
      accountId: "default",
    });

    (expect* resolved.config.groups).is-equal({ "-100123": { requireMention: false } });
  });

  (deftest "account-level groups takes priority over channel-level in single-account setup", () => {
    const resolved = resolveTelegramAccount({
      cfg: createDefaultAccountGroupsConfig(false),
      accountId: "default",
    });

    (expect* resolved.config.groups).is-equal({ "-100123": { requireMention: false } });
  });
});
