# cl-claw

Extracted specifications for OpenClaw, derived from the source tree at `~/openclaw`.

This repo is meant to be a practical specification corpus for a Common Lisp reimplementation effort:

- product/docs surface
- exact code-level spec modules
- behavioral test specs
- source manifest and provenance

## Source provenance

See `specs/source-manifest.json`.

## Generated artifacts

- `specs/docs-index.md` — documentation/spec surface discovered from `docs/`
- `specs/code-spec-files.md` — exact `*spec.ts` files and their contents
- `specs/test-specs.md` — extracted test titles grouped by file
- `specs/test-specs-by-domain.md` — same tests grouped by top-level subsystem
- `specs/source-manifest.json` — source commit, counts, and file inventory

## Regeneration

```bash
node scripts/extract-specs.mjs ~/openclaw
```

## Notes

This is an extraction repo, not a verbatim mirror. It intentionally favors auditable, structured spec artifacts over copying the full upstream codebase.
