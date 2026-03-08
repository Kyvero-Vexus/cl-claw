;;;; signal.lisp — Signal channel mapping helpers

(defpackage :cl-claw.channels.signal
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
   :signal-envelope->route-entry
   :signal-session-key
   :signal-route->send-payload))

(in-package :cl-claw.channels.signal)

(declaim (optimize (safety 3) (debug 3)))

(declaim (ftype (function (hash-table &key (:account (or string null)) (:agent-id (or string null))) route-entry)
                signal-envelope->route-entry))
(defun signal-envelope->route-entry (envelope &key (account "default") (agent-id "main"))
  (declare (type hash-table envelope)
           (type (or string null) account agent-id))
  (let* ((target (format nil "~a" (or (gethash "groupId" envelope)
                                       (gethash "source" envelope)
                                       "unknown")))
         (thread (when (gethash "threadId" envelope)
                   (format nil "~a" (gethash "threadId" envelope)))))
    (declare (type string target)
             (type (or string null) thread))
    (make-route-entry :provider "signal"
                      :account (or account "default")
                      :target target
                      :thread thread
                      :agent-id (or agent-id "main"))))

(declaim (ftype (function (hash-table &key (:account (or string null)) (:agent-id (or string null))) string)
                signal-session-key))
(defun signal-session-key (envelope &key (account "default") (agent-id "main"))
  (declare (type hash-table envelope)
           (type (or string null) account agent-id))
  (let ((route (signal-envelope->route-entry envelope :account account :agent-id agent-id)))
    (declare (type route-entry route))
    (make-session-key "signal" (route-entry-account route) (route-entry-target route)
                      :thread (route-entry-thread route)
                      :agent-id (route-entry-agent-id route))))

(declaim (ftype (function (route-entry string) hash-table) signal-route->send-payload))
(defun signal-route->send-payload (route text)
  (declare (type route-entry route)
           (type string text))
  (let ((payload (make-hash-table :test 'equal)))
    (declare (type hash-table payload))
    (setf (gethash "recipient" payload) (route-entry-target route)
          (gethash "message" payload) text)
    payload))