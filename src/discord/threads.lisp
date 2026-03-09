;;;; threads.lisp — Discord thread management & ACP bindings
;;;;
;;;; Manages Discord threads and provides thread binding for agents.

(defpackage :cl-claw.discord.threads
  (:use :cl)
  (:import-from :cl-claw.discord.rest-client
                :discord-client
                :dc-create-thread
                :dc-get-channel)
  (:export
   :discord-thread-binding
   :make-discord-thread-binding
   :discord-thread-binding-channel-id
   :discord-thread-binding-thread-id
   :discord-thread-binding-agent-id

   :*discord-thread-bindings*
   :register-discord-thread-binding
   :resolve-discord-thread-binding
   :clear-discord-thread-bindings

   :create-agent-thread
   :is-thread-p))

(in-package :cl-claw.discord.threads)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Thread bindings
;;; -----------------------------------------------------------------------

(defstruct discord-thread-binding
  "Binds a Discord thread to an agent."
  (channel-id "" :type string)
  (thread-id "" :type string)
  (agent-id "main" :type string))

(defvar *discord-thread-bindings* (make-hash-table :test 'equal)
  "Map from thread-id -> discord-thread-binding.")

(defun register-discord-thread-binding (thread-id agent-id &key (channel-id ""))
  "Register a thread-to-agent binding."
  (declare (type string thread-id agent-id channel-id))
  (setf (gethash thread-id *discord-thread-bindings*)
        (make-discord-thread-binding :channel-id channel-id
                                      :thread-id thread-id
                                      :agent-id agent-id))
  (values))

(defun resolve-discord-thread-binding (thread-id)
  "Resolve the agent ID for a Discord thread."
  (declare (type string thread-id))
  (let ((binding (gethash thread-id *discord-thread-bindings*)))
    (when binding
      (discord-thread-binding-agent-id binding))))

(defun clear-discord-thread-bindings ()
  "Clear all Discord thread bindings."
  (clrhash *discord-thread-bindings*)
  (values))

;;; -----------------------------------------------------------------------
;;; Thread creation
;;; -----------------------------------------------------------------------

(defun create-agent-thread (client channel-id name agent-id &key message-id)
  "Create a new Discord thread and bind it to an agent."
  (declare (type discord-client client)
           (type string channel-id name agent-id))
  (multiple-value-bind (result ok)
      (dc-create-thread client channel-id name :message-id message-id)
    (when (and ok (hash-table-p result))
      (let ((thread-id (gethash "id" result)))
        (when thread-id
          (register-discord-thread-binding thread-id agent-id
                                           :channel-id channel-id)
          thread-id)))))

;;; -----------------------------------------------------------------------
;;; Thread detection
;;; -----------------------------------------------------------------------

(defun is-thread-p (channel-info)
  "Check if a channel is a thread based on its type."
  (declare (type hash-table channel-info))
  (let ((type (gethash "type" channel-info)))
    (member type '(10 11 12)))) ; PUBLIC_THREAD, PRIVATE_THREAD, ANNOUNCEMENT_THREAD
