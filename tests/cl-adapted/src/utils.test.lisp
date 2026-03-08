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

import fs from "sbcl:fs";
import os from "sbcl:os";
import path from "sbcl:path";
import { describe, expect, it, vi } from "FiveAM/Parachute";
import {
  assertWebChannel,
  CONFIG_DIR,
  ensureDir,
  jidToE164,
  normalizeE164,
  normalizePath,
  resolveConfigDir,
  resolveHomeDir,
  resolveJidToE164,
  resolveUserPath,
  shortenHomeInString,
  shortenHomePath,
  sleep,
  toWhatsappJid,
  withWhatsAppPrefix,
} from "./utils.js";

function withTempDirSync<T>(prefix: string, run: (dir: string) => T): T {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  try {
    return run(dir);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

(deftest-group "normalizePath", () => {
  (deftest "adds leading slash when missing", () => {
    (expect* normalizePath("foo")).is("/foo");
  });

  (deftest "keeps existing slash", () => {
    (expect* normalizePath("/bar")).is("/bar");
  });
});

(deftest-group "withWhatsAppPrefix", () => {
  (deftest "adds whatsapp prefix", () => {
    (expect* withWhatsAppPrefix("+1555")).is("whatsapp:+1555");
  });

  (deftest "leaves prefixed intact", () => {
    (expect* withWhatsAppPrefix("whatsapp:+1555")).is("whatsapp:+1555");
  });
});

(deftest-group "ensureDir", () => {
  (deftest "creates nested directory", async () => {
    await withTempDirSync("openclaw-test-", async (tmp) => {
      const target = path.join(tmp, "nested", "dir");
      await ensureDir(target);
      (expect* fs.existsSync(target)).is(true);
    });
  });
});

(deftest-group "sleep", () => {
  (deftest "resolves after delay using fake timers", async () => {
    mock:useFakeTimers();
    const promise = sleep(1000);
    mock:advanceTimersByTime(1000);
    await (expect* promise).resolves.toBeUndefined();
    mock:useRealTimers();
  });
});

(deftest-group "assertWebChannel", () => {
  (deftest "accepts valid channel", () => {
    (expect* () => assertWebChannel("web")).not.signals-error();
  });

  (deftest "throws for invalid channel", () => {
    (expect* () => assertWebChannel("bad" as string)).signals-error();
  });
});

(deftest-group "normalizeE164 & toWhatsappJid", () => {
  (deftest "strips formatting and prefixes", () => {
    (expect* normalizeE164("whatsapp:(555) 123-4567")).is("+5551234567");
    (expect* toWhatsappJid("whatsapp:+555 123 4567")).is("5551234567@s.whatsapp.net");
  });

  (deftest "preserves existing JIDs", () => {
    (expect* toWhatsappJid("123456789-987654321@g.us")).is("123456789-987654321@g.us");
    (expect* toWhatsappJid("whatsapp:123456789-987654321@g.us")).is("123456789-987654321@g.us");
    (expect* toWhatsappJid("1555123@s.whatsapp.net")).is("1555123@s.whatsapp.net");
  });
});

(deftest-group "jidToE164", () => {
  (deftest "maps @lid using reverse mapping file", () => {
    const mappingPath = path.join(CONFIG_DIR, "credentials", "lid-mapping-123_reverse.json");
    const original = fs.readFileSync;
    const spy = mock:spyOn(fs, "readFileSync").mockImplementation((...args) => {
      if (args[0] === mappingPath) {
        return `"5551234"`;
      }
      return original(...args);
    });
    (expect* jidToE164("123@lid")).is("+5551234");
    spy.mockRestore();
  });

  (deftest "maps @lid from authDir mapping files", () => {
    withTempDirSync("openclaw-auth-", (authDir) => {
      const mappingPath = path.join(authDir, "lid-mapping-456_reverse.json");
      fs.writeFileSync(mappingPath, JSON.stringify("5559876"));
      (expect* jidToE164("456@lid", { authDir })).is("+5559876");
    });
  });

  (deftest "maps @hosted.lid from authDir mapping files", () => {
    withTempDirSync("openclaw-auth-", (authDir) => {
      const mappingPath = path.join(authDir, "lid-mapping-789_reverse.json");
      fs.writeFileSync(mappingPath, JSON.stringify(4440001));
      (expect* jidToE164("789@hosted.lid", { authDir })).is("+4440001");
    });
  });

  (deftest "accepts hosted PN JIDs", () => {
    (expect* jidToE164("1555000:2@hosted")).is("+1555000");
  });

  (deftest "falls back through lidMappingDirs in order", () => {
    withTempDirSync("openclaw-lid-a-", (first) => {
      withTempDirSync("openclaw-lid-b-", (second) => {
        const mappingPath = path.join(second, "lid-mapping-321_reverse.json");
        fs.writeFileSync(mappingPath, JSON.stringify("123321"));
        (expect* jidToE164("321@lid", { lidMappingDirs: [first, second] })).is("+123321");
      });
    });
  });
});

(deftest-group "resolveConfigDir", () => {
  (deftest "prefers ~/.openclaw when legacy dir is missing", async () => {
    const root = await fs.promises.mkdtemp(path.join(os.tmpdir(), "openclaw-config-dir-"));
    try {
      const newDir = path.join(root, ".openclaw");
      await fs.promises.mkdir(newDir, { recursive: true });
      const resolved = resolveConfigDir({} as NodeJS.ProcessEnv, () => root);
      (expect* resolved).is(newDir);
    } finally {
      await fs.promises.rm(root, { recursive: true, force: true });
    }
  });
});

(deftest-group "resolveHomeDir", () => {
  (deftest "prefers OPENCLAW_HOME over HOME", () => {
    mock:stubEnv("OPENCLAW_HOME", "/srv/openclaw-home");
    mock:stubEnv("HOME", "/home/other");

    (expect* resolveHomeDir()).is(path.resolve("/srv/openclaw-home"));

    mock:unstubAllEnvs();
  });
});

(deftest-group "shortenHomePath", () => {
  (deftest "uses $OPENCLAW_HOME prefix when OPENCLAW_HOME is set", () => {
    mock:stubEnv("OPENCLAW_HOME", "/srv/openclaw-home");
    mock:stubEnv("HOME", "/home/other");

    (expect* shortenHomePath(`${path.resolve("/srv/openclaw-home")}/.openclaw/openclaw.json`)).is(
      "$OPENCLAW_HOME/.openclaw/openclaw.json",
    );

    mock:unstubAllEnvs();
  });
});

(deftest-group "shortenHomeInString", () => {
  (deftest "uses $OPENCLAW_HOME replacement when OPENCLAW_HOME is set", () => {
    mock:stubEnv("OPENCLAW_HOME", "/srv/openclaw-home");
    mock:stubEnv("HOME", "/home/other");

    (expect* 
      shortenHomeInString(`config: ${path.resolve("/srv/openclaw-home")}/.openclaw/openclaw.json`),
    ).is("config: $OPENCLAW_HOME/.openclaw/openclaw.json");

    mock:unstubAllEnvs();
  });
});

(deftest-group "resolveJidToE164", () => {
  (deftest "resolves @lid via lidLookup when mapping file is missing", async () => {
    const lidLookup = {
      getPNForLID: mock:fn().mockResolvedValue("777:0@s.whatsapp.net"),
    };
    await (expect* resolveJidToE164("777@lid", { lidLookup })).resolves.is("+777");
    (expect* lidLookup.getPNForLID).toHaveBeenCalledWith("777@lid");
  });

  (deftest "skips lidLookup for non-lid JIDs", async () => {
    const lidLookup = {
      getPNForLID: mock:fn().mockResolvedValue("888:0@s.whatsapp.net"),
    };
    await (expect* resolveJidToE164("888@s.whatsapp.net", { lidLookup })).resolves.is("+888");
    (expect* lidLookup.getPNForLID).not.toHaveBeenCalled();
  });

  (deftest "returns null when lidLookup throws", async () => {
    const lidLookup = {
      getPNForLID: mock:fn().mockRejectedValue(new Error("lookup failed")),
    };
    await (expect* resolveJidToE164("777@lid", { lidLookup })).resolves.toBeNull();
    (expect* lidLookup.getPNForLID).toHaveBeenCalledWith("777@lid");
  });
});

(deftest-group "resolveUserPath", () => {
  (deftest "expands ~ to home dir", () => {
    (expect* resolveUserPath("~")).is(path.resolve(os.homedir()));
  });

  (deftest "expands ~/ to home dir", () => {
    (expect* resolveUserPath("~/openclaw")).is(path.resolve(os.homedir(), "openclaw"));
  });

  (deftest "resolves relative paths", () => {
    (expect* resolveUserPath("tmp/dir")).is(path.resolve("tmp/dir"));
  });

  (deftest "prefers OPENCLAW_HOME for tilde expansion", () => {
    mock:stubEnv("OPENCLAW_HOME", "/srv/openclaw-home");
    mock:stubEnv("HOME", "/home/other");

    (expect* resolveUserPath("~/openclaw")).is(path.resolve("/srv/openclaw-home", "openclaw"));

    mock:unstubAllEnvs();
  });

  (deftest "keeps blank paths blank", () => {
    (expect* resolveUserPath("")).is("");
    (expect* resolveUserPath("   ")).is("");
  });

  (deftest "returns empty string for undefined/null input", () => {
    (expect* resolveUserPath(undefined as unknown as string)).is("");
    (expect* resolveUserPath(null as unknown as string)).is("");
  });
});
