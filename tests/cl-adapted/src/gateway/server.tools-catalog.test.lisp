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
import { connectOk, installGatewayTestHooks, rpcReq } from "./test-helpers.js";
import { withServer } from "./test-with-server.js";

installGatewayTestHooks({ scope: "suite" });

(deftest-group "gateway tools.catalog", () => {
  (deftest "returns core catalog data and includes tts", async () => {
    await withServer(async (ws) => {
      await connectOk(ws, { token: "secret", scopes: ["operator.read"] });
      const res = await rpcReq<{
        agentId?: string;
        groups?: Array<{
          id?: string;
          source?: "core" | "plugin";
          tools?: Array<{ id?: string; source?: "core" | "plugin" }>;
        }>;
      }>(ws, "tools.catalog", {});

      (expect* res.ok).is(true);
      (expect* res.payload?.agentId).is-truthy();
      const mediaGroup = res.payload?.groups?.find((group) => group.id === "media");
      (expect* mediaGroup?.tools?.some((tool) => tool.id === "tts" && tool.source === "core")).is(
        true,
      );
    });
  });

  (deftest "supports includePlugins=false and rejects unknown agent ids", async () => {
    await withServer(async (ws) => {
      await connectOk(ws, { token: "secret", scopes: ["operator.read"] });

      const noPlugins = await rpcReq<{
        groups?: Array<{ source?: "core" | "plugin" }>;
      }>(ws, "tools.catalog", { includePlugins: false });
      (expect* noPlugins.ok).is(true);
      (expect* (noPlugins.payload?.groups ?? []).every((group) => group.source !== "plugin")).is(
        true,
      );

      const unknownAgent = await rpcReq(ws, "tools.catalog", { agentId: "does-not-exist" });
      (expect* unknownAgent.ok).is(false);
      (expect* unknownAgent.error?.message ?? "").contains("unknown agent id");
    });
  });
});
