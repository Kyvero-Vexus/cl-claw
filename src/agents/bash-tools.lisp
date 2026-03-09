;;;; bash-tools.lisp — Agent bash tools: exec, approval, Docker
;;;;
;;;; Bash process registry, Docker exec argument building, execution approval
;;;; flow, and exec runtime event handling.

(defpackage :cl-claw.agents.bash-tools
  (:use :cl)
  (:export
   ;; Process registry
   :make-process-registry
   :process-registry
   :registry-add-session
   :registry-get-session
   :registry-get-finished-session
   :registry-remove-session
   :registry-reset
   :registry-list-sessions
   ;; Process session
   :make-process-session
   :process-session
   :process-session-id
   :process-session-command
   :process-session-cwd
   :process-session-pid
   :process-session-backgrounded
   :process-session-exited
   :process-session-exit-code
   :process-session-output-buffer
   ;; Docker args
   :build-docker-exec-args
   ;; Approval
   :make-exec-approval-policy
   :exec-approval-policy
   :exec-requires-approval-p
   :create-process-tool))

(in-package :cl-claw.agents.bash-tools)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Process Session ────────────────────────────────────────────────────────

(defstruct (process-session (:conc-name process-session-))
  "A tracked bash process session."
  (id "" :type string)
  (command "" :type string)
  (cwd "" :type string)
  (pid 0 :type fixnum)
  (backgrounded nil :type boolean)
  (exited nil :type boolean)
  (exit-code -1 :type fixnum)
  (output-buffer (make-string-output-stream) :type stream)
  (created-at 0 :type fixnum))

;;; ─── Process Registry ───────────────────────────────────────────────────────

(defstruct (process-registry (:conc-name process-registry-))
  "Registry of tracked process sessions."
  (active (make-hash-table :test 'equal) :type hash-table)
  (finished (make-hash-table :test 'equal) :type hash-table)
  (lock (bt:make-lock "process-registry") :type t))

(declaim (ftype (function (process-registry process-session) null)
                registry-add-session))
(defun registry-add-session (registry session)
  "Add a process session to the registry."
  (declare (type process-registry registry)
           (type process-session session))
  (bt:with-lock-held ((process-registry-lock registry))
    (setf (gethash (process-session-id session)
                   (process-registry-active registry))
          session))
  nil)

(declaim (ftype (function (process-registry string) (or process-session null))
                registry-get-session))
(defun registry-get-session (registry session-id)
  "Get an active session by ID."
  (declare (type process-registry registry) (type string session-id))
  (gethash session-id (process-registry-active registry)))

(declaim (ftype (function (process-registry string) (or process-session null))
                registry-get-finished-session))
(defun registry-get-finished-session (registry session-id)
  "Get a finished session by ID."
  (declare (type process-registry registry) (type string session-id))
  (gethash session-id (process-registry-finished registry)))

(declaim (ftype (function (process-registry string) boolean) registry-remove-session))
(defun registry-remove-session (registry session-id)
  "Remove a session from active or finished. Returns T if found."
  (declare (type process-registry registry) (type string session-id))
  (bt:with-lock-held ((process-registry-lock registry))
    (or (not (null (remhash session-id (process-registry-active registry))))
        (not (null (remhash session-id (process-registry-finished registry)))))))

(declaim (ftype (function (process-registry) null) registry-reset))
(defun registry-reset (registry)
  "Clear all sessions."
  (declare (type process-registry registry))
  (bt:with-lock-held ((process-registry-lock registry))
    (clrhash (process-registry-active registry))
    (clrhash (process-registry-finished registry)))
  nil)

(declaim (ftype (function (process-registry) list) registry-list-sessions))
(defun registry-list-sessions (registry)
  "List all active session IDs."
  (declare (type process-registry registry))
  (let ((ids nil))
    (maphash (lambda (k v) (declare (ignore v)) (push k ids))
             (process-registry-active registry))
    ids))

;;; ─── Docker Exec Args ──────────────────────────────────────────────────────

(declaim (ftype (function (string string &key (:user string)
                                              (:workdir string)
                                              (:env list))
                          list)
                build-docker-exec-args))
(defun build-docker-exec-args (container-id command
                               &key (user "") (workdir "") (env nil))
  "Build the argument list for 'docker exec'."
  (declare (type string container-id command user workdir)
           (type list env))
  (let ((args (list "docker" "exec")))
    ;; Interactive + TTY
    (push "-it" args)
    ;; User
    (when (not (string= user ""))
      (push "-u" args)
      (push user args))
    ;; Working directory
    (when (not (string= workdir ""))
      (push "-w" args)
      (push workdir args))
    ;; Environment variables
    (dolist (env-pair env)
      (push "-e" args)
      (push env-pair args))
    ;; Container and command
    (push container-id args)
    (push "sh" args)
    (push "-c" args)
    (push command args)
    (nreverse args)))

;;; ─── Exec Approval ─────────────────────────────────────────────────────────

(defstruct (exec-approval-policy (:conc-name exec-approval-policy-))
  "Policy for exec command approval."
  (mode "auto" :type string)       ; "auto" | "always" | "never"
  (allowlist nil :type list)       ; list of allowed command prefixes
  (denylist nil :type list))       ; list of denied command patterns

(declaim (ftype (function (exec-approval-policy string) boolean)
                exec-requires-approval-p))
(defun exec-requires-approval-p (policy command)
  "Determine if a command requires explicit approval."
  (declare (type exec-approval-policy policy) (type string command))
  (let ((mode (exec-approval-policy-mode policy)))
    (cond
      ((string= mode "never") nil)
      ((string= mode "always") t)
      ;; auto mode: check allowlist/denylist
      (t
       (let ((cmd-lower (string-downcase command)))
         ;; Check denylist first
         (dolist (pattern (exec-approval-policy-denylist policy))
           (when (search (string-downcase pattern) cmd-lower)
             (return-from exec-requires-approval-p t)))
         ;; Check allowlist
         (dolist (prefix (exec-approval-policy-allowlist policy))
           (when (uiop:string-prefix-p (string-downcase prefix) cmd-lower)
             (return-from exec-requires-approval-p nil)))
         ;; Default: require approval
         t)))))

;;; ─── Process Tool ───────────────────────────────────────────────────────────

(defstruct (process-tool (:conc-name process-tool-))
  "The process management tool for agent bash operations."
  (registry nil :type (or process-registry null))
  (approval-policy nil :type (or exec-approval-policy null)))

(declaim (ftype (function (&key (:registry (or process-registry null))
                                (:approval-policy (or exec-approval-policy null)))
                          process-tool)
                create-process-tool))
(defun create-process-tool (&key registry approval-policy)
  "Create a new process tool."
  (declare (type (or process-registry null) registry)
           (type (or exec-approval-policy null) approval-policy))
  (make-process-tool
   :registry (or registry (make-process-registry))
   :approval-policy (or approval-policy (make-exec-approval-policy))))
