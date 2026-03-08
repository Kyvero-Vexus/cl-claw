(defpackage :cl-claw.infra.binaries
  (:use :cl)
  (:export :ensure-binary))
(in-package :cl-claw.infra.binaries)

(defun ensure-binary (binary-name &key (exec-fn #'uiop:run-program) (runtime (list :log (lambda (x) (print x)) :error (lambda (x) (error x)) :exit #'uiop:quit)))
  (handler-case (progn
                  (funcall exec-fn (format nil "which ~a" binary-name) :output :string)
                  t)
    (uiop/run-program:subprocess-error (c)
      (let ((error-message (format nil "Missing required binary: ~a. Please install it." binary-name)))
        (funcall (getf runtime :error) error-message)
        (funcall (getf runtime :exit) 1)))))
