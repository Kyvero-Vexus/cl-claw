# cl-claw

Common Lisp–adapted specification corpus for OpenClaw.

This repository starts from an extracted OpenClaw spec corpus and rewrites it so
that Common Lisp is the only implementation language assumed by the specs,
without simplifying the underlying behavior.

## What this repo contains

### Raw extracted corpus
- `specs/docs-index.md`
- `specs/code-spec-files.md`
- `specs/test-specs.md`
- `specs/test-specs-by-domain.md`
- `specs/source-manifest.json`

### Common Lisp–adapted corpus
- `specs/cl-adapted/runtime-adaptation-spec.md`
- `specs/cl-adapted/docs-index.common-lisp.md`
- `specs/cl-adapted/code-spec-files.common-lisp.md`
- `specs/cl-adapted/test-specs.common-lisp.md`
- `specs/cl-adapted/test-specs-by-domain.common-lisp.md`
- `specs/common-lisp-library-substitutions.md`

## Adaptation rules

- Preserve behavior.
- Replace Node/TypeScript assumptions with Common Lisp assumptions.
- When upstream specs imply concrete libraries, use the closest Common Lisp
  substitute.
- Where no strong pure-CL equivalent exists, permit a narrow external helper
  while keeping control and semantics in Common Lisp.
- Do not simplify in this phase.

## Source provenance

See `specs/source-manifest.json`.

## Regeneration

```bash
node scripts/extract-specs.mjs ~/openclaw
python3 scripts/adapt-specs-to-common-lisp.py
```
