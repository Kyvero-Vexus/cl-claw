;;;; allow-from-test.lisp — Tests for channels allow-from validation

(in-package :cl-claw.channels.tests)

(in-suite :channels-allow-from)

(defun %make-allow-from-config (allow-from)
  "Create allow-from configuration."
  (make-nested-config "channels.allow-from" allow-from))

(test allow-from-parse-allow-from
  "Parses allow-from specification"
  (let ((config (%make-allow-from-config "user1,user2")))
    (let ((result (cl-claw.channels:parse-allow-from config)))
      (is (not (null result))
      (is (listp result))
      (is (= 2 (length result)))
      (is (member "user1" result)))))

(test allow-from-validate-source
  "Validates a message source"
  (let* ((allow-from (%make-allow-from-config "user1,user2"))
         (from-user1 "user1")
         (from-user2 "user3"))
    (is (cl-claw.channels:validate-source allow-from from-user1))
    (is (not (cl-claw.channels:validate-source allow-from from-user2)))))

(test allow-from-empty-allow-from
  "Handles empty allow-from (allow all)"
  (let ((config (%make-allow-from-config "")))
    (let ((result (cl-claw.channels:parse-allow-from config)))
      (is (not (null result))
      (is (eq t (cl-claw.channels:validate-source result "any-user"))))))

(test allow-from-wildcard-allow-from
  "Handles wildcard (*) in allow-from"
  (let ((config (%make-allow-from-config "*")))
    (let ((result (cl-claw.channels:parse-allow-from config)))
      (is (not (null result))
      (is (cl-claw.channels:validate-source result "any-user")))))
