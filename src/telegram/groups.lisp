;;;; groups.lisp — Telegram groups/topics
;;;;
;;;; Handles Telegram group and topic (forum) message routing,
;;;; thread binding, and topic management.

(defpackage :cl-claw.telegram.groups
  (:use :cl)
  (:import-from :cl-claw.channel-protocol.types
                :normalized-message
                :normalized-message-target
                :normalized-message-thread
                :normalized-message-is-group-p
                :normalized-message-is-mention-p
                :normalized-message-sender-name
                :normalized-message-text)
  (:export
   ;; Topic management
   :extract-topic-thread-id
   :is-forum-message-p
   :build-group-sender-prefix

   ;; Thread binding
   :thread-binding
   :make-thread-binding
   :thread-binding-chat-id
   :thread-binding-thread-id
   :thread-binding-agent-id

   ;; Thread binding store
   :*thread-bindings*
   :register-thread-binding
   :resolve-thread-binding
   :remove-thread-binding
   :clear-thread-bindings
   :list-thread-bindings

   ;; Group message helpers
   :should-respond-in-group-p))

(in-package :cl-claw.telegram.groups)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Forum/topic helpers
;;; -----------------------------------------------------------------------

(declaim (ftype (function (hash-table) (or string null)) extract-topic-thread-id))
(defun extract-topic-thread-id (raw-message)
  "Extract the forum topic thread ID from a raw Telegram message."
  (declare (type hash-table raw-message))
  (let ((thread-id (gethash "message_thread_id" raw-message)))
    (when thread-id
      (format nil "~A" thread-id))))

(declaim (ftype (function (hash-table) boolean) is-forum-message-p))
(defun is-forum-message-p (raw-message)
  "Check if a raw Telegram message is from a forum topic."
  (declare (type hash-table raw-message))
  (let ((is-topic (gethash "is_topic_message" raw-message))
        (thread-id (gethash "message_thread_id" raw-message)))
    (or (and is-topic (not (null is-topic)))
        (not (null thread-id)))))

;;; -----------------------------------------------------------------------
;;; Sender prefix for group messages
;;; -----------------------------------------------------------------------

(declaim (ftype (function (normalized-message) string) build-group-sender-prefix))
(defun build-group-sender-prefix (msg)
  "Build a sender prefix for group messages.
Returns e.g. '[username] ' for group messages, '' for DMs."
  (declare (type normalized-message msg))
  (if (normalized-message-is-group-p msg)
      (let ((name (normalized-message-sender-name msg)))
        (if (plusp (length name))
            (format nil "[~A] " name)
            ""))
      ""))

;;; -----------------------------------------------------------------------
;;; Thread bindings — map topics to agents
;;; -----------------------------------------------------------------------

(defstruct thread-binding
  "Binds a Telegram chat+thread to a specific agent."
  (chat-id "" :type string)
  (thread-id "" :type string)
  (agent-id "main" :type string))

(defvar *thread-bindings* (make-hash-table :test 'equal)
  "Map from 'chat-id:thread-id' -> thread-binding.")

(defun binding-key (chat-id thread-id)
  "Generate a store key from chat and thread IDs."
  (format nil "~A:~A" chat-id thread-id))

(defun register-thread-binding (chat-id thread-id agent-id)
  "Register a thread binding."
  (declare (type string chat-id thread-id agent-id))
  (let ((binding (make-thread-binding :chat-id chat-id
                                       :thread-id thread-id
                                       :agent-id agent-id)))
    (setf (gethash (binding-key chat-id thread-id) *thread-bindings*) binding))
  (values))

(defun resolve-thread-binding (chat-id thread-id)
  "Resolve the agent ID for a thread binding.
Returns the agent-id string or nil if no binding exists."
  (declare (type string chat-id thread-id))
  (let ((binding (gethash (binding-key chat-id thread-id) *thread-bindings*)))
    (when binding
      (thread-binding-agent-id binding))))

(defun remove-thread-binding (chat-id thread-id)
  "Remove a thread binding."
  (declare (type string chat-id thread-id))
  (remhash (binding-key chat-id thread-id) *thread-bindings*)
  (values))

(defun clear-thread-bindings ()
  "Clear all thread bindings."
  (clrhash *thread-bindings*)
  (values))

(defun list-thread-bindings ()
  "List all thread bindings."
  (let ((bindings '()))
    (maphash (lambda (k v) (declare (ignore k)) (push v bindings))
             *thread-bindings*)
    bindings))

;;; -----------------------------------------------------------------------
;;; Group response decision
;;; -----------------------------------------------------------------------

(declaim (ftype (function (normalized-message &key (:bot-username string)
                                                   (:always-respond-in-dms boolean))
                          boolean)
                should-respond-in-group-p))
(defun should-respond-in-group-p (msg &key (bot-username "")
                                           (always-respond-in-dms t))
  "Determine whether the bot should respond to a group message.
Returns T if:
- Message is a DM (and always-respond-in-dms is T)
- Message mentions the bot
- Message is a reply (handled by thread binding)
- Thread has an active binding"
  (declare (type normalized-message msg)
           (type string bot-username)
           (type boolean always-respond-in-dms))
  ;; DMs always get responses
  (when (and (not (normalized-message-is-group-p msg))
             always-respond-in-dms)
    (return-from should-respond-in-group-p t))
  ;; Mentions
  (when (normalized-message-is-mention-p msg)
    (return-from should-respond-in-group-p t))
  ;; Check thread binding
  (let ((thread (normalized-message-thread msg))
        (target (normalized-message-target msg)))
    (when (and thread
               (resolve-thread-binding target thread))
      (return-from should-respond-in-group-p t)))
  nil)
