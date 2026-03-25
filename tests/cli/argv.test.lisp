;;;; FiveAM tests for CLI argument parsing

(in-package :cl-claw.cli.tests)

(declaim (optimize (safety 3) (debug 3)))

(in-suite cli-suite)

;; Tests for argv helper functions

(test has-help-flag-basic
  "Detects --help flag"
  (let ((argv '("sbcl" "openclaw" "--help")))
    ;; TODO: Implement when has-help-or-version function is available
    (skip "argv parsing functions not yet available")))

(test has-version-flag-basic
  "Detects -V version flag"
  (let ((argv '("sbcl" "openclaw" "-V")))
    ;; TODO: Implement when has-help-or-version function is available
    (skip "argv parsing functions not yet available")))

(test has-version-v-alias
  "Detects -v as version flag at root level"
  (let ((argv '("sbcl" "openclaw" "-v")))
    ;; TODO: Implement when has-help-or-version function is available
    (skip "argv parsing functions not yet available")))

(test subcommand-v-not-version
  "Subcommand -v should not be treated as version"
  (let ((argv '("sbcl" "openclaw" "acp" "-v")))
    ;; TODO: Implement when has-help-or-version function is available
    (skip "argv parsing functions not yet available")))

(test normal-command-not-help-version
  "Normal command has no help/version flags"
  (let ((argv '("sbcl" "openclaw" "status")))
    ;; TODO: Implement when has-help-or-version function is available
    (skip "argv parsing functions not yet available")))

(test root-v-with-profile
  "Root -v with profile flag is still version"
  (let ((argv '("sbcl" "openclaw" "--profile" "work" "-v")))
    ;; TODO: Implement when has-help-or-version function is available
    (skip "argv parsing functions not yet available")))

(test root-v-with-log-level
  "Root -v with log-level flag is still version"
  (let ((argv '("sbcl" "openclaw" "--log-level" "debug" "-v")))
    ;; TODO: Implement when has-help-or-version function is available
    (skip "argv parsing functions not yet available")))

(test subcommand-path-after-flags
  "Subcommand path after global flags should not be version"
  (let ((argv '("sbcl" "openclaw" "--dev" "skills" "list" "-v")))
    ;; TODO: Implement when has-help-or-version function is available
    (skip "argv parsing functions not yet available")))
