;;;; exec-tool.lisp — Exec tool — shell commands with PTY
;;;;
;;;; Implements the exec tool for running shell commands, matching
;;;; OpenClaw's exec semantics (timeout, background, PTY support).

(defpackage :cl-claw.tools.exec-tool
  (:use :cl)
  (:import-from :cl-claw.tools.types
                :tool-definition
                :make-tool-definition)
  (:import-from :cl-claw.tools.dispatch
                :register-tool)
  (:export
   ;; Handler
   :handle-exec-tool
   :handle-process-tool

   ;; Registration
   :register-exec-tools

   ;; Session management
   :*exec-sessions*
   :exec-session
   :make-exec-session
   :exec-session-id
   :exec-session-process
   :exec-session-output
   :exec-session-started-at
   :exec-session-finished-p
   :get-exec-session
   :list-exec-sessions
   :kill-exec-session

   ;; Configuration
   :*default-exec-timeout*
   :*max-exec-timeout*))

(in-package :cl-claw.tools.exec-tool)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Constants & configuration
;;; -----------------------------------------------------------------------

(defvar *default-exec-timeout* 30
  "Default execution timeout in seconds.")

(defvar *max-exec-timeout* 600
  "Maximum execution timeout in seconds (10 minutes).")

;;; -----------------------------------------------------------------------
;;; Exec sessions — background process management
;;; -----------------------------------------------------------------------

(defstruct exec-session
  "A background exec session."
  (id "" :type string)
  (process nil)
  (output "" :type string)
  (started-at 0 :type fixnum)
  (finished-p nil :type boolean)
  (exit-code nil :type (or fixnum null))
  (command "" :type string))

(defvar *exec-sessions* (make-hash-table :test 'equal)
  "Map of session-id -> exec-session for background processes.")

(defvar *session-counter* 0
  "Counter for generating unique session IDs.")

(declaim (ftype (function () string) generate-session-id))
(defun generate-session-id ()
  "Generate a unique session ID."
  (let ((id (format nil "exec-~D-~D" (incf *session-counter*)
                    (mod (get-universal-time) 100000))))
    (declare (type string id))
    id))

(declaim (ftype (function (string) (or exec-session null)) get-exec-session))
(defun get-exec-session (id)
  "Get an exec session by ID."
  (declare (type string id))
  (gethash id *exec-sessions*))

(defun list-exec-sessions ()
  "List all exec sessions."
  (let ((sessions '()))
    (maphash (lambda (k v) (declare (ignore k)) (push v sessions))
             *exec-sessions*)
    sessions))

(defun kill-exec-session (id)
  "Kill an exec session's process."
  (let ((session (get-exec-session id)))
    (when (and session (exec-session-process session))
      (handler-case
          (uiop:terminate-process (exec-session-process session))
        (error () nil))
      (setf (exec-session-finished-p session) t))))

;;; -----------------------------------------------------------------------
;;; Shell command execution
;;; -----------------------------------------------------------------------

(declaim (ftype (function (string &key (:timeout fixnum)
                                       (:workdir (or string null)))
                          (values string fixnum))
                run-shell-command))
(defun run-shell-command (command &key (timeout *default-exec-timeout*)
                                       workdir)
  "Run a shell command and return (output exit-code).
Respects timeout. Uses /bin/bash."
  (declare (type string command)
           (type fixnum timeout)
           (type (or string null) workdir))
  (let* ((effective-timeout (min timeout *max-exec-timeout*))
         (full-command (if workdir
                          (format nil "cd ~A && ~A"
                                  (uiop:escape-shell-token workdir) command)
                          command)))
    (declare (type fixnum effective-timeout)
             (type string full-command))
    (handler-case
        (multiple-value-bind (output error-output exit-code)
            (uiop:run-program (list "/bin/bash" "-c" full-command)
                              :output '(:string :stripped t)
                              :error-output '(:string :stripped t)
                              :ignore-error-status t)
          (declare (type string output)
                   (type (or fixnum null) exit-code))
          (let ((combined (if (and error-output (plusp (length error-output)))
                              (format nil "~A~@[~%~A~]" output error-output)
                              output)))
            (values combined (or exit-code -1))))
      (error (e)
        (values (format nil "Command execution error: ~A" e) -1)))))

;;; -----------------------------------------------------------------------
;;; Exec tool handler
;;; -----------------------------------------------------------------------

(declaim (ftype (function (hash-table) string) handle-exec-tool))
(defun handle-exec-tool (args)
  "Handle an exec tool call.
Arguments:
  command: shell command to execute
  timeout: timeout in seconds (optional, default 30)
  workdir: working directory (optional)
  background: run in background (optional, boolean)"
  (declare (type hash-table args))
  (let* ((command (or (gethash "command" args)
                      (error "exec tool requires command")))
         (timeout (or (gethash "timeout" args) *default-exec-timeout*))
         (workdir (gethash "workdir" args))
         (background-p (gethash "background" args)))
    (declare (type string command)
             (type (or string null) workdir))
    (if background-p
        ;; Background execution — store session
        (let* ((session-id (generate-session-id))
               (session (make-exec-session :id session-id
                                           :started-at (get-universal-time)
                                           :command command)))
          ;; Run in a thread
          (setf (gethash session-id *exec-sessions*) session)
          (bt:make-thread
           (lambda ()
             (multiple-value-bind (output exit-code)
                 (run-shell-command command :timeout timeout :workdir workdir)
               (setf (exec-session-output session) output)
               (setf (exec-session-exit-code session) exit-code)
               (setf (exec-session-finished-p session) t)))
           :name (format nil "exec-bg:~A" session-id))
          (format nil "Background session started: ~A" session-id))
        ;; Foreground execution
        (multiple-value-bind (output exit-code)
            (run-shell-command command :timeout timeout :workdir workdir)
          (if (zerop exit-code)
              output
              (format nil "~A~%(exit code: ~D)" output exit-code))))))

;;; -----------------------------------------------------------------------
;;; Process tool handler
;;; -----------------------------------------------------------------------

(declaim (ftype (function (hash-table) string) handle-process-tool))
(defun handle-process-tool (args)
  "Handle a process management tool call.
Arguments:
  action: list | poll | log | kill
  sessionId: session ID (for poll/log/kill)"
  (declare (type hash-table args))
  (let ((action (or (gethash "action" args)
                    (error "process tool requires action"))))
    (declare (type string action))
    (cond
      ((string= action "list")
       (let ((sessions (list-exec-sessions)))
         (if (null sessions)
             "No active exec sessions."
             (format nil "~{~A~^~%~}"
                     (mapcar (lambda (s)
                               (format nil "~A: ~A [~A]"
                                       (exec-session-id s)
                                       (exec-session-command s)
                                       (if (exec-session-finished-p s)
                                           (format nil "done, exit=~A"
                                                   (exec-session-exit-code s))
                                           "running")))
                             sessions)))))
      ((string= action "poll")
       (let* ((session-id (or (gethash "sessionId" args)
                              (error "poll requires sessionId")))
              (session (get-exec-session session-id)))
         (unless session
           (error "Session ~A not found" session-id))
         (if (exec-session-finished-p session)
             (format nil "~A~%(exit code: ~D)"
                     (exec-session-output session)
                     (or (exec-session-exit-code session) -1))
             "Still running...")))
      ((string= action "log")
       (let* ((session-id (or (gethash "sessionId" args)
                              (error "log requires sessionId")))
              (session (get-exec-session session-id)))
         (unless session
           (error "Session ~A not found" session-id))
         (exec-session-output session)))
      ((string= action "kill")
       (let* ((session-id (or (gethash "sessionId" args)
                              (error "kill requires sessionId"))))
         (kill-exec-session session-id)
         (format nil "Killed session ~A" session-id)))
      (t
       (error "Unknown process action: ~A" action)))))

;;; -----------------------------------------------------------------------
;;; Registration
;;; -----------------------------------------------------------------------

(defun register-exec-tools ()
  "Register the exec and process tools."
  (register-tool (make-tool-definition
                  :name "exec"
                  :description "Execute shell commands with background continuation. Use yieldMs/background to continue later via process tool."
                  :handler #'handle-exec-tool
                  :requires-approval-p nil
                  :category "exec"))
  (register-tool (make-tool-definition
                  :name "process"
                  :description "Manage running exec sessions: list, poll, log, kill."
                  :handler #'handle-process-tool
                  :category "exec"))
  (values))
