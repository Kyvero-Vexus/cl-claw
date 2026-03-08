;;;; FiveAM tests for command dispatch metadata

(defpackage :cl-claw.commands.test
  (:use :cl :fiveam))

(in-package :cl-claw.commands.test)

(declaim (optimize (safety 3) (debug 3)))

(def-suite commands-suite
  :description "Tests for command registry and command/subcommand validation")

(in-suite commands-suite)

(test default-command-table-has-core-domains
  (let ((table (cl-claw.commands:create-default-command-table)))
    (is-true (cl-claw.commands:command-known-p table "agent"))
    (is-true (cl-claw.commands:command-known-p table "daemon"))
    (is-true (cl-claw.commands:command-known-p table "configure"))
    (is-false (cl-claw.commands:command-known-p table "unknown"))))

(test subcommand-validation
  (let ((table (cl-claw.commands:create-default-command-table)))
    (is-true (cl-claw.commands:subcommand-known-p table "daemon" "status"))
    (is-false (cl-claw.commands:subcommand-known-p table "daemon" "boom"))))

(test resolve-command-action-errors-when-command-is-unknown
  (let* ((table (cl-claw.commands:create-default-command-table))
         (result (cl-claw.commands:resolve-command-action table "nope" "status" nil)))
    (is-false (gethash "ok" result))
    (is (search "Unknown command" (gethash "error" result)))))

(test resolve-command-action-errors-when-subcommand-missing
  (let* ((table (cl-claw.commands:create-default-command-table))
         (result (cl-claw.commands:resolve-command-action table "daemon" nil nil)))
    (is-false (gethash "ok" result))
    (is (search "requires a subcommand" (gethash "error" result)))))

(test resolve-command-action-errors-when-subcommand-unknown
  (let* ((table (cl-claw.commands:create-default-command-table))
         (result (cl-claw.commands:resolve-command-action table "daemon" "boom" nil)))
    (is-false (gethash "ok" result))
    (is (search "Unknown subcommand" (gethash "error" result)))))

(test resolve-command-action-succeeds-for-valid-command
  (let* ((table (cl-claw.commands:create-default-command-table))
         (result (cl-claw.commands:resolve-command-action table "daemon" "status" (list "--json"))))
    (is-true (gethash "ok" result))
    (is (string= "daemon" (gethash "command" result)))
    (is (string= "status" (gethash "subcommand" result)))
    (is (equal (list "--json") (gethash "args" result)))))
