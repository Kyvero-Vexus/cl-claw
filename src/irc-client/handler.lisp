;;;; handler.lisp — IRC channel implementation & message handling
;;;;
;;;; IRC channel CLOS implementation with connect/disconnect/send
;;;; and message read loop.

(defpackage :cl-claw.irc-client.handler
  (:use :cl)
  (:import-from :cl-claw.channel-protocol.types
                :channel
                :channel-state-slot
                :channel-message-handler
                :channel-get-info
                :channel-connect
                :channel-disconnect
                :channel-get-state
                :channel-send-message
                :channel-format-outbound
                :channel-info
                :make-channel-info
                :channel-account
                :channel-account-bot-token
                :channel-account-id
                :+channel-state-disconnected+
                :+channel-state-connecting+
                :+channel-state-connected+
                :+channel-state-error+
                :outbound-message
                :outbound-message-text
                :outbound-message-target
                :normalized-message
                :make-normalized-message)
  (:import-from :cl-claw.channel-protocol.format
                :format-irc-outbound)
  (:import-from :cl-claw.irc-client.connection
                :irc-connection
                :make-irc-connection
                :irc-connection-nick
                :irc-connect
                :irc-disconnect
                :irc-privmsg
                :irc-join
                :irc-pong
                :irc-read-line
                :irc-nickserv-identify)
  (:import-from :cl-claw.irc-client.parser
                :irc-message
                :parse-irc-line
                :irc-message-command
                :irc-message-nick
                :irc-message-params
                :irc-message-trailing)
  (:export
   :irc-channel
   :make-irc-channel-instance
   :irc-channel-connection
   :irc-channel-channels
   :start-irc-read-loop
   :stop-irc-read-loop))

(in-package :cl-claw.irc-client.handler)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; IRC channel class
;;; -----------------------------------------------------------------------

(defclass irc-channel (channel)
  ((connection :initform nil :accessor irc-channel-connection
               :type (or irc-connection null))
   (channels-to-join :initform '() :accessor irc-channel-channels
                     :type list)
   (account-id :initform "default" :accessor irc-channel-account-id
               :type string)
   (read-thread :initform nil :accessor irc-channel-read-thread)
   (running-p :initform nil :accessor irc-channel-running-p
              :type boolean))
  (:documentation "IRC channel implementation."))

(defun make-irc-channel-instance (&key (account-id "default") channels)
  "Create a new irc-channel instance."
  (let ((ch (make-instance 'irc-channel)))
    (setf (irc-channel-account-id ch) account-id)
    (when channels
      (setf (irc-channel-channels ch) channels))
    ch))

;;; -----------------------------------------------------------------------
;;; Channel protocol
;;; -----------------------------------------------------------------------

(defmethod channel-get-info ((channel irc-channel))
  (make-channel-info :id "irc"
                     :name "IRC"
                     :version "1.0.0"
                     :supports '("text" "channels" "private")))

(defmethod channel-connect ((channel irc-channel) account)
  (declare (type channel-account account))
  (let* ((extra (cl-claw.channel-protocol.types:channel-account-extra account))
         (host (when (hash-table-p extra) (gethash "host" extra)))
         (port (when (hash-table-p extra) (or (gethash "port" extra) 6667)))
         (nick (when (hash-table-p extra)
                 (or (gethash "nick" extra) (channel-account-id account))))
         (tls (when (hash-table-p extra) (gethash "tls" extra)))
         (password (channel-account-bot-token account))
         (nickserv-pass (when (hash-table-p extra) (gethash "nickservPassword" extra)))
         (channels-str (when (hash-table-p extra) (gethash "channels" extra))))
    (unless host
      (error "IRC connection requires host in account extra config"))
    (setf (channel-state-slot channel) +channel-state-connecting+)
    (let ((conn (make-irc-connection :host host
                                      :port (if (numberp port) port 6667)
                                      :nick (or nick "cl-claw")
                                      :user (or nick "cl-claw")
                                      :tls-p (if tls t nil)
                                      :password password)))
      (setf (irc-channel-connection channel) conn)
      (handler-case
          (progn
            (irc-connect conn)
            ;; NickServ identify
            (when nickserv-pass
              (sleep 2) ; Wait for server to be ready
              (irc-nickserv-identify conn nickserv-pass))
            ;; Join channels
            (let ((chans (or (irc-channel-channels channel)
                             (when (listp channels-str) channels-str)
                             (when (stringp channels-str) (list channels-str)))))
              (dolist (ch chans)
                (when (stringp ch)
                  (irc-join conn ch))))
            (setf (channel-state-slot channel) +channel-state-connected+))
        (error (e)
          (setf (channel-state-slot channel) +channel-state-error+)
          (error "IRC connect failed: ~A" e))))))

(defmethod channel-disconnect ((channel irc-channel))
  (stop-irc-read-loop channel)
  (let ((conn (irc-channel-connection channel)))
    (when conn
      (irc-disconnect conn)))
  (setf (irc-channel-connection channel) nil)
  (setf (channel-state-slot channel) +channel-state-disconnected+))

(defmethod channel-send-message ((channel irc-channel) outbound)
  (declare (type outbound-message outbound))
  (let ((conn (irc-channel-connection channel))
        (target (outbound-message-target outbound))
        (text (outbound-message-text outbound)))
    (unless conn
      (error "IRC channel not connected"))
    ;; Split long messages for IRC
    (let ((lines (cl-ppcre:split "\\n" text)))
      (dolist (line lines)
        (when (plusp (length line))
          (irc-privmsg conn target line))))
    ;; IRC doesn't return message IDs
    nil))

(defmethod channel-format-outbound ((channel irc-channel) message)
  (format-irc-outbound message))

;;; -----------------------------------------------------------------------
;;; Read loop
;;; -----------------------------------------------------------------------

(defun start-irc-read-loop (channel)
  "Start the IRC message read loop in a background thread."
  (declare (type irc-channel channel))
  (when (irc-channel-running-p channel)
    (return-from start-irc-read-loop nil))
  (setf (irc-channel-running-p channel) t)
  (let ((thread
          (bt:make-thread
           (lambda ()
             (loop while (irc-channel-running-p channel)
                   do (handler-case
                          (let* ((conn (irc-channel-connection channel))
                                 (line (when conn (irc-read-line conn))))
                            (when (and line (plusp (length line)))
                              (let ((msg (parse-irc-line line)))
                                (process-irc-message channel msg))))
                        (error (e)
                          (format *error-output* "IRC read error: ~A~%" e)
                          (sleep 1)))))
           :name "irc-reader")))
    (setf (irc-channel-read-thread channel) thread))
  (values))

(defun stop-irc-read-loop (channel)
  "Stop the IRC read loop."
  (declare (type irc-channel channel))
  (setf (irc-channel-running-p channel) nil))

;;; -----------------------------------------------------------------------
;;; Message processing
;;; -----------------------------------------------------------------------

(defun process-irc-message (channel msg)
  "Process a parsed IRC message."
  (declare (type irc-channel channel)
           (type irc-message msg))
  (let ((command (irc-message-command msg)))
    (cond
      ;; PING -> PONG
      ((string= command "PING")
       (let ((conn (irc-channel-connection channel))
             (server (or (irc-message-trailing msg) "")))
         (when conn
           (irc-pong conn server))))
      ;; PRIVMSG -> dispatch to handler
      ((string= command "PRIVMSG")
       (let ((handler (channel-message-handler channel)))
         (when handler
           (let* ((nick (or (irc-message-nick msg) ""))
                  (target (or (first (irc-message-params msg)) ""))
                  (text (or (irc-message-trailing msg) ""))
                  (raw (make-hash-table :test 'equal)))
             (setf (gethash "nick" raw) nick)
             (setf (gethash "target" raw) target)
             (setf (gethash "text" raw) text)
             (let ((normalized (make-normalized-message
                                :id (format nil "irc-~D" (get-universal-time))
                                :channel "irc"
                                :account (irc-channel-account-id channel)
                                :target target
                                :sender-id nick
                                :sender-name nick
                                :text text
                                :timestamp-ms (* (get-universal-time) 1000)
                                :raw raw
                                :is-group-p (and (plusp (length target))
                                                 (char= (char target 0) #\#)))))
               (handler-case
                   (funcall handler normalized)
                 (error (e)
                   (format *error-output* "IRC handler error: ~A~%" e))))))))
      ;; Other commands: ignore for now
      (t nil))))
