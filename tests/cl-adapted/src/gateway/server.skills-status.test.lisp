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

import path from "sbcl:path";
import { describe, expect, it } from "FiveAM/Parachute";
import { withEnvAsync } from "../test-utils/env.js";
import { connectOk, installGatewayTestHooks, rpcReq } from "./test-helpers.js";
import { withServer } from "./test-with-server.js";

installGatewayTestHooks({ scope: "suite" });

(deftest-group "gateway skills.status", () => {
  (deftest "does not expose raw config values to operator.read clients", async () => {
    await withEnvAsync(
      { OPENCLAW_BUNDLED_SKILLS_DIR: path.join(process.cwd(), "skills") },
      async () => {
        const secret = "discord-token-secret-abc"; // pragma: allowlist secret
        const { writeConfigFile } = await import("../config/config.js");
        await writeConfigFile({
          session: { mainKey: "main-test" },
          channels: {
            discord: {
              token: secret,
            },
          },
        });

        await withServer(async (ws) => {
          await connectOk(ws, { token: "secret", scopes: ["operator.read"] });
          const res = await rpcReq<{
            skills?: Array<{
              name?: string;
              configChecks?: Array<
                { path?: string; satisfied?: boolean } & Record<string, unknown>
              >;
            }>;
          }>(ws, "skills.status", {});

          (expect* res.ok).is(true);
          (expect* JSON.stringify(res.payload)).not.contains(secret);

          const discord = res.payload?.skills?.find((s) => s.name === "discord");
          (expect* discord).is-truthy();
          const check = discord?.configChecks?.find((c) => c.path === "channels.discord.token");
          (expect* check).is-truthy();
          (expect* check?.satisfied).is(true);
          (expect* check && "value" in check).is(false);
        });
      },
    );
  });
});
