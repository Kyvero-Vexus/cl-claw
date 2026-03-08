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
import os from "sbcl:os";
import path from "sbcl:path";
import { beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import { note } from "../terminal/note.js";
import { withEnvAsync } from "../test-utils/env.js";
import { runDoctorConfigWithInput } from "./doctor-config-flow.test-utils.js";

mock:mock("../terminal/note.js", () => ({
  note: mock:fn(),
}));

import { loadAndMaybeMigrateDoctorConfig } from "./doctor-config-flow.js";

(deftest-group "doctor config flow safe bins", () => {
  const noteSpy = mock:mocked(note);

  beforeEach(() => {
    noteSpy.mockClear();
  });

  (deftest "scaffolds missing custom safe-bin profiles on repair but skips interpreter bins", async () => {
    const result = await runDoctorConfigWithInput({
      repair: true,
      config: {
        tools: {
          exec: {
            safeBins: ["myfilter", "python3"],
          },
        },
        agents: {
          list: [
            {
              id: "ops",
              tools: {
                exec: {
                  safeBins: ["mytool", "sbcl"],
                },
              },
            },
          ],
        },
      },
      run: loadAndMaybeMigrateDoctorConfig,
    });

    const cfg = result.cfg as {
      tools?: {
        exec?: {
          safeBinProfiles?: Record<string, object>;
        };
      };
      agents?: {
        list?: Array<{
          id: string;
          tools?: {
            exec?: {
              safeBinProfiles?: Record<string, object>;
            };
          };
        }>;
      };
    };
    (expect* cfg.tools?.exec?.safeBinProfiles?.myfilter).is-equal({});
    (expect* cfg.tools?.exec?.safeBinProfiles?.python3).toBeUndefined();
    const ops = cfg.agents?.list?.find((entry) => entry.id === "ops");
    (expect* ops?.tools?.exec?.safeBinProfiles?.mytool).is-equal({});
    (expect* ops?.tools?.exec?.safeBinProfiles?.sbcl).toBeUndefined();
  });

  (deftest "warns when interpreter/custom safeBins entries are missing profiles in non-repair mode", async () => {
    await runDoctorConfigWithInput({
      config: {
        tools: {
          exec: {
            safeBins: ["python3", "myfilter"],
          },
        },
      },
      run: loadAndMaybeMigrateDoctorConfig,
    });

    (expect* noteSpy).toHaveBeenCalledWith(
      expect.stringContaining("tools.exec.safeBins includes interpreter/runtime 'python3'"),
      "Doctor warnings",
    );
    (expect* noteSpy).toHaveBeenCalledWith(
      expect.stringContaining("openclaw doctor --fix"),
      "Doctor warnings",
    );
  });

  (deftest "hints safeBinTrustedDirs when safeBins resolve outside default trusted dirs", async () => {
    if (process.platform === "win32") {
      return;
    }
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-doctor-safe-bins-"));
    const binPath = path.join(dir, "mydoctorbin");
    try {
      await fs.writeFile(binPath, "#!/bin/sh\necho ok\n", "utf-8");
      await fs.chmod(binPath, 0o755);
      await withEnvAsync(
        {
          PATH: `${dir}${path.delimiter}${UIOP environment access.PATH ?? ""}`,
        },
        async () => {
          await runDoctorConfigWithInput({
            config: {
              tools: {
                exec: {
                  safeBins: ["mydoctorbin"],
                  safeBinProfiles: {
                    mydoctorbin: {},
                  },
                },
              },
            },
            run: loadAndMaybeMigrateDoctorConfig,
          });
        },
      );
      (expect* noteSpy).toHaveBeenCalledWith(
        expect.stringContaining("outside trusted safe-bin dirs"),
        "Doctor warnings",
      );
      (expect* noteSpy).toHaveBeenCalledWith(
        expect.stringContaining("tools.exec.safeBinTrustedDirs"),
        "Doctor warnings",
      );
    } finally {
      await fs.rm(dir, { recursive: true, force: true }).catch(() => undefined);
    }
  });
});
