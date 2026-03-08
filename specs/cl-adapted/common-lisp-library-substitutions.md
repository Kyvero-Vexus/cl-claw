# Common Lisp Library Substitutions

This document is the normative ledger for substituting Common Lisp libraries
in place of Node.js/TypeScript ecosystem dependencies mentioned or implied
in the upstream OpenClaw specification corpus.

This ledger is maintained as part of the `cl-claw` project. Changes should be
proposed via pull request and reviewed against project goals.

## Core Substitutions

| Upstream (Node/TS) | Downstream (Common Lisp) | Rationale / Notes |
|--------------------|--------------------------|-------------------|
| `node-fetch` / `axios` | `dexador`                | General-purpose HTTP client. |
| `express` / `fastify` | `ningle` / `hunchentoot` | Web framework for routing and handling requests. Ningle is a lightweight routing library, often used with Hunchentoot. |
| (built-in JSON)    | `yason` / `jzon`         | Encoding and decoding JSON. YASON is a popular choice. JZON is more modern and performant. |
| `crypto` (Node.js) | `ironclad`               | Cryptographic functions (hashing, HMAC, ciphers). |
| `jest` / `mocha`   | `fiveam` / `parachute`   | Testing frameworks. FiveAM is a popular xUnit-style framework. |
| `fs` (Node.js)     | `uiop`                   | Filesystem, subprocess, and OS interaction utilities. `uiop` provides a portable layer over implementation-specific features. |
| `commander` / `yargs` | `cl-getopt` / `clingon` | Command-line argument parsing. |
| `ws`               | `usocket` / `cl-websockets` | WebSocket client and server. |
| `ioredis`          | `cl-redis`               | Redis client library. |
| `uuid`             | `cl-uuid`                | Generating and parsing UUIDs. |

## Policy

- **Prefer pure CL:** Libraries written in pure Common Lisp are preferred for portability.
- **ASDF installable:** Libraries should be installable via Quicklisp or a similar ASDF-compatible mechanism.
- **Actively maintained:** Prefer libraries that are actively developed and maintained.
- **SBCL compatible:** Must be compatible with SBCL, the primary target runtime.

This list is not exhaustive and will be expanded as new substitution needs are identified during implementation.
