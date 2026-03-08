;;;; spawn-utils.lisp — Process spawn with EBADF fallback and restart-recovery hook
;;;;
;;;; Provides SPAWN-WITH-FALLBACK (retries with fallback options on EBADF)
;;;; and CREATE-RESTART-ITERATION-HOOK (tracks restart iterations).

(defpackage :cl-claw.process.spawn-utils
  (:use :cl)
  (:export
   :spawn-with-fallback
   :spawn-result
   :spawn-result-process
   :spawn-result-used-fallback
   :spawn-result-fallback-label
   :create-restart-iteration-hook))

(in-package :cl-claw.process.spawn-utils)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Data types ──────────────────────────────────────────────────────────────

(defstruct spawn-result
  "Result of SPAWN-WITH-FALLBACK."
  (process      nil  :type t)
  (used-fallback nil  :type boolean)
  (fallback-label ""  :type string))

;;; ─── EBADF detection ─────────────────────────────────────────────────────────

(declaim (ftype (function (t) boolean) ebadf-error-p))
(defun ebadf-error-p (condition)
  "Return T if CONDITION represents an EBADF spawn error."
  (declare (type t condition))
  (let ((msg (format nil "~a" condition)))
    (declare (type string msg))
    (not (null (or (search "EBADF" msg)
                   (search "ebadf" msg))))))

;;; ─── Spawn with fallback ─────────────────────────────────────────────────────

(declaim (ftype (function (&key (:argv list)
                                (:options list)
                                (:fallbacks list)
                                (:spawn-impl (or function null)))
                          spawn-result)
                spawn-with-fallback))
(defun spawn-with-fallback (&key argv options fallbacks spawn-impl)
  "Attempt to spawn ARGV with OPTIONS. If EBADF is raised and FALLBACKS is non-nil,
retry once with the first fallback's options. Returns a SPAWN-RESULT.

ARGV: list of strings (command + args)
OPTIONS: plist of spawn options
FALLBACKS: list of (:label STRING :options PLIST) property lists
SPAWN-IMPL: (lambda (argv options) → process) — uses UIOP:LAUNCH-PROGRAM by default"
  (declare (type list argv options fallbacks)
           (type (or function null) spawn-impl))
  (let ((spawn-fn (or spawn-impl
                      (lambda (cmd opts)
                        (declare (ignore opts))
                        (uiop:launch-program cmd :wait nil)))))
    (declare (type function spawn-fn))
    ;; Try primary options
    (handler-case
        (let ((proc (funcall spawn-fn argv options)))
          (make-spawn-result
           :process proc
           :used-fallback nil
           :fallback-label ""))
      (error (c)
        ;; If EBADF and we have fallbacks, retry with the first fallback
        (if (and (ebadf-error-p c) fallbacks)
            (let* ((fallback (car fallbacks))
                   (fb-label (getf fallback :label ""))
                   (fb-opts  (getf fallback :options '())))
              (declare (type string fb-label)
                       (type list fb-opts))
              (let ((proc (funcall spawn-fn argv fb-opts)))
                (make-spawn-result
                 :process proc
                 :used-fallback t
                 :fallback-label fb-label)))
            ;; Re-raise for non-EBADF or no fallbacks
            (error c))))))

;;; ─── Restart iteration hook ──────────────────────────────────────────────────

(declaim (ftype (function (function) function) create-restart-iteration-hook))
(defun create-restart-iteration-hook (on-restart)
  "Return a thunk that returns NIL on first call (skip recovery) and T on
subsequent calls (run ON-RESTART before returning T).

ON-RESTART: (lambda () ...) — called on the 2nd+ invocation"
  (declare (type function on-restart))
  (let ((first-call t))
    (declare (type boolean first-call))
    (lambda ()
      (if first-call
          (progn
            (setf first-call nil)
            nil)
          (progn
            (funcall on-restart)
            t)))))
