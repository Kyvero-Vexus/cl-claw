# cl-claw

Common Lisp port of OpenClaw — statically typed, homoiconic, libre.

This repository contains a Common Lisp implementation adapted from the
[OpenClaw](https://github.com/openclaw/openclaw) specification corpus.

## License

- **Implementation code** (`src/`): AGPL-3.0-or-later
- **Adapted specs** (`specs/cl-adapted/`): Derived from OpenClaw (MIT)

### OpenClaw Acknowledgement

This project adapts specification and test materials from OpenClaw:

```
OpenClaw - https://github.com/openclaw/openclaw
Copyright (c) 2025 Peter Steinberger
Licensed under the MIT License
```

The full MIT license text is available at:
https://opensource.org/licenses/MIT

We gratefully acknowledge the OpenClaw project for providing the spec corpus
that made this port possible.

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
- Require statically typed Common Lisp discipline: SBCL type declarations as baseline, with Coalton for suitable core modules.

## Source provenance

See `specs/source-manifest.json`.

## Regeneration

```bash
node scripts/extract-specs.mjs ~/openclaw
python3 scripts/adapt-specs-to-common-lisp.py
```
