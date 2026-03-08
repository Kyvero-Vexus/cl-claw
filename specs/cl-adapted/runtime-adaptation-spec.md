# Common Lisp runtime adaptation spec

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
- Static typing policy: strict SBCL type declarations everywhere, with Coalton preferred for new or critical pure-core modules

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
