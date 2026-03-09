;;;; restart.lisp - Gateway process restart utilities for cl-claw
;;;;
;;;; Provides functions to find and clean up stale gateway processes
;;;; using lsof to identify processes listening on the gateway port.

(defpackage :cl-claw.infra.restart
  (:use :cl)
  (:export :find-gateway-pids-on-port-sync
           :clean-stale-gateway-processes-sync
           :parse-pids-from-lsof-output))
(in-package :cl-claw.infra.restart)

(declaim (optimize (safety 3) (debug 3)))

(declaim (ftype (function (string (integer 0) &key (:timeout-ms (integer 0))) (values string integer t)) run-lsof))
(defun run-lsof (lsof-path port &key (timeout-ms 2000))
  "Run lsof to find processes listening on PORT.
Returns (values stdout exit-status error) where error is NIL on success."
  (declare (type string lsof-path)
           (type (integer 0) port))
  (handler-case
      (let ((output (uiop:run-program
                     (list lsof-path "-nP"
                           (format nil "-iTCP:~a" port)
                           "-sTCP:LISTEN"
                           "-Fpc")
                     :output :string
                     :ignore-error-status t
                     :error-output :string
                     :timeout (/ timeout-ms 1000.0))))
        (values output 0 nil))
    (error (e)
      (values "" 1 e))))

(declaim (ftype (function (string &key (:current-pid (or null integer))) list) parse-pids-from-lsof-output))
(defun parse-pids-from-lsof-output (stdout &key (current-pid nil))
  "Parse lsof -Fpc output and return PIDs of openclaw gateway processes.

The -Fpc format produces alternating lines:
  pPID   (process PID)
  cCOMMAND (process command/name)

Filters out the current process (CURRENT-PID) and non-openclaw processes."
  (declare (type string stdout))
  (let ((lines (uiop:split-string stdout :separator '(#\Newline)))
        (pids '())
        (current-pid-num (or current-pid (sb-posix:getpid)))
        (current-cmd nil)
        (current-entry-pid nil))
    (dolist (line lines)
      (when (and (> (length line) 1))
        (cond
          ((char= (char line 0) #\p)
           ;; PID line: "pNNNN"
           (let ((pid-str (subseq line 1)))
             (handler-case
                 (let ((pid (parse-integer pid-str)))
                   (setf current-entry-pid pid)
                   (setf current-cmd nil))
               (error () (setf current-entry-pid nil)))))
          ((char= (char line 0) #\c)
           ;; Command line: "cCOMMAND"
           (setf current-cmd (string-downcase (subseq line 1)))
           ;; Check if this pid+cmd combination is a valid openclaw gateway
           (when (and current-entry-pid
                      current-cmd
                      (/= current-entry-pid current-pid-num)
                      (search "openclaw" current-cmd))
             (push current-entry-pid pids))))))
    (nreverse pids)))

(declaim (ftype (function ((integer 0) &key (:lsof-command string) (:timeout-ms (integer 0))) list) find-gateway-pids-on-port-sync))
(defun find-gateway-pids-on-port-sync (port &key (lsof-command "/usr/sbin/lsof") (timeout-ms 2000))
  "Find PIDs of openclaw gateway processes listening on PORT.

Returns a list of PIDs. Returns empty list if lsof fails or is unavailable.
On Windows (non-Unix), returns empty list."
  (declare (type (integer 0) port))
  #+(or win32 windows)
  (return-from find-gateway-pids-on-port-sync '())
  (multiple-value-bind (stdout exit-status error)
      (run-lsof lsof-command port :timeout-ms timeout-ms)
    (declare (ignore exit-status error))
    (parse-pids-from-lsof-output stdout)))

(defparameter *sleep-sync-override* nil
  "Override for sleep function, used in tests.")

(declaim (ftype (function (real) t) sleep-ms))
(defun sleep-ms (ms)
  "Sleep for MS milliseconds, respecting any test override."
  (if *sleep-sync-override*
      (funcall *sleep-sync-override* ms)
      (sleep (/ ms 1000.0))))

(declaim (ftype (function (&optional (or null (integer 0))) list) clean-stale-gateway-processes-sync))
(defun clean-stale-gateway-processes-sync (&optional port)
  "Find and kill stale gateway processes on the gateway port.

If PORT is provided, uses that port; otherwise resolves the default gateway port.
Sends SIGTERM then SIGKILL to stale processes.
Returns the list of PIDs that were targeted."
  #+(or win32 windows)
  (return-from clean-stale-gateway-processes-sync '())
  (let* ((effective-port (or port 18789))
         (pids (find-gateway-pids-on-port-sync effective-port)))
    (when pids
      ;; Send SIGTERM first
      (dolist (pid pids)
        (handler-case
            (sb-posix:kill pid sb-posix:sigterm)
          (error () nil)))
      ;; Brief wait
      (sleep-ms 200)
      ;; Send SIGKILL
      (dolist (pid pids)
        (handler-case
            (sb-posix:kill pid sb-posix:sigkill)
          (error () nil))))
    pids))
