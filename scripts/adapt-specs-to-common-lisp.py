from pathlib import Path
import re

ROOT = Path('.').resolve()
SPEC = ROOT / 'specs'
OUT = SPEC / 'cl-adapted'
OUT.mkdir(parents=True, exist_ok=True)

REPLACEMENTS = [
    (r'\bNode\.js\b', 'SBCL/Common Lisp runtime'),
    (r'\bnode\b', 'sbcl'),
    (r'\bTypeScript\b', 'Common Lisp'),
    (r'\bJavaScript\b', 'Common Lisp'),
    (r'\bTS\b', 'CL'),
    (r'\bnpm/pnpm\b', 'ASDF/Quicklisp/Ultralisp'),
    (r'\bnpm\b', 'Quicklisp/Ultralisp'),
    (r'\bpnpm\b', 'ASDF/Quicklisp/Ultralisp'),
    (r'\bpackage\.json\b', 'ASDF system definition'),
    (r'\bVitest\b', 'FiveAM/Parachute'),
    (r'\bvitest\b', 'FiveAM/Parachute'),
    (r'\bPlaywright\b', 'CDP automation in Common Lisp (or external helper)'),
    (r'\bplaywright\b', 'CDP automation in Common Lisp (or external helper)'),
    (r'\bCDP\b', 'Chrome DevTools Protocol'),
    (r'\bWebSocket\b', 'WebSocket'),
    (r'\bSSE\b', 'Server-Sent Events'),
    (r'\bDocker CLI\b', 'Docker CLI invoked from Common Lisp'),
    (r'\bDocker\b', 'Docker (driven from Common Lisp)'),
    (r'\bJSON\b', 'JSON'),
    (r'\bCLI\b', 'command-line interface'),
    (r'\bRPC\b', 'RPC'),
    (r'\bESM\b', 'Common Lisp package/module structure'),
    (r'\b\.ts\b', '.lisp'),
    (r'\b\.mjs\b', '.lisp'),
    (r'\bprocess\.env\b', 'the process environment via UIOP'),
    (r'\bsubprocess\b', 'external process invoked from Common Lisp'),
    (r'\bOpenAI WS\b', 'provider WebSocket streaming from Common Lisp'),
]

HEADER = '''# Common Lisp adapted specification corpus

This directory contains Common Lisp–adapted rewrites of the extracted OpenClaw
spec corpus. The goal is adaptation, not simplification:

- preserve the original behavioral expectations
- remove TypeScript/Node-first implementation assumptions
- restate runtime/library expectations in Common Lisp terms
- use CL substitutions where upstream specs imply concrete libraries or stacks

When a feature has no strong pure-CL equivalent (notably browser automation),
the adapted spec still preserves the behavior and explicitly allows a narrow
external helper where necessary.
'''


def apply_replacements(text: str) -> str:
    out = text
    for pat, repl in REPLACEMENTS:
        out = re.sub(pat, repl, out)
    return out

# docs-index rewrite
src = SPEC / 'docs-index.md'
text = src.read_text()
text = HEADER + '\n\n' + apply_replacements(text)
text += '\n\n## Adaptation notes\n\n- Treat all command examples as interface contracts, not as a requirement to use a non-CL implementation language.\n- Replace original runtime assumptions with ASDF systems, Common Lisp packages, and UIOP-managed external process invocation where required.\n- Preserve documented protocols, routing, and user-visible behavior exactly unless a later simplification pass changes them deliberately.\n'
(OUT / 'docs-index.common-lisp.md').write_text(text)

# code spec rewrite
src = SPEC / 'code-spec-files.md'
text = src.read_text()
text = apply_replacements(text)
text = text.replace('```ts', '```lisp')
text = HEADER + '\n\n' + text + '\n\n## Adaptation notes\n\n- The original code-level spec fragments are to be re-expressed as Common Lisp functions/macros with equivalent argument contracts and failure behavior.\n- Preserve exact validation rules, parsing rules, selector semantics, and target-mode semantics.\n- Prefer ordinary functions plus condition types over JS/TS exception conventions.\n'
(OUT / 'code-spec-files.common-lisp.md').write_text(text)

# test specs rewrite
src = SPEC / 'test-specs.md'
text = src.read_text()
text = apply_replacements(text)
text = HEADER + '\n\n' + text + '\n\n## Adaptation notes\n\n- Each bullet remains a behavioral requirement.\n- Implement these as FiveAM or Parachute tests in Common Lisp.\n- Preserve edge cases, provider quirks, security constraints, and session semantics even when the internal CL architecture differs.\n'
(OUT / 'test-specs.common-lisp.md').write_text(text)

src = SPEC / 'test-specs-by-domain.md'
text = src.read_text()
text = apply_replacements(text)
text = HEADER + '\n\n' + text
(OUT / 'test-specs-by-domain.common-lisp.md').write_text(text)

# runtime/profile adaptation overview
runtime_doc = '''# Common Lisp runtime adaptation spec

This document defines the implementation-language adaptation policy for the
cl-claw specification corpus.

## Rule 1: Common Lisp is the implementation language

All implementation-facing specs in this repository target Common Lisp as the
primary and preferred implementation language.

- System structure: ASDF systems and Common Lisp packages
- Primary runtime: SBCL is the default target runtime
- Process/env/filesystem operations: UIOP and standard Common Lisp facilities
- HTTP/JSON APIs: Common Lisp libraries such as Dexador + JZON/YASON
- Crypto/HMAC: Ironclad
- Test framework: FiveAM or Parachute

## Rule 2: Preserve behavioral parity

Adaptation to Common Lisp does not permit behavioral drift. The following stay
normative:

- user-visible command surfaces
- gateway and session behavior
- routing and threading semantics
- tool contracts and parameter validation
- transport/auth/security rules
- provider normalization and failover semantics
- channel-specific formatting and delivery rules

## Rule 3: Library substitutions are allowed and expected

When the upstream spec corpus implies or names a Node/TypeScript library,
framework, or package ecosystem assumption, substitute the closest viable
Common Lisp equivalent.

The normative substitution ledger is:

- `specs/common-lisp-library-substitutions.md`

## Rule 4: External helpers are allowed only where needed for parity

If the target behavior has no strong pure-CL ecosystem equivalent, the Common
Lisp implementation may use a narrow external helper while keeping the control
plane, orchestration, validation, and user-facing behavior in Common Lisp.

Primary expected example:

- Browser automation: direct Chrome DevTools Protocol in CL, with an optional
  helper process for cases where Playwright-level behavior is otherwise too
  costly to replicate immediately.

## Rule 5: No simplification in this phase

This phase adapts language/runtime assumptions only.

It does not:

- shrink feature scope
- drop channels
- merge distinct behaviors
- weaken security properties
- discard provider-specific quirks captured by tests
- rewrite the product into a smaller or “more lispy” shape

That work, if desired, belongs to a later simplification pass.
'''
(OUT / 'runtime-adaptation-spec.md').write_text(runtime_doc)
