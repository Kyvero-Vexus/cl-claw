# Acknowledgements

## OpenClaw

This project is a Common Lisp port of [OpenClaw](https://github.com/openclaw/openclaw),
an open-source AI agent platform.

- **Source:** https://github.com/openclaw/openclaw
- **Commit:** 4db634964b93f5b1f64746fbd1f4777f1f895d81
- **License:** MIT License
- **Copyright:** (c) 2025 Peter Steinberger

The specification corpus in `specs/` was extracted from OpenClaw and adapted
for Common Lisp runtime assumptions. We preserve the behavioral semantics while
replacing Node.js/TypeScript-specific assumptions with Common Lisp equivalents.

### MIT License (OpenClaw)

```
MIT License

Copyright (c) 2025 Peter Steinberger

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Common Lisp Libraries

This project uses or plans to use the following Common Lisp libraries:

- **SBCL** — Steel Bank Common Lisp compiler
- **FiveAM** — Test framework
- **Alexandria** — Utility functions
- **UIOP** — Utilities for cross-implementation portability
- **Dexador** — HTTP client
- **Jonathan** — JSON parsing
- **Ironclad** — Cryptography
- **CL-PPCRE** — Regular expressions

See `specs/common-lisp-library-substitutions.md` for the full mapping.
