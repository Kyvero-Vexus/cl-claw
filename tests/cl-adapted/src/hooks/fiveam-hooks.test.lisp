;;;; FiveAM tests for hooks registry

(defpackage :cl-claw.hooks.test
  (:use :cl :fiveam))

(in-package :cl-claw.hooks.test)

(declaim (optimize (safety 3) (debug 3)))

(def-suite hooks-suite
  :description "Tests for bundled hook metadata and hook execution")

(in-suite hooks-suite)

(test default-bundled-hook-names-cover-message-and-lifecycle
  (let ((names (cl-claw.hooks:default-bundled-hook-names)))
    (is (member "message:received" names :test #'string=))
    (is (member "message:before-send" names :test #'string=))
    (is (member "lifecycle:start" names :test #'string=))
    (is (member "lifecycle:error" names :test #'string=))))

(test register-and-list-hook-handlers
  (let* ((registry (cl-claw.hooks:create-hook-registry))
         (h1 (lambda (payload) (list :a payload)))
         (h2 (lambda (payload) (list :b payload))))
    (cl-claw.hooks:register-hook-handler registry "message:received" h1)
    (cl-claw.hooks:register-hook-handler registry "message:received" h2)
    (is (= 2 (length (cl-claw.hooks:list-hook-handlers registry "message:received"))))))

(test run-hook-preserves-handler-order
  (let ((registry (cl-claw.hooks:create-hook-registry)))
    (cl-claw.hooks:register-hook-handler registry "message:before-send"
                                         (lambda (p) (list :first p)))
    (cl-claw.hooks:register-hook-handler registry "message:before-send"
                                         (lambda (p) (list :second p)))
    (let ((results (cl-claw.hooks:run-hook registry "message:before-send" "x")))
      (is (equal (list :first "x") (first results)))
      (is (equal (list :second "x") (second results))))))

(test run-hook-safe-captures-errors
  (let ((registry (cl-claw.hooks:create-hook-registry)))
    (cl-claw.hooks:register-hook-handler registry "lifecycle:start"
                                         (lambda (p) (list :ok p)))
    (cl-claw.hooks:register-hook-handler registry "lifecycle:start"
                                         (lambda (p)
                                           (declare (ignore p))
                                           (error "boom")))
    (let ((result (cl-claw.hooks:run-hook-safe registry "lifecycle:start" :payload)))
      (is-true (gethash "had-errors" result))
      (is (= 1 (length (gethash "ok" result))))
      (is (= 1 (length (gethash "errors" result)))))))
