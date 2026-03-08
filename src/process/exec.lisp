;;;; exec.lisp — Command execution with timeouts and environment management
;;;;
;;;; Implements runCommandWithTimeout (CL: RUN-COMMAND-WITH-TIMEOUT) and
;;;; helpers for env merging and shell-spawn decisions.

(defpackage :cl-claw.process.exec
  (:use :cl)
  (:export
   :resolve-command-env
   :should-spawn-with-shell
   :run-command-with-timeout
   :run-exec
   :termination-result
   :termination-result-code
   :termination-result-stdout
   :termination-result-stderr
   :termination-result-termination
   :termination-result-no-output-timed-out))

(in-package :cl-claw.process.exec)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Data types ──────────────────────────────────────────────────────────────

(defstruct termination-result
  "Result of running a command to termination."
  (code            0     :type (or integer null))
  (stdout          ""    :type string)
  (stderr          ""    :type string)
  (termination     :exit :type keyword)
  (no-output-timed-out nil :type boolean))

;;; ─── Environment resolution ──────────────────────────────────────────────────

(declaim (ftype (function (list) list) filter-env-pairs))
(defun filter-env-pairs (pairs)
  "Remove entries whose value is NIL from PAIRS (a plist-style alist)."
  (declare (type list pairs))
  (remove-if (lambda (pair)
               (null (cdr pair)))
             pairs))

(declaim (ftype (function (&key (:argv list)
                                (:base-env list)
                                (:env list))
                          list)
                resolve-command-env))
(defun resolve-command-env (&key argv base-env env)
  "Merge BASE-ENV with ENV, dropping NIL values.
If ARGV starts with 'npm', also sets NPM_CONFIG_FUND=false.
Returns an alist of (key . value) string pairs."
  (declare (type list argv base-env env))
  (let* ((merged (append base-env env))
         (filtered (filter-env-pairs merged))
         (is-npm (and argv
                      (stringp (car argv))
                      (string= (car argv) "npm"))))
    (declare (type list merged filtered)
             (type boolean is-npm))
    (if is-npm
        (append filtered
                '(("NPM_CONFIG_FUND" . "false")
                  ("npm_config_fund" . "false")))
        filtered)))

;;; ─── Shell-spawn decision ────────────────────────────────────────────────────

(declaim (ftype (function (&key (:resolved-command string)
                                (:platform string))
                          boolean)
                should-spawn-with-shell))
(defun should-spawn-with-shell (&key resolved-command platform)
  "Returns NIL always — shell execution is disabled for security (Windows cmd.exe injection).
RESOLVED-COMMAND and PLATFORM are accepted but not used."
  (declare (type string resolved-command platform)
           (ignore resolved-command platform))
  nil)

;;; ─── Command execution ───────────────────────────────────────────────────────

(declaim (ftype (function (list &key (:timeout-ms (or fixnum null))
                                     (:no-output-timeout-ms (or fixnum null)))
                          termination-result)
                run-command-with-timeout))
(defun run-command-with-timeout (argv &key timeout-ms no-output-timeout-ms)
  "Run ARGV as a subprocess with optional overall and no-output timeouts.
Returns a TERMINATION-RESULT struct."
  (declare (type list argv)
           (type (or fixnum null) timeout-ms no-output-timeout-ms))
  (let ((command (car argv))
        (args    (cdr argv)))
    (declare (type string command)
             (type list args))
    (let* ((stdout-parts '())
           (stderr-parts '())
           (last-output-time (get-internal-real-time))
           (start-time (get-internal-real-time))
           (timed-out nil)
           (no-output-timed-out nil))
      (declare (type list stdout-parts stderr-parts)
               (type fixnum last-output-time start-time)
               (type boolean timed-out no-output-timed-out))
      (handler-case
          (let* ((process (uiop:launch-program
                           (cons command args)
                           :output :stream
                           :error-output :stream
                           :wait nil))
                 (out-stream (uiop:process-info-output process))
                 (err-stream (uiop:process-info-error-output process))
                 (poll-interval 0.005))
            (declare (type t process out-stream err-stream)
                     (type float poll-interval))
            (block poll-loop
              (tagbody
               poll-start
               ;; Check timeouts
               (let* ((now (get-internal-real-time))
                      (elapsed-ms (round (* 1000 (/ (- now start-time)
                                                    internal-time-units-per-second))))
                      (since-output-ms (round (* 1000 (/ (- now last-output-time)
                                                          internal-time-units-per-second)))))
                 (declare (type fixnum elapsed-ms since-output-ms))
                 ;; Global timeout check
                 (when (and timeout-ms (>= elapsed-ms timeout-ms))
                   (setf timed-out t)
                   (ignore-errors (uiop:terminate-process process))
                   (return-from poll-loop))
                 ;; No-output timeout check
                 (when (and no-output-timeout-ms (>= since-output-ms no-output-timeout-ms))
                   (setf no-output-timed-out t)
                   (ignore-errors (uiop:terminate-process process))
                   (return-from poll-loop)))
               ;; Read available output
               (when out-stream
                 (loop while (listen out-stream)
                       do (let ((line (read-line out-stream nil nil)))
                            (when line
                              (push line stdout-parts)
                              (setf last-output-time (get-internal-real-time))))))
               (when err-stream
                 (loop while (listen err-stream)
                       do (let ((line (read-line err-stream nil nil)))
                            (when line
                              (push line stderr-parts)
                              (setf last-output-time (get-internal-real-time))))))
               ;; Check if process exited
               (when (uiop:process-alive-p process)
                 (sleep poll-interval)
                 (go poll-start))
               ;; Process exited — fall through
               ))
            ;; Collect remaining output
            (when out-stream
              (loop for line = (read-line out-stream nil nil)
                    while line do (push line stdout-parts)))
            (when err-stream
              (loop for line = (read-line err-stream nil nil)
                    while line do (push line stderr-parts)))
            (let ((code (uiop:wait-process process)))
              (declare (type (or integer null) code))
              (make-termination-result
               :code code
               :stdout (format nil "~{~a~%~}" (reverse stdout-parts))
               :stderr (format nil "~{~a~%~}" (reverse stderr-parts))
               :termination (cond (no-output-timed-out :no-output-timeout)
                                  (timed-out           :timeout)
                                  (t                   :exit))
               :no-output-timed-out no-output-timed-out)))
        (error (c)
          (make-termination-result
           :code 1
           :stdout ""
           :stderr (format nil "~a" c)
           :termination :error
           :no-output-timed-out nil))))))

(declaim (ftype (function (list &key (:env list)) termination-result) run-exec))
(defun run-exec (argv &key env)
  "Run ARGV synchronously (no timeout). ENV is an alist of extra env vars."
  (declare (type list argv)
           (type list env))
  (declare (ignore env))
  (run-command-with-timeout argv))
