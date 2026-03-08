;;;; slack.lisp — Slack channel mapping helpers

(defpackage :cl-claw.channels.slack
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
   :slack-event->route-entry
   :slack-session-key
   :slack-route->send-payload))

(in-package :cl-claw.channels.slack)

(declaim (optimize (safety 3) (debug 3)))

(declaim (ftype (function (hash-table &key (:account (or string null)) (:agent-id (or string null))) route-entry)
                slack-event->route-entry))
(defun slack-event->route-entry (event &key (account "default") (agent-id "main"))
  (declare (type hash-table event)
           (type (or string null) account agent-id))
  (let* ((channel (format nil "~a" (gethash "channel" event "unknown")))
         (thread (when (gethash "thread_ts" event)
                   (format nil "~a" (gethash "thread_ts" event)))))
    (declare (type string channel)
             (type (or string null) thread))
    (make-route-entry :provider "slack"
                      :account (or account "default")
                      :target channel
                      :thread thread
                      :agent-id (or agent-id "main"))))

(declaim (ftype (function (hash-table &key (:account (or string null)) (:agent-id (or string null))) string)
                slack-session-key))
(defun slack-session-key (event &key (account "default") (agent-id "main"))
  (declare (type hash-table event)
           (type (or string null) account agent-id))
  (let ((route (slack-event->route-entry event :account account :agent-id agent-id)))
    (declare (type route-entry route))
    (make-session-key "slack" (route-entry-account route) (route-entry-target route)
                      :thread (route-entry-thread route)
                      :agent-id (route-entry-agent-id route))))

(declaim (ftype (function (route-entry string) hash-table) slack-route->send-payload))
(defun slack-route->send-payload (route text)
  (declare (type route-entry route)
           (type string text))
  (let ((payload (make-hash-table :test 'equal)))
    (declare (type hash-table payload))
    (setf (gethash "channel" payload) (route-entry-target route)
          (gethash "text" payload) text)
    (let ((thread (route-entry-thread route)))
      (declare (type (or string null) thread))
      (when thread
        (setf (gethash "thread_ts" payload) thread)))
    payload))