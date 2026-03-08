(defpackage :cl-claw.infra.abort-signal.test
  (:use :cl :fiveam))
(in-package :cl-claw.infra.abort-signal.test)

(def-suite abort-signal-suite)
(in-suite abort-signal-suite)

(test resolves-immediately-when-signal-is-missing
  "Resolves immediately when signal is missing"
  (let ((result (cl-claw.infra.abort-signal:wait-for-abort-signal nil)))
    (is (eq result :ok))))

(test resolves-immediately-when-signal-is-already-aborted
  "Resolves immediately when signal is already aborted"
  (let ((controller (cl-claw.infra.abort-signal:make-abort-controller)))
    (cl-claw.infra.abort-signal:trigger-abort controller)
    (let ((result (cl-claw.infra.abort-signal:wait-for-abort-signal
                   (cl-claw.infra.abort-signal:abort-controller-signal controller))))
      (is (eq result :ok)))))

(test waits-until-abort-fires
  "Waits until abort fires"
  (let ((controller (cl-claw.infra.abort-signal:make-abort-controller))
        (resolved nil))
    ;; Start waiting in a separate thread
    (sb-thread:make-thread
     (lambda ()
       (cl-claw.infra.abort-signal:wait-for-abort-signal
        (cl-claw.infra.abort-signal:abort-controller-signal controller))
       (setf resolved t)))
    ;; Give it a moment to start
    (sleep 0.05)
    (is (eq resolved nil))
    ;; Abort the signal
    (cl-claw.infra.abort-signal:trigger-abort controller)
    ;; Wait for the thread to complete
    (sleep 0.1)
    (is (eq resolved t))))
