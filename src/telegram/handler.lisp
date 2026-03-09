;;;; handler.lisp — Telegram message handling
;;;;
;;;; Telegram channel implementation: connects to Telegram via Bot API,
;;;; handles inbound messages, and sends outbound messages.

(defpackage :cl-claw.telegram.handler
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
                :channel-set-message-handler
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
                :outbound-message-thread
                :outbound-message-reply-to-id
                :outbound-message-silent-p
                :outbound-message-format
                :outbound-message-effect
                :rate-limiter
                :make-rate-limiter
                :rate-limit-check
                :rate-limit-record)
  (:import-from :cl-claw.channel-protocol.normalize
                :normalize-telegram-message)
  (:import-from :cl-claw.channel-protocol.format
                :format-telegram-outbound
                :split-long-message
                :+telegram-max-message-length+)
  (:import-from :cl-claw.telegram.api-client
                :telegram-client
                :make-telegram-client
                :telegram-client-token
                :tg-get-me
                :tg-send-message
                :tg-get-updates
                :tg-set-message-reaction
                :tg-delete-message
                :tg-edit-message-text)
  (:export
   ;; Telegram channel
   :telegram-channel
   :make-telegram-channel-instance
   :telegram-channel-client
   :telegram-channel-bot-info
   :telegram-channel-bot-username

   ;; Polling
   :start-polling
   :stop-polling

   ;; Message operations
   :send-telegram-message
   :send-telegram-reaction
   :delete-telegram-message
   :edit-telegram-message))

(in-package :cl-claw.telegram.handler)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Telegram channel class
;;; -----------------------------------------------------------------------

(defclass telegram-channel (channel)
  ((client :initform nil :accessor telegram-channel-client
           :type (or telegram-client null))
   (bot-info :initform nil :accessor telegram-channel-bot-info
             :type (or hash-table null))
   (bot-username :initform "" :accessor telegram-channel-bot-username
                 :type string)
   (polling-thread :initform nil :accessor telegram-channel-polling-thread)
   (polling-p :initform nil :accessor telegram-channel-polling-p
              :type boolean)
   (last-update-id :initform 0 :accessor telegram-channel-last-update-id
                   :type fixnum)
   (rate-limiter :initform (make-rate-limiter :max-per-second 1.0
                                              :max-per-minute 20.0)
                 :accessor telegram-channel-rate-limiter
                 :type rate-limiter)
   (account-id :initform "default" :accessor telegram-channel-account-id
               :type string))
  (:documentation "Telegram Bot API channel implementation."))

(defun make-telegram-channel-instance (&key (account-id "default"))
  "Create a new telegram-channel instance."
  (let ((ch (make-instance 'telegram-channel)))
    (setf (telegram-channel-account-id ch) account-id)
    ch))

;;; -----------------------------------------------------------------------
;;; Channel protocol implementation
;;; -----------------------------------------------------------------------

(defmethod channel-get-info ((channel telegram-channel))
  (make-channel-info :id "telegram"
                     :name "Telegram"
                     :version "1.0.0"
                     :supports '("text" "photo" "document" "voice"
                                 "reactions" "threads" "groups"
                                 "reply" "edit" "delete" "effects")))

(defmethod channel-connect ((channel telegram-channel) account)
  (declare (type channel-account account))
  (let ((token (channel-account-bot-token account)))
    (unless (and token (plusp (length token)))
      (error "Telegram bot token is required"))
    (setf (channel-state-slot channel) +channel-state-connecting+)
    (let ((client (make-telegram-client :token token)))
      (setf (telegram-channel-client channel) client)
      ;; Verify token by calling getMe
      (multiple-value-bind (result ok) (tg-get-me client)
        (if ok
            (progn
              (setf (telegram-channel-bot-info channel) result)
              (when (hash-table-p result)
                (setf (telegram-channel-bot-username channel)
                      (or (gethash "username" result) "")))
              (setf (channel-state-slot channel) +channel-state-connected+))
            (progn
              (setf (channel-state-slot channel) +channel-state-error+)
              (error "Failed to verify Telegram bot token: ~A"
                     (when (hash-table-p result)
                       (gethash "description" result)))))))))

(defmethod channel-disconnect ((channel telegram-channel))
  (stop-polling channel)
  (setf (telegram-channel-client channel) nil)
  (setf (channel-state-slot channel) +channel-state-disconnected+))

(defmethod channel-send-message ((channel telegram-channel) outbound)
  (declare (type outbound-message outbound))
  (let* ((client (telegram-channel-client channel))
         (target (outbound-message-target outbound))
         (text (outbound-message-text outbound))
         (thread (outbound-message-thread outbound))
         (reply-to (outbound-message-reply-to-id outbound))
         (silent (outbound-message-silent-p outbound))
         (effect (outbound-message-effect outbound)))
    (unless client
      (error "Telegram channel not connected"))
    ;; Split long messages
    (let ((chunks (split-long-message text +telegram-max-message-length+))
          (last-result nil))
      (dolist (chunk chunks)
        ;; Rate limit
        (let ((limiter (telegram-channel-rate-limiter channel)))
          (loop until (rate-limit-check limiter)
                do (sleep 0.1))
          ;; Build reply params
          (let ((reply-params (when reply-to
                                (let ((rp (make-hash-table :test 'equal)))
                                  (setf (gethash "message_id" rp) reply-to)
                                  rp))))
            (multiple-value-bind (result ok)
                (tg-send-message client target chunk
                                 :thread-id thread
                                 :reply-parameters reply-params
                                 :disable-notification silent
                                 :message-effect-id effect)
              (rate-limit-record limiter)
              (when ok
                (setf last-result result))
              ;; Only reply to first chunk
              (setf reply-to nil)
              ;; Only apply effect to first chunk
              (setf effect nil)))))
      ;; Return message ID of last sent message
      (when (hash-table-p last-result)
        (format nil "~A" (gethash "message_id" last-result))))))

(defmethod channel-format-outbound ((channel telegram-channel) message)
  (format-telegram-outbound message))

;;; -----------------------------------------------------------------------
;;; Message operations
;;; -----------------------------------------------------------------------

(defun send-telegram-message (channel chat-id text &key thread-id reply-to silent)
  "Convenience function for sending a Telegram message."
  (declare (type telegram-channel channel)
           (type string text))
  (let ((outbound (cl-claw.channel-protocol.types:make-outbound-message
                   :target (format nil "~A" chat-id)
                   :text text
                   :thread (when thread-id (format nil "~A" thread-id))
                   :reply-to-id (when reply-to (format nil "~A" reply-to))
                   :silent-p silent)))
    (channel-send-message channel outbound)))

(defun send-telegram-reaction (channel chat-id message-id emoji)
  "Send a reaction to a Telegram message."
  (declare (type telegram-channel channel)
           (type string emoji))
  (let ((client (telegram-channel-client channel)))
    (unless client (error "Telegram channel not connected"))
    (tg-set-message-reaction client chat-id message-id emoji)))

(defun delete-telegram-message (channel chat-id message-id)
  "Delete a Telegram message."
  (declare (type telegram-channel channel))
  (let ((client (telegram-channel-client channel)))
    (unless client (error "Telegram channel not connected"))
    (tg-delete-message client chat-id message-id)))

(defun edit-telegram-message (channel chat-id message-id text &key parse-mode)
  "Edit a Telegram message."
  (declare (type telegram-channel channel)
           (type string text))
  (let ((client (telegram-channel-client channel)))
    (unless client (error "Telegram channel not connected"))
    (tg-edit-message-text client chat-id message-id text :parse-mode parse-mode)))

;;; -----------------------------------------------------------------------
;;; Long polling
;;; -----------------------------------------------------------------------

(defun start-polling (channel &key (timeout 30) (limit 100))
  "Start long-polling for updates in a background thread."
  (declare (type telegram-channel channel)
           (type fixnum timeout limit))
  (when (telegram-channel-polling-p channel)
    (return-from start-polling nil))
  (setf (telegram-channel-polling-p channel) t)
  (let ((thread
          (bt:make-thread
           (lambda ()
             (loop while (telegram-channel-polling-p channel)
                   do (handler-case
                          (let ((client (telegram-channel-client channel)))
                            (when client
                              (multiple-value-bind (updates ok)
                                  (tg-get-updates client
                                                  :offset (1+ (telegram-channel-last-update-id channel))
                                                  :limit limit
                                                  :timeout timeout)
                                (when (and ok (listp updates))
                                  (dolist (update updates)
                                    (when (hash-table-p update)
                                      (let ((update-id (gethash "update_id" update)))
                                        (when (and update-id (> update-id
                                                                (telegram-channel-last-update-id channel)))
                                          (setf (telegram-channel-last-update-id channel) update-id)))
                                      ;; Process message
                                      (let ((message (or (gethash "message" update)
                                                         (gethash "edited_message" update)
                                                         (gethash "channel_post" update))))
                                        (when (and message (hash-table-p message))
                                          (let* ((handler (channel-message-handler channel))
                                                 (normalized (normalize-telegram-message
                                                              message
                                                              :account (telegram-channel-account-id channel)
                                                              :bot-username (telegram-channel-bot-username channel))))
                                            (when handler
                                              (handler-case
                                                  (funcall handler normalized)
                                                (error (e)
                                                  (format *error-output*
                                                          "Error handling Telegram message: ~A~%" e)))))))))))))
                        (error (e)
                          (format *error-output* "Telegram polling error: ~A~%" e)
                          (sleep 5)))))
           :name "telegram-poller")))
    (setf (telegram-channel-polling-thread channel) thread))
  (values))

(defun stop-polling (channel)
  "Stop the long-polling thread."
  (declare (type telegram-channel channel))
  (setf (telegram-channel-polling-p channel) nil)
  (let ((thread (telegram-channel-polling-thread channel)))
    (when (and thread (bt:thread-alive-p thread))
      ;; Thread will exit on next poll timeout
      (setf (telegram-channel-polling-thread channel) nil)))
  (values))
