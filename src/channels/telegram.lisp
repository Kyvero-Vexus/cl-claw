;;;; telegram.lisp — Telegram channel mapping helpers

(defpackage :cl-claw.channels.telegram
  (:use :cl)
  (:import-from :cl-claw.routing
                :route-entry
                :make-route-entry
                :make-session-key)
  (:export
   :telegram-update->route-entry
   :telegram-session-key
   :telegram-route->send-payload))

(in-package :cl-claw.channels.telegram)

(declaim (optimize (safety 3) (debug 3)))

(declaim (ftype (function (hash-table &key (:account (or string null)) (:agent-id (or string null))) route-entry)
                telegram-update->route-entry))
(defun telegram-update->route-entry (update &key (account "default") (agent-id "main"))
  (declare (type hash-table update)
           (type (or string null) account agent-id))
  (let* ((chat-id (format nil "~a" (gethash "chatId" update "unknown")))
         (thread-id (when (gethash "threadId" update)
                      (format nil "~a" (gethash "threadId" update)))))
    (declare (type string chat-id)
             (type (or string null) thread-id))
    (make-route-entry :provider "telegram"
                      :account (or account "default")
                      :target chat-id
                      :thread thread-id
                      :agent-id (or agent-id "main"))))

(declaim (ftype (function (hash-table &key (:account (or string null)) (:agent-id (or string null))) string)
                telegram-session-key))
(defun telegram-session-key (update &key (account "default") (agent-id "main"))
  (declare (type hash-table update)
           (type (or string null) account agent-id))
  (let ((route (telegram-update->route-entry update :account account :agent-id agent-id)))
    (declare (type route-entry route))
    (make-session-key "telegram"
                      (cl-claw.routing:route-entry-account route)
                      (cl-claw.routing:route-entry-target route)
                      :thread (cl-claw.routing:route-entry-thread route)
                      :agent-id (cl-claw.routing:route-entry-agent-id route))))

(declaim (ftype (function (route-entry string) hash-table) telegram-route->send-payload))
(defun telegram-route->send-payload (route text)
  (declare (type route-entry route)
           (type string text))
  (let ((payload (make-hash-table :test 'equal)))
    (declare (type hash-table payload))
    (setf (gethash "chat_id" payload) (cl-claw.routing:route-entry-target route)
          (gethash "text" payload) text)
    (let ((thread (cl-claw.routing:route-entry-thread route)))
      (declare (type (or string null) thread))
      (when thread
        (setf (gethash "message_thread_id" payload) thread)))
    payload))