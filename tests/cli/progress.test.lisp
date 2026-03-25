;;;; FiveAM tests for CLI progress display

(in-package :cl-claw.cli.tests)

(declaim (optimize (safety 3) (debug 3)))

(in-suite cli-suite)

;; Tests for CLI progress display

(test cli-progress-non-tty-fallback-log
  "Logs progress when non-tty and fallback=log"
  ;; TODO: Implement when create-cli-progress function is available
  (skip "cli-progress functions not yet available"))

(test cli-progress-non-tty-fallback-none
  "Does not log without tty when fallback is none"
  ;; TODO: Implement when create-cli-progress function is available
  (skip "cli-progress functions not yet available"))

(test cli-progress-tty-display
  "Displays progress bar on tty"
  ;; TODO: Implement when create-cli-progress function is available
  (skip "cli-progress functions not yet available"))

(test cli-progress-percent-update
  "Updates progress percentage correctly"
  ;; TODO: Implement when create-cli-progress function is available
  (skip "cli-progress functions not yet available"))

(test cli-progress-done-completes
  "Completes progress display on done"
  ;; TODO: Implement when create-cli-progress function is available
  (skip "cli-progress functions not yet available"))
