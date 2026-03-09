;;;; handler.lisp — Discord channel implementation
;;;;
;;;; Discord channel CLOS implementation with connect/disconnect/send.

(defpackage :cl-claw.discord.handler
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
                :+channel-state-disconnected+
                :+channel-state-connecting+
                :+channel-state-connected+
                :+channel-state-error+
                :outbound-message
                :outbound-message-text
                :outbound-message-target
                :outbound-message-reply-to-id
                :outbound-message-silent-p
                :rate-limiter
                :make-rate-limiter
                :rate-limit-check
                :rate-limit-record)
  (:import-from :cl-claw.channel-protocol.format
                :format-discord-outbound
                :split-long-message
                :+discord-max-message-length+)
  (:import-from :cl-claw.discord.rest-client
                :discord-client
                :make-discord-client
                :dc-get-current-user
                :dc-send-message)
  (:export
   :discord-channel
   :make-discord-channel-instance
   :discord-channel-client
   :discord-channel-bot-user))

(in-package :cl-claw.discord.handler)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Discord channel class
;;; -----------------------------------------------------------------------

(defclass discord-channel (channel)
  ((client :initform nil :accessor discord-channel-client
           :type (or discord-client null))
   (bot-user :initform nil :accessor discord-channel-bot-user
             :type (or hash-table null))
   (rate-limiter :initform (make-rate-limiter :max-per-second 5.0
                                              :max-per-minute 50.0)
                 :accessor discord-channel-rate-limiter
                 :type rate-limiter))
  (:documentation "Discord channel implementation."))

(defun make-discord-channel-instance ()
  "Create a new discord-channel instance."
  (make-instance 'discord-channel))

;;; -----------------------------------------------------------------------
;;; Channel protocol
;;; -----------------------------------------------------------------------

(defmethod channel-get-info ((channel discord-channel))
  (make-channel-info :id "discord"
                     :name "Discord"
                     :version "1.0.0"
                     :supports '("text" "embeds" "reactions" "threads"
                                 "reply" "edit" "delete")))

(defmethod channel-connect ((channel discord-channel) account)
  (declare (type channel-account account))
  (let ((token (channel-account-bot-token account)))
    (unless (and token (plusp (length token)))
      (error "Discord bot token is required"))
    (setf (channel-state-slot channel) +channel-state-connecting+)
    (let ((client (make-discord-client :token token)))
      (setf (discord-channel-client channel) client)
      (multiple-value-bind (result ok) (dc-get-current-user client)
        (if ok
            (progn
              (setf (discord-channel-bot-user channel) result)
              (setf (channel-state-slot channel) +channel-state-connected+))
            (progn
              (setf (channel-state-slot channel) +channel-state-error+)
              (error "Failed to verify Discord bot token")))))))

(defmethod channel-disconnect ((channel discord-channel))
  (setf (discord-channel-client channel) nil)
  (setf (channel-state-slot channel) +channel-state-disconnected+))

(defmethod channel-send-message ((channel discord-channel) outbound)
  (declare (type outbound-message outbound))
  (let* ((client (discord-channel-client channel))
         (target (outbound-message-target outbound))
         (text (outbound-message-text outbound))
         (reply-to (outbound-message-reply-to-id outbound))
         (silent (outbound-message-silent-p outbound)))
    (unless client
      (error "Discord channel not connected"))
    (let ((chunks (split-long-message text +discord-max-message-length+))
          (last-result nil))
      (dolist (chunk chunks)
        (let ((limiter (discord-channel-rate-limiter channel)))
          (loop until (rate-limit-check limiter)
                do (sleep 0.1))
          (multiple-value-bind (result ok)
              (dc-send-message client target chunk
                               :reply-to reply-to
                               :flags (when silent 4096))
            (rate-limit-record limiter)
            (when ok (setf last-result result))
            (setf reply-to nil))))
      (when (hash-table-p last-result)
        (gethash "id" last-result)))))

(defmethod channel-format-outbound ((channel discord-channel) message)
  (format-discord-outbound message))
