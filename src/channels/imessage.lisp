;;;; imessage.lisp — iMessage/BlueBubbles channel mapping helpers

(defpackage :cl-claw.channels.imessage
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
   :normalize-imessage-target
   :classify-imessage-target
   :imessage-event->route-entry
   :imessage-session-key
   :imessage-route->send-payload))

(in-package :cl-claw.channels.imessage)

(declaim (optimize (safety 3) (debug 3)))

(declaim (ftype (function (string) string) normalize-imessage-target))
(defun normalize-imessage-target (raw-target)
  (declare (type string raw-target))
  (let* ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) raw-target))
         (lower (string-downcase trimmed)))
    (declare (type string trimmed lower))
    (cond
      ((search "@" lower) lower)
      ((or (search "chat" lower) (search ";" lower))
       lower)
      (t
       (with-output-to-string (out)
         (loop for ch across trimmed do
           (when (or (digit-char-p ch)
                     (char= ch #\+))
             (write-char ch out))))))))

(declaim (ftype (function (string) keyword) classify-imessage-target))
(defun classify-imessage-target (target)
  (declare (type string target))
  (let ((normalized (normalize-imessage-target target)))
    (declare (type string normalized))
    (cond
      ((search "@" normalized) :email)
      ((or (search "chat" normalized)
           (search ";" normalized))
       :chat-guid)
      ((and (> (length normalized) 0)
            (every #'digit-char-p (if (char= (char normalized 0) #\+)
                                      (subseq normalized 1)
                                      normalized)))
       :phone)
      (t :unknown))))

(declaim (ftype (function (hash-table) string) resolve-imessage-target))
(defun resolve-imessage-target (event)
  (declare (type hash-table event))
  (let* ((is-group (not (null (gethash "isGroup" event nil))))
         (group-target (or (gethash "chat_id" event)
                           (gethash "chatGuid" event)
                           (gethash "chatGuidId" event)))
         (direct-target (or (gethash "sender" event)
                            (gethash "handle" event)
                            (gethash "from" event)))
         (picked (or (and is-group group-target)
                     group-target
                     direct-target
                     "unknown")))
    (declare (type t is-group group-target direct-target picked))
    (normalize-imessage-target (format nil "~a" picked))))

(declaim (ftype (function (hash-table &key (:account (or string null)) (:agent-id (or string null))) route-entry)
                imessage-event->route-entry))
(defun imessage-event->route-entry (event &key (account "default") (agent-id "main"))
  (declare (type hash-table event)
           (type (or string null) account agent-id))
  (let* ((target (resolve-imessage-target event))
         (thread (when (gethash "thread_id" event)
                   (format nil "~a" (gethash "thread_id" event)))))
    (declare (type string target)
             (type (or string null) thread))
    (make-route-entry :provider "imessage"
                      :account (or account "default")
                      :target target
                      :thread thread
                      :agent-id (or agent-id "main"))))

(declaim (ftype (function (hash-table &key (:account (or string null)) (:agent-id (or string null))) string)
                imessage-session-key))
(defun imessage-session-key (event &key (account "default") (agent-id "main"))
  (declare (type hash-table event)
           (type (or string null) account agent-id))
  (let ((route (imessage-event->route-entry event :account account :agent-id agent-id)))
    (declare (type route-entry route))
    (make-session-key "imessage" (route-entry-account route) (route-entry-target route)
                      :thread (route-entry-thread route)
                      :agent-id (route-entry-agent-id route))))

(declaim (ftype (function (route-entry string) hash-table) imessage-route->send-payload))
(defun imessage-route->send-payload (route text)
  (declare (type route-entry route)
           (type string text))
  (let* ((payload (make-hash-table :test 'equal))
         (target (route-entry-target route))
         (target-kind (classify-imessage-target target)))
    (declare (type hash-table payload)
             (type string target)
             (type keyword target-kind))
    (setf (gethash "message" payload) text)
    (ecase target-kind
      (:chat-guid (setf (gethash "chatGuid" payload) target))
      ((:phone :email :unknown)
       (setf (gethash "address" payload) target)))
    (let ((thread (route-entry-thread route)))
      (declare (type (or string null) thread))
      (when thread
        (setf (gethash "thread_id" payload) thread)))
    payload))
