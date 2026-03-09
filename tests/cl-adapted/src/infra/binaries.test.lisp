(defpackage :cl-claw.infra.binaries.test
  (:use :cl :fiveam))
(in-package :cl-claw.infra.binaries.test)

(def-suite binaries-suite)
(in-suite binaries-suite)

;;; ─── Success path ────────────────────────────────────────────────────────────

(test ensure-binary-passes-when-binary-exists
  (let ((exec-called nil))
    (cl-claw.infra.binaries:ensure-binary
     "sbcl"
     :exec-fn (lambda (cmd &key output)
                (declare (ignore output))
                (setf exec-called t)
                (is (equal cmd "which sbcl"))))))

;;; ─── Legacy :runtime callback path (backward compatibility) ──────────────────

(test ensure-binary-logs-and-exits-when-missing
  "Legacy :runtime plist interface: calls :error then :exit callbacks."
  (let ((error-called nil)
        (exit-called nil))
    (handler-case
        (cl-claw.infra.binaries:ensure-binary
         "ghost"
         :exec-fn (lambda (cmd &key output)
                    (declare (ignore output))
                    (error 'uiop/run-program:subprocess-error
                           :command cmd :code 1 :stdout "" :stderr "not found"))
         :runtime (list :log   (lambda (x) (print x))
                        :error (lambda (msg)
                                 (setf error-called t)
                                 (is (equal msg
                                            "Missing required binary: ghost. Please install it.")))
                        :exit  (lambda (code)
                                 (setf exit-called t)
                                 (is (= code 1)))))
      (error (c) (print c)))
    (is-true error-called)
    (is-true exit-called)))

;;; ─── CL-idiomatic condition path ─────────────────────────────────────────────

(test ensure-binary-signals-missing-binary-error
  "Without :runtime, signals MISSING-BINARY-ERROR condition."
  (let ((caught nil))
    (handler-case
        (cl-claw.infra.binaries:ensure-binary
         "ghost-binary-that-does-not-exist"
         :exec-fn (lambda (cmd &key output)
                    (declare (ignore output cmd))
                    (error "not found")))
      (cl-claw.infra.binaries:missing-binary-error (c)
        (setf caught c)
        (is (string= (cl-claw.infra.binaries:missing-binary-error-name c)
                     "ghost-binary-that-does-not-exist"))))
    (is-true caught)))

(test ensure-binary-restart-exit-with-error-is-available
  "The EXIT-WITH-ERROR restart is established when no :runtime is supplied."
  (let ((restart-found nil))
    (handler-bind
        ((cl-claw.infra.binaries:missing-binary-error
          (lambda (c)
            (declare (ignore c))
            ;; Use the exported symbol so the package matches the restart name.
            (let ((r (find-restart 'cl-claw.infra.binaries:exit-with-error)))
              (when r (setf restart-found t)))
            ;; Do not actually invoke EXIT-WITH-ERROR (would call uiop:quit).
            (invoke-restart 'continue))))
      (restart-case
          (cl-claw.infra.binaries:ensure-binary
           "no-such-binary"
           :exec-fn (lambda (cmd &key output)
                      (declare (ignore output cmd))
                      (error "not found")))
        (continue () nil)))
    (is-true restart-found)))
