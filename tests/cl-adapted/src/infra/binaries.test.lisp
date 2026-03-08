(defpackage :cl-claw.infra.binaries.test
  (:use :cl :fiveam))
(in-package :cl-claw.infra.binaries.test)

(def-suite binaries-suite)
(in-suite binaries-suite)

(test ensure-binary-passes-when-binary-exists
  (let ((exec-called nil))
    (cl-claw.infra.binaries:ensure-binary "sbcl" :exec-fn (lambda (cmd &key output)
                                                           (declare (ignore output))
                                                          (setf exec-called t)
                                                          (is (equal cmd "which sbcl"))))))

(test ensure-binary-logs-and-exits-when-missing
  (let ((error-called nil)
        (exit-called nil))
    (handler-case (cl-claw.infra.binaries:ensure-binary "ghost"
                                                :exec-fn (lambda (cmd &key output)
                                                           (declare (ignore output))
                                                           (error 'uiop/run-program:subprocess-error :command cmd :code 1 :stdout "" :stderr "not found"))
                                                :runtime (list :log (lambda (x) (print x))
                                                                :error (lambda (msg)
                                                                         (setf error-called t)
                                                                         (is (equal msg "Missing required binary: ghost. Please install it.")))
                                                                :exit (lambda (code)
                                                                        (setf exit-called t)
                                                                        (is (= code 1)))))
      (error (c) (print c)))
    (is-true error-called)
    (is-true exit-called)))
