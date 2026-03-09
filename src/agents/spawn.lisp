;;;; spawn.lisp — Agent spawn: ACP direct, thread binding, stream relay
;;;;
;;;; Handles spawning ACP agents (direct and via thread binding), parent stream
;;;; relay for sub-agents, and inline delivery coordination.

(defpackage :cl-claw.agents.spawn
  (:use :cl :cl-claw.acp.types)
  (:export
   ;; Spawn config
   :make-spawn-config
   :spawn-config
   :spawn-config-agent-id
   :spawn-config-session-key
   :spawn-config-cwd
   :spawn-config-backend
   :spawn-config-mode
   :spawn-config-parent-session-key
   ;; Thread binding
   :make-thread-binding
   :thread-binding
   :thread-binding-thread-id
   :thread-binding-channel
   :thread-binding-session-key
   ;; Spawn operations
   :resolve-spawn-session-key
   :build-spawn-env
   ;; Stream relay
   :make-stream-relay
   :stream-relay
   :stream-relay-parent-key
   :stream-relay-child-key
   :stream-relay-buffer
   :relay-append
   :relay-flush
   :relay-closed-p
   :relay-close))

(in-package :cl-claw.agents.spawn)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Spawn Config ───────────────────────────────────────────────────────────

(defstruct (spawn-config (:conc-name spawn-config-))
  "Configuration for spawning an ACP agent."
  (agent-id "" :type string)
  (session-key "" :type string)
  (cwd "" :type string)
  (backend "acpx" :type string)
  (mode "persistent" :type string)
  (parent-session-key nil :type (or string null)))

;;; ─── Thread Binding ─────────────────────────────────────────────────────────

(defstruct (thread-binding (:conc-name thread-binding-))
  "Binding of a spawned agent to a channel thread."
  (thread-id "" :type string)
  (channel "" :type string)
  (session-key "" :type string))

;;; ─── Session Key Resolution ─────────────────────────────────────────────────

(declaim (ftype (function (string &key (:parent-key (or string null))
                                       (:label string))
                          string)
                resolve-spawn-session-key))
(defun resolve-spawn-session-key (agent-id &key parent-key (label ""))
  "Build a session key for a spawned agent.
   If PARENT-KEY is given, creates a sub-agent key."
  (declare (type string agent-id label)
           (type (or string null) parent-key))
  (let ((base (string-downcase (string-trim '(#\Space #\Tab) agent-id))))
    (declare (type string base))
    (cond
      ((and parent-key (not (string= label "")))
       (format nil "~A:subagent:~A:~A" parent-key base label))
      (parent-key
       (format nil "~A:subagent:~A" parent-key base))
      ((not (string= label ""))
       (format nil "agent:~A:acp:~A" base label))
      (t
       (format nil "agent:~A:acp:direct" base)))))

;;; ─── Spawn Environment ──────────────────────────────────────────────────────

(declaim (ftype (function (spawn-config &key (:base-env (or hash-table null))) hash-table)
                build-spawn-env))
(defun build-spawn-env (config &key base-env)
  "Build the environment for a spawned agent process."
  (declare (type spawn-config config)
           (type (or hash-table null) base-env))
  (let ((env (make-hash-table :test 'equal)))
    ;; Copy base env
    (when base-env
      (maphash (lambda (k v) (setf (gethash k env) v)) base-env))
    ;; Set spawn-specific vars
    (setf (gethash "OPENCLAW_SHELL" env) "acp-client"
          (gethash "OPENCLAW_AGENT_ID" env) (spawn-config-agent-id config)
          (gethash "OPENCLAW_SESSION_KEY" env) (spawn-config-session-key config)
          (gethash "OPENCLAW_CWD" env) (spawn-config-cwd config))
    ;; Parent session key for sub-agents
    (let ((parent (spawn-config-parent-session-key config)))
      (when parent
        (setf (gethash "OPENCLAW_PARENT_SESSION_KEY" env) parent)))
    env))

;;; ─── Stream Relay ───────────────────────────────────────────────────────────

(defstruct (stream-relay (:conc-name stream-relay-))
  "Relay for streaming output from a child agent to a parent session."
  (parent-key "" :type string)
  (child-key "" :type string)
  (buffer (make-array 0 :element-type 'string :adjustable t :fill-pointer 0) :type vector)
  (closed nil :type boolean)
  (lock (bt:make-lock "stream-relay") :type t))

(declaim (ftype (function (stream-relay string) null) relay-append))
(defun relay-append (relay chunk)
  "Append a chunk to the relay buffer."
  (declare (type stream-relay relay) (type string chunk))
  (bt:with-lock-held ((stream-relay-lock relay))
    (unless (stream-relay-closed relay)
      (vector-push-extend chunk (stream-relay-buffer relay))))
  nil)

(declaim (ftype (function (stream-relay) list) relay-flush))
(defun relay-flush (relay)
  "Flush and return all buffered chunks."
  (declare (type stream-relay relay))
  (bt:with-lock-held ((stream-relay-lock relay))
    (let ((chunks (coerce (stream-relay-buffer relay) 'list)))
      (setf (fill-pointer (stream-relay-buffer relay)) 0)
      chunks)))

(declaim (ftype (function (stream-relay) boolean) relay-closed-p))
(defun relay-closed-p (relay)
  "Check if the relay is closed."
  (declare (type stream-relay relay))
  (stream-relay-closed relay))

(declaim (ftype (function (stream-relay) null) relay-close))
(defun relay-close (relay)
  "Close the relay."
  (declare (type stream-relay relay))
  (bt:with-lock-held ((stream-relay-lock relay))
    (setf (stream-relay-closed relay) t))
  nil)
