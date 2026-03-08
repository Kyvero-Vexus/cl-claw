;;;; irc.lisp — IRC channel mapping helpers

(defpackage :cl-claw.channels.irc
  (:use :cl)
  (:import-from :cl-claw.routing
                :route-entry
                :make-route-entry
                :make-session-key
                :route-entry-account
                :route-entry-target
                :route-entry-agent-id)
  (:export
   :irc-message->route-entry
   :irc-session-key
   :irc-route->send-command))

(in-package :cl-claw.channels.irc)

(declaim (optimize (safety 3) (debug 3)))

(declaim (ftype (function (hash-table &key (:account (or string null)) (:agent-id (or string null))) route-entry)
                irc-message->route-entry))
(defun irc-message->route-entry (message &key (account "default") (agent-id "main"))
  (declare (type hash-table message)
           (type (or string null) account agent-id))
  (let ((target (format nil "~a" (or (gethash "channel" message)
                                      (gethash "nick" message)
                                      "unknown"))))
    (declare (type string target))
    (make-route-entry :provider "irc"
                      :account (or account "default")
                      :target target
                      :agent-id (or agent-id "main"))))

(declaim (ftype (function (hash-table &key (:account (or string null)) (:agent-id (or string null))) string)
                irc-session-key))
(defun irc-session-key (message &key (account "default") (agent-id "main"))
  (declare (type hash-table message)
           (type (or string null) account agent-id))
  (let ((route (irc-message->route-entry message :account account :agent-id agent-id)))
    (declare (type route-entry route))
    (make-session-key "irc" (route-entry-account route) (route-entry-target route)
                      :agent-id (route-entry-agent-id route))))

(declaim (ftype (function (route-entry string) string) irc-route->send-command))
(defun irc-route->send-command (route text)
  (declare (type route-entry route)
           (type string text))
  (format nil "PRIVMSG ~a :~a" (route-entry-target route) text))