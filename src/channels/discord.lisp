;;;; discord.lisp — Discord channel mapping helpers

(defpackage :cl-claw.channels.discord
  (:use :cl)
  (:import-from :cl-claw.routing
                :route-entry
                :make-route-entry
                :make-session-key
                :route-entry-account
                :route-entry-target
                :route-entry-thread
                :route-entry-agent-id)
  (:export
   :discord-event->route-entry
   :discord-session-key
   :discord-route->send-payload))

(in-package :cl-claw.channels.discord)

(declaim (optimize (safety 3) (debug 3)))

(declaim (ftype (function (hash-table &key (:account (or string null)) (:agent-id (or string null))) route-entry)
                discord-event->route-entry))
(defun discord-event->route-entry (event &key (account "default") (agent-id "main"))
  (declare (type hash-table event)
           (type (or string null) account agent-id))
  (let* ((channel-id (format nil "~a" (gethash "channelId" event "unknown")))
         (thread-id (when (gethash "threadId" event)
                      (format nil "~a" (gethash "threadId" event)))))
    (declare (type string channel-id)
             (type (or string null) thread-id))
    (make-route-entry :provider "discord"
                      :account (or account "default")
                      :target channel-id
                      :thread thread-id
                      :agent-id (or agent-id "main"))))

(declaim (ftype (function (hash-table &key (:account (or string null)) (:agent-id (or string null))) string)
                discord-session-key))
(defun discord-session-key (event &key (account "default") (agent-id "main"))
  (declare (type hash-table event)
           (type (or string null) account agent-id))
  (let ((route (discord-event->route-entry event :account account :agent-id agent-id)))
    (declare (type route-entry route))
    (make-session-key "discord" (route-entry-account route) (route-entry-target route)
                      :thread (route-entry-thread route)
                      :agent-id (route-entry-agent-id route))))

(declaim (ftype (function (route-entry string) hash-table) discord-route->send-payload))
(defun discord-route->send-payload (route text)
  (declare (type route-entry route)
           (type string text))
  (let ((payload (make-hash-table :test 'equal)))
    (declare (type hash-table payload))
    (setf (gethash "channel_id" payload) (route-entry-target route)
          (gethash "content" payload) text)
    (let ((thread (route-entry-thread route)))
      (declare (type (or string null) thread))
      (when thread
        (setf (gethash "thread_id" payload) thread)))
    payload))