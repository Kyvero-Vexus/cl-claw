;;;; allow-from-test.lisp — Tests for channels allow-from validation

(in-package :cl-claw.channels.tests)

(in-suite :channels-allow-from)

(test allow-from-parse-allow-from
  "Parses allow-from specification"
  (let* ((config (make-test-config "allowFrom" '("user1" "user2")))
         (result (cl-claw.channels:parse-allow-from config)))
    (is (listp result))
    (is (= 2 (length result)))))

(test allow-from-validate-source-wildcard
  "Validates wildcard source"
  (is (cl-claw.channels:validate-source '("*") "any-user")))

(test allow-from-validate-source-nil
  "Returns nil for non-matching source"
  (is (null (cl-claw.channels:validate-source '("user1") "user2"))))
