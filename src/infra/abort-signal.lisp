;;;; abort-signal.lisp - Abort signal pattern for cl-claw
;;;;
;;;; Implements abort signal pattern similar to JavaScript's AbortController/AbortSignal.
;;;; Based on test specs from tests/cl-adapted/src/infra/abort-signal.test.lisp

(defpackage :cl-claw.infra.abort-signal
  (:use :cl)
  (:nicknames :cl-claw.abort)
  (:export :abort-controller
           :make-abort-controller
           :abort-signal-struct
           :make-abort-signal-struct
           :abort-signal-struct-aborted
           :abort-signal-struct-reason
           :abort-controller-signal
           :trigger-abort
           :wait-for-abort-signal))
(in-package :cl-claw.infra.abort-signal)

(defstruct abort-signal-struct
  "Represents a signal that can be aborted."
  (aborted nil :type boolean)
  (reason nil))

(defstruct abort-controller
  "Controller for creating and triggering abort signals."
  (signal (make-abort-signal-struct) :type abort-signal-struct))

(defun trigger-abort (controller &optional reason)
  "Abort the controller's signal with optional reason."
  (declare (type abort-controller controller))
  (let ((signal (abort-controller-signal controller)))
    (setf (abort-signal-struct-aborted signal) t)
    (setf (abort-signal-struct-reason signal) reason)))

(defun wait-for-abort-signal (signal &key (timeout nil) (poll-interval 0.01))
  "Wait for an abort signal to become aborted.

If SIGNAL is nil, returns immediately.
If SIGNAL is already aborted, returns immediately.
Otherwise, polls until the signal becomes aborted or timeout is reached.

Returns :aborted when the signal was aborted, or :timeout if timeout was reached."
  (declare (type (or null abort-signal-struct) signal)
           (type (or null real) timeout)
           (type real poll-interval))
  (cond
    ((null signal) :ok)
    ((abort-signal-struct-aborted signal) :ok)
    (t
     (let ((start-time (get-internal-real-time))
           (timeout-internal (when timeout (* timeout internal-time-units-per-second))))
       (loop
         (when (abort-signal-struct-aborted signal)
           (return :aborted))
         (when (and timeout-internal
                    (> (- (get-internal-real-time) start-time) timeout-internal))
           (return :timeout))
         (sleep poll-interval))))))
