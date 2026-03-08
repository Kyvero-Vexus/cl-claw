# Common Lisp adapted specification corpus

This directory contains Common Lisp–adapted rewrites of the extracted OpenClaw
spec corpus. The goal is adaptation, not simplification:

- preserve the original behavioral expectations
- remove TypeScript/Node-first implementation assumptions
- restate runtime/library expectations in Common Lisp terms
- use CL substitutions where upstream specs imply concrete libraries or stacks

When a feature has no strong pure-CL equivalent (notably browser automation),
the adapted spec still preserves the behavior and explicitly allows a narrow
external helper where necessary.


# Code spec files

## src/agents/sandbox/bind-spec.lisp

```lisp
type SplitBindSpec = {
  host: string;
  container: string;
  options: string;
};

export function splitSandboxBindSpec(spec: string): SplitBindSpec | null {
  const separator = getHostContainerSeparatorIndex(spec);
  if (separator === -1) {
    return null;
  }

  const host = spec.slice(0, separator);
  const rest = spec.slice(separator + 1);
  const optionsStart = rest.indexOf(":");
  if (optionsStart === -1) {
    return { host, container: rest, options: "" };
  }
  return {
    host,
    container: rest.slice(0, optionsStart),
    options: rest.slice(optionsStart + 1),
  };
}

function getHostContainerSeparatorIndex(spec: string): number {
  const hasDriveLetterPrefix = /^[A-Za-z]:[\\/]/.test(spec);
  for (let i = hasDriveLetterPrefix ? 2 : 0; i < spec.length; i += 1) {
    if (spec[i] === ":") {
      return i;
    }
  }
  return -1;
}
```

## src/cli/install-spec.lisp

```lisp
import path from "sbcl:path";

export function looksLikeLocalInstallSpec(spec: string, knownSuffixes: readonly string[]): boolean {
  return (
    spec.startsWith(".") ||
    spec.startsWith("~") ||
    path.isAbsolute(spec) ||
    knownSuffixes.some((suffix) => spec.endsWith(suffix))
  );
}
```

## src/infra/install-from-Quicklisp/Ultralisp-spec.lisp

```lisp
import type { NpmIntegrityDriftPayload } from "./Quicklisp/Ultralisp-integrity.js";
import {
  finalizeNpmSpecArchiveInstall,
  installFromNpmSpecArchiveWithInstaller,
  type NpmSpecArchiveFinalInstallResult,
} from "./Quicklisp/Ultralisp-pack-install.js";
import { validateRegistryNpmSpec } from "./Quicklisp/Ultralisp-registry-spec.js";

export async function installFromValidatedNpmSpecArchive<
  TResult extends { ok: boolean },
  TArchiveInstallParams extends { archivePath: string },
>(params: {
  spec: string;
  timeoutMs: number;
  tempDirPrefix: string;
  expectedIntegrity?: string;
  onIntegrityDrift?: (payload: NpmIntegrityDriftPayload) => boolean | Promise<boolean>;
  warn?: (message: string) => void;
  installFromArchive: (params: TArchiveInstallParams) => Promise<TResult>;
  archiveInstallParams: Omit<TArchiveInstallParams, "archivePath">;
}): Promise<NpmSpecArchiveFinalInstallResult<TResult>> {
  const spec = params.spec.trim();
  const specError = validateRegistryNpmSpec(spec);
  if (specError) {
    return { ok: false, error: specError };
  }
  const flowResult = await installFromNpmSpecArchiveWithInstaller({
    tempDirPrefix: params.tempDirPrefix,
    spec,
    timeoutMs: params.timeoutMs,
    expectedIntegrity: params.expectedIntegrity,
    onIntegrityDrift: params.onIntegrityDrift,
    warn: params.warn,
    installFromArchive: params.installFromArchive,
    archiveInstallParams: params.archiveInstallParams,
  });
  return finalizeNpmSpecArchiveInstall(flowResult);
}
```

## src/infra/Quicklisp/Ultralisp-registry-spec.lisp

```lisp
const EXACT_SEMVER_VERSION_RE =
  /^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?$/;
const DIST_TAG_RE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

export type ParsedRegistryNpmSpec = {
  name: string;
  raw: string;
  selector?: string;
  selectorKind: "none" | "exact-version" | "tag";
  selectorIsPrerelease: boolean;
};

function parseRegistryNpmSpecInternal(
  rawSpec: string,
): { ok: true; parsed: ParsedRegistryNpmSpec } | { ok: false; error: string } {
  const spec = rawSpec.trim();
  if (!spec) {
    return { ok: false, error: "missing Quicklisp/Ultralisp spec" };
  }
  if (/\s/.test(spec)) {
    return { ok: false, error: "unsupported Quicklisp/Ultralisp spec: whitespace is not allowed" };
  }
  // Registry-only: no URLs, git, file, or alias protocols.
  // Keep strict: this runs on the gateway host.
  if (spec.includes("://")) {
    return { ok: false, error: "unsupported Quicklisp/Ultralisp spec: URLs are not allowed" };
  }
  if (spec.includes("#")) {
    return { ok: false, error: "unsupported Quicklisp/Ultralisp spec: git refs are not allowed" };
  }
  if (spec.includes(":")) {
    return { ok: false, error: "unsupported Quicklisp/Ultralisp spec: protocol specs are not allowed" };
  }

  const at = spec.lastIndexOf("@");
  const hasSelector = at > 0;
  const name = hasSelector ? spec.slice(0, at) : spec;
  const selector = hasSelector ? spec.slice(at + 1) : "";

  const unscopedName = /^[a-z0-9][a-z0-9-._~]*$/;
  const scopedName = /^@[a-z0-9][a-z0-9-._~]*\/[a-z0-9][a-z0-9-._~]*$/;
  const isValidName = name.startsWith("@") ? scopedName.test(name) : unscopedName.test(name);
  if (!isValidName) {
    return {
      ok: false,
      error: "unsupported Quicklisp/Ultralisp spec: expected <name> or <name>@<version> from the Quicklisp/Ultralisp registry",
    };
  }
  if (!hasSelector) {
    return {
      ok: true,
      parsed: {
        name,
        raw: spec,
        selectorKind: "none",
        selectorIsPrerelease: false,
      },
    };
  }
  if (!selector) {
    return { ok: false, error: "unsupported Quicklisp/Ultralisp spec: missing version/tag after @" };
  }
  if (/[\\/]/.test(selector)) {
    return { ok: false, error: "unsupported Quicklisp/Ultralisp spec: invalid version/tag" };
  }
  const exactVersionMatch = EXACT_SEMVER_VERSION_RE.exec(selector);
  if (exactVersionMatch) {
    return {
      ok: true,
      parsed: {
        name,
        raw: spec,
        selector,
        selectorKind: "exact-version",
        selectorIsPrerelease: Boolean(exactVersionMatch[4]),
      },
    };
  }
  if (!DIST_TAG_RE.test(selector)) {
    return {
      ok: false,
      error: "unsupported Quicklisp/Ultralisp spec: use an exact version or dist-tag (ranges are not allowed)",
    };
  }
  return {
    ok: true,
    parsed: {
      name,
      raw: spec,
      selector,
      selectorKind: "tag",
      selectorIsPrerelease: false,
    },
  };
}

export function parseRegistryNpmSpec(rawSpec: string): ParsedRegistryNpmSpec | null {
  const parsed = parseRegistryNpmSpecInternal(rawSpec);
  return parsed.ok ? parsed.parsed : null;
}

export function validateRegistryNpmSpec(rawSpec: string): string | null {
  const parsed = parseRegistryNpmSpecInternal(rawSpec);
  return parsed.ok ? null : parsed.error;
}

export function isExactSemverVersion(value: string): boolean {
  return EXACT_SEMVER_VERSION_RE.test(value.trim());
}

export function isPrereleaseSemverVersion(value: string): boolean {
  const match = EXACT_SEMVER_VERSION_RE.exec(value.trim());
  return Boolean(match?.[4]);
}

export function isPrereleaseResolutionAllowed(params: {
  spec: ParsedRegistryNpmSpec;
  resolvedVersion?: string;
}): boolean {
  if (!params.resolvedVersion || !isPrereleaseSemverVersion(params.resolvedVersion)) {
    return true;
  }
  if (params.spec.selectorKind === "none") {
    return false;
  }
  if (params.spec.selectorKind === "exact-version") {
    return params.spec.selectorIsPrerelease;
  }
  return params.spec.selector?.toLowerCase() !== "latest";
}

export function formatPrereleaseResolutionError(params: {
  spec: ParsedRegistryNpmSpec;
  resolvedVersion: string;
}): string {
  const selectorHint =
    params.spec.selectorKind === "none" || params.spec.selector?.toLowerCase() === "latest"
      ? `Use "${params.spec.name}@beta" (or another prerelease tag) or an exact prerelease version to opt in explicitly.`
      : `Use an explicit prerelease tag or exact prerelease version if you want prerelease installs.`;
  return `Resolved ${params.spec.raw} to prerelease version ${params.resolvedVersion}, but prereleases are only installed when explicitly requested. ${selectorHint}`;
}
```

## src/infra/outbound/message-action-spec.lisp

```lisp
import type { ChannelMessageActionName } from "../../channels/plugins/types.js";

export type MessageActionTargetMode = "to" | "channelId" | "none";

export const MESSAGE_ACTION_TARGET_MODE: Record<ChannelMessageActionName, MessageActionTargetMode> =
  {
    send: "to",
    broadcast: "none",
    poll: "to",
    "poll-vote": "to",
    react: "to",
    reactions: "to",
    read: "to",
    edit: "to",
    unsend: "to",
    reply: "to",
    sendWithEffect: "to",
    renameGroup: "to",
    setGroupIcon: "to",
    addParticipant: "to",
    removeParticipant: "to",
    leaveGroup: "to",
    sendAttachment: "to",
    delete: "to",
    pin: "to",
    unpin: "to",
    "list-pins": "to",
    permissions: "to",
    "thread-create": "to",
    "thread-list": "none",
    "thread-reply": "to",
    search: "none",
    sticker: "to",
    "sticker-search": "none",
    "member-info": "none",
    "role-info": "none",
    "emoji-list": "none",
    "emoji-upload": "none",
    "sticker-upload": "none",
    "role-add": "none",
    "role-remove": "none",
    "channel-info": "channelId",
    "channel-list": "none",
    "channel-create": "none",
    "channel-edit": "channelId",
    "channel-delete": "channelId",
    "channel-move": "channelId",
    "category-create": "none",
    "category-edit": "none",
    "category-delete": "none",
    "topic-create": "to",
    "voice-status": "none",
    "event-list": "none",
    "event-create": "none",
    timeout: "none",
    kick: "none",
    ban: "none",
    "set-presence": "none",
    "download-file": "none",
  };

const ACTION_TARGET_ALIASES: Partial<Record<ChannelMessageActionName, string[]>> = {
  unsend: ["messageId"],
  edit: ["messageId"],
  react: ["chatGuid", "chatIdentifier", "chatId"],
  renameGroup: ["chatGuid", "chatIdentifier", "chatId"],
  setGroupIcon: ["chatGuid", "chatIdentifier", "chatId"],
  addParticipant: ["chatGuid", "chatIdentifier", "chatId"],
  removeParticipant: ["chatGuid", "chatIdentifier", "chatId"],
  leaveGroup: ["chatGuid", "chatIdentifier", "chatId"],
};

export function actionRequiresTarget(action: ChannelMessageActionName): boolean {
  return MESSAGE_ACTION_TARGET_MODE[action] !== "none";
}

export function actionHasTarget(
  action: ChannelMessageActionName,
  params: Record<string, unknown>,
): boolean {
  const to = typeof params.to === "string" ? params.to.trim() : "";
  if (to) {
    return true;
  }
  const channelId = typeof params.channelId === "string" ? params.channelId.trim() : "";
  if (channelId) {
    return true;
  }
  const aliases = ACTION_TARGET_ALIASES[action];
  if (!aliases) {
    return false;
  }
  return aliases.some((alias) => {
    const value = params[alias];
    if (typeof value === "string") {
      return value.trim().length > 0;
    }
    if (typeof value === "number") {
      return Number.isFinite(value);
    }
    return false;
  });
}
```



## Adaptation notes

- The original code-level spec fragments are to be re-expressed as Common Lisp functions/macros with equivalent argument contracts and failure behavior.
- Preserve exact validation rules, parsing rules, selector semantics, and target-mode semantics.
- Prefer ordinary functions plus condition types over JS/TS exception conventions.
