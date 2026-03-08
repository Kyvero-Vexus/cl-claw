# Static Typing Strategy for `cl-claw`

## Executive recommendation

Use a **hybrid strategy**:

1. **Primary requirement for “static typing”**: introduce **Coalton** for new core logic and for high-risk modules being ported.
2. **Project-wide baseline**: enforce **strict SBCL type-declaration discipline** (compile-time warnings as errors, high-safety CI builds, explicit function/slot/value types) across ordinary Common Lisp code.
3. Treat “Typed Common Lisp” research/prototype systems as **non-blocking experiments**, not a dependency for production delivery.

This is the most practical way to get real static guarantees without breaking interoperability with the existing Common Lisp ecosystem.

---

## Why this recommendation

### Coalton first (as requested)

Coalton is currently the most realistic maintained path to true static typing in the CL world:

- It provides compile-time inference/checking (HM-style, ML-like surface).
- It is designed to interoperate with Common Lisp code and data.
- It is actively used in real systems (per project docs), not just a paper prototype.

Important caveat: Coalton is still pre-1.0 and not in Quicklisp yet, so stability/process controls are needed.

### SBCL declaration discipline as the foundation

Even without a full typed language, SBCL gives strong leverage if used rigorously:

- SBCL treats declarations as assertions and performs aggressive type analysis.
- With high safety and strict warning policy, many type issues are found at compile time and runtime test phases.
- This works immediately with existing CL libraries and near-literal ports.

This is not full static typing, but it is low-friction and scales operationally.

### Why not “Typed Common Lisp” alternatives as primary path

There is no broadly adopted, clearly maintained, production-grade “Typed CL overlay” with Coalton-level momentum and integration story today. Existing efforts are largely research/prototype/fragmented compared to what a large OpenClaw-like codebase needs.

---

## Option comparison (practical)

## 1) Coalton-centric modules

**Pros**
- Real static typing and inference.
- Better long-term correctness boundary for critical logic.
- Interop story with CL is intentionally supported.

**Cons**
- Non-trivial language shift (ML-ish style, ADTs/typeclasses).
- Porting near-literal CL code into Coalton can be awkward in macro-heavy/dynamic regions.
- Pre-1.0 toolchain/process risk.

**Best fit in `cl-claw`**
- Domain logic, protocol/state models, transformation pipelines, validation code.
- New subsystems where type-driven design helps reduce regressions.

## 2) Strict SBCL typed-discipline CL (declarations + CI policy)

**Pros**
- Minimal disruption to existing CL code and libraries.
- Excellent ecosystem fit and incremental adoption.
- Supports near-literal ports almost directly.

**Cons**
- Not full static typing.
- Discipline can drift without hard CI gates.
- More false confidence possible if declarations are too weak/imprecise.

**Best fit in `cl-claw`**
- Large compatibility surface, glue code, macro-rich integration layers, third-party API boundaries.

## 3) Other Typed-CL approaches (research/prototypes)

**Pros**
- Interesting ideas for gradual typing.

**Cons**
- Maintenance/adoption risk too high for core dependency.
- Unclear interoperability and migration tooling for large production codebases.

**Best fit in `cl-claw`**
- Optional R&D spike only.

---

## Migration/adaptation guidance

### Phase 0: Define enforceable “typed enough” policy

Adopt a project policy that code is accepted only if:

- Every exported/public function has explicit argument/result type intent (declarations or Coalton signatures).
- CI runs SBCL in strict mode with high safety and treats warnings as failures.
- New critical modules are evaluated for Coalton-first implementation.

### Phase 1: Harden plain CL baseline (immediate)

- Add declaration standards for:
  - function args/returns,
  - struct/class slots,
  - key local variables in hot/critical paths.
- Build with aggressive diagnostics and fail CI on type-related warnings.
- Keep a safe build/test profile that maximizes runtime assertion checking before optimized builds.

This gives immediate quality gains while preserving near-literal ports.

### Phase 2: Introduce Coalton at bounded seams

- Start with one or two high-value modules with clear data models.
- Expose thin CL-facing APIs around Coalton code.
- Keep impure/FFI/macro-heavy edges in CL; keep pure core logic in Coalton.

### Phase 3: Expand typed core selectively

Promote modules to Coalton when they meet at least two criteria:

- high defect cost,
- stable domain model,
- heavy transformation/validation logic,
- frequent regressions from representation mistakes.

### Phase 4: Long-term steady state

- **Typed core** (Coalton) + **dynamic integration shell** (CL with strict declarations).
- Avoid full rewrites driven only by ideology; move modules when ROI is clear.

---

## Practical rules for near-literal ports

To preserve behavior while adding typing pressure:

1. Port literally into CL first with strong declarations and tests.
2. Stabilize behavior parity.
3. Migrate internals of selected modules to Coalton behind unchanged CL API boundaries.
4. Keep escape hatches explicit at boundaries (conversion/adapters), not scattered.

This reduces semantic drift while still improving type safety over time.

---

## Decision statement

For `cl-claw`, the best practical requirement is:

- **Mandate strict SBCL type-discipline project-wide now**, and
- **Mandate Coalton for new/critical pure-core modules by default unless explicitly exempted**.

This gives immediate maintainability and ecosystem compatibility, while establishing a credible path to stronger static guarantees for a large, evolving Common Lisp system.