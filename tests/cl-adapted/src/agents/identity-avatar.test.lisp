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
import { afterEach, describe, expect, it } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../config/config.js";
import { AVATAR_MAX_BYTES } from "../shared/avatar-policy.js";
import { resolveAgentAvatar } from "./identity-avatar.js";

async function writeFile(filePath: string, contents = "avatar") {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, contents, "utf-8");
}

async function expectLocalAvatarPath(
  cfg: OpenClawConfig,
  workspace: string,
  expectedRelativePath: string,
) {
  const workspaceReal = await fs.realpath(workspace);
  const resolved = resolveAgentAvatar(cfg, "main");
  (expect* resolved.kind).is("local");
  if (resolved.kind === "local") {
    const resolvedReal = await fs.realpath(resolved.filePath);
    (expect* path.relative(workspaceReal, resolvedReal)).is(expectedRelativePath);
  }
}

const tempRoots: string[] = [];

async function createTempAvatarRoot() {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-avatar-"));
  tempRoots.push(root);
  return root;
}

afterEach(async () => {
  await Promise.all(
    tempRoots
      .splice(0, tempRoots.length)
      .map((root) => fs.rm(root, { recursive: true, force: true })),
  );
});

(deftest-group "resolveAgentAvatar", () => {
  (deftest "resolves local avatar from config when inside workspace", async () => {
    const root = await createTempAvatarRoot();
    const workspace = path.join(root, "work");
    const avatarPath = path.join(workspace, "avatars", "main.png");
    await writeFile(avatarPath);

    const cfg: OpenClawConfig = {
      agents: {
        list: [
          {
            id: "main",
            workspace,
            identity: { avatar: "avatars/main.png" },
          },
        ],
      },
    };

    await expectLocalAvatarPath(cfg, workspace, path.join("avatars", "main.png"));
  });

  (deftest "rejects avatars outside the workspace", async () => {
    const root = await createTempAvatarRoot();
    const workspace = path.join(root, "work");
    await fs.mkdir(workspace, { recursive: true });
    const outsidePath = path.join(root, "outside.png");
    await writeFile(outsidePath);

    const cfg: OpenClawConfig = {
      agents: {
        list: [
          {
            id: "main",
            workspace,
            identity: { avatar: outsidePath },
          },
        ],
      },
    };

    const resolved = resolveAgentAvatar(cfg, "main");
    (expect* resolved.kind).is("none");
    if (resolved.kind === "none") {
      (expect* resolved.reason).is("outside_workspace");
    }
  });

  (deftest "falls back to IDENTITY.md when config has no avatar", async () => {
    const root = await createTempAvatarRoot();
    const workspace = path.join(root, "work");
    const avatarPath = path.join(workspace, "avatars", "fallback.png");
    await writeFile(avatarPath);
    await fs.mkdir(workspace, { recursive: true });
    await fs.writeFile(
      path.join(workspace, "IDENTITY.md"),
      "- Avatar: avatars/fallback.png\n",
      "utf-8",
    );

    const cfg: OpenClawConfig = {
      agents: {
        list: [{ id: "main", workspace }],
      },
    };

    await expectLocalAvatarPath(cfg, workspace, path.join("avatars", "fallback.png"));
  });

  (deftest "returns missing for non-existent local avatar files", async () => {
    const root = await createTempAvatarRoot();
    const workspace = path.join(root, "work");
    await fs.mkdir(workspace, { recursive: true });

    const cfg: OpenClawConfig = {
      agents: {
        list: [{ id: "main", workspace, identity: { avatar: "avatars/missing.png" } }],
      },
    };

    const resolved = resolveAgentAvatar(cfg, "main");
    (expect* resolved.kind).is("none");
    if (resolved.kind === "none") {
      (expect* resolved.reason).is("missing");
    }
  });

  (deftest "rejects local avatars larger than max bytes", async () => {
    const root = await createTempAvatarRoot();
    const workspace = path.join(root, "work");
    const avatarPath = path.join(workspace, "avatars", "too-big.png");
    await fs.mkdir(path.dirname(avatarPath), { recursive: true });
    await fs.writeFile(avatarPath, Buffer.alloc(AVATAR_MAX_BYTES + 1));

    const cfg: OpenClawConfig = {
      agents: {
        list: [{ id: "main", workspace, identity: { avatar: "avatars/too-big.png" } }],
      },
    };

    const resolved = resolveAgentAvatar(cfg, "main");
    (expect* resolved.kind).is("none");
    if (resolved.kind === "none") {
      (expect* resolved.reason).is("too_large");
    }
  });

  (deftest "accepts remote and data avatars", () => {
    const cfg: OpenClawConfig = {
      agents: {
        list: [
          { id: "main", identity: { avatar: "https://example.com/avatar.png" } },
          { id: "data", identity: { avatar: "data:image/png;base64,aaaa" } },
        ],
      },
    };

    const remote = resolveAgentAvatar(cfg, "main");
    (expect* remote.kind).is("remote");

    const data = resolveAgentAvatar(cfg, "data");
    (expect* data.kind).is("data");
  });
});
