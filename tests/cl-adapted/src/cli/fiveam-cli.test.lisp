;;;; FiveAM tests for CLI helpers

(defpackage :cl-claw.cli.test
  (:use :cl :fiveam))

(in-package :cl-claw.cli.test)

(declaim (optimize (safety 3) (debug 3)))

(def-suite cli-suite
  :description "Tests for command-line and install-spec parsing")

(in-suite cli-suite)

(test looks-like-local-install-spec
  (is-true (cl-claw.cli.install-spec:looks-like-local-install-spec "./pkg" (list ".tgz")))
  (is-true (cl-claw.cli.install-spec:looks-like-local-install-spec "~/pkg" (list ".tgz")))
  (is-true (cl-claw.cli.install-spec:looks-like-local-install-spec "/opt/pkg" (list ".tgz")))
  (is-true (cl-claw.cli.install-spec:looks-like-local-install-spec "release.tgz" (list ".zip" ".tgz")))
  (is-false (cl-claw.cli.install-spec:looks-like-local-install-spec "openclaw/core" (list ".tgz"))))

(test parse-global-options-basic
  (let ((parsed (cl-claw.cli:parse-global-options (list "--json" "-v" "gateway" "status"))))
    (is-true (gethash "json" parsed))
    (is-true (gethash "verbose" parsed))
    (is (equal (list "gateway" "status") (gethash "rest" parsed)))))

(test parse-global-options-unknown-option-is-left-in-rest
  (let ((parsed (cl-claw.cli:parse-global-options (list "--wat" "models" "list"))))
    (is (equal (list "--wat" "models" "list") (gethash "rest" parsed)))))

(test parse-command-line-splits-command-subcommand-and-args
  (let ((parsed (cl-claw.cli:parse-command-line (list "--json" "Gateway" "Status" "--probe" "--fast"))))
    (is-true (gethash "json" parsed))
    (is (string= "gateway" (gethash "command" parsed)))
    (is (string= "status" (gethash "subcommand" parsed)))
    (is (equal (list "--probe" "--fast") (gethash "args" parsed)))
    (is (string= "gateway status --probe --fast"
                 (cl-claw.cli:command-invocation-string parsed)))))
