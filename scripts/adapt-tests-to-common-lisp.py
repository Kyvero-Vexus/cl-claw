from pathlib import Path
import re

ROOT = Path('.').resolve()
RAW = ROOT / 'tests' / 'raw'
OUT = ROOT / 'tests' / 'cl-adapted'
OUT.mkdir(parents=True, exist_ok=True)

REPL = [
    (r'\bdescribe\s*\(', '(deftest-group '),
    (r'\btest\s*\(', '(deftest '),
    (r'\bit\s*\(', '(deftest '),
    (r'\bexpect\s*\(', '(expect* '),
    (r'\bvi\.', 'mock:'),
    (r'\bVitest\b', 'FiveAM/Parachute'),
    (r'\bvitest\b', 'FiveAM/Parachute'),
    (r'\bTypeScript\b', 'Common Lisp'),
    (r'\bJavaScript\b', 'Common Lisp'),
    (r'\bNode\.js\b', 'SBCL/Common Lisp runtime'),
    (r'\bnode\b', 'sbcl'),
    (r'\bpackage\.json\b', 'ASDF system definition'),
    (r'\bprocess\.env\b', 'UIOP environment access'),
    (r'\bPromise<', 'deferred-result<'),
    (r'\basync\b', 'async'),
    (r'\bawait\b', 'await'),
    (r'\bthrow new Error\b', 'error'),
    (r'\btoEqual\b', 'is-equal'),
    (r'\btoBe\b', 'is'),
    (r'\btoMatchObject\b', 'matches-object'),
    (r'\btoContain\b', 'contains'),
    (r'\btoHaveLength\b', 'has-length'),
    (r'\btoBeTruthy\b', 'is-truthy'),
    (r'\btoBeFalsy\b', 'is-falsy'),
    (r'\btoThrow\b', 'signals-error'),
    (r'\b\.ts\b', '.lisp'),
    (r'\b\.mjs\b', '.lisp'),
]

HEADER = ''';;;; Common Lisp–adapted test source
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

'''

INDEX_LINES = ['# Common Lisp adapted test source corpus', '']

for src in sorted([p for p in RAW.rglob('*') if p.is_file()]):
    rel = src.relative_to(RAW)
    out_rel = rel.with_suffix('.lisp') if rel.suffix == '.ts' else rel
    # preserve names like .test.ts -> .test.lisp
    if str(out_rel).endswith('.test.lisp') or str(out_rel).endswith('.spec.lisp'):
        pass
    else:
        s = str(out_rel)
        s = s.replace('.e2e.lisp', '.e2e.test.lisp')
        out_rel = Path(s)
    dest = OUT / out_rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    text = src.read_text(errors='ignore')
    for pat, repl in REPL:
        text = re.sub(pat, repl, text)
    text = HEADER + text
    dest.write_text(text)
    INDEX_LINES.append(f'- `{rel.as_posix()}` -> `{out_rel.as_posix()}`')

(ROOT / 'tests' / 'cl-adapted' / 'INDEX.md').write_text('\n'.join(INDEX_LINES) + '\n')
