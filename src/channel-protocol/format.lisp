;;;; format.lisp — Outbound message formatting per channel
;;;;
;;;; Formats normalized outbound messages into channel-specific payloads
;;;; for Telegram, Discord, and IRC.

(defpackage :cl-claw.channel-protocol.format
  (:use :cl)
  (:import-from :cl-claw.channel-protocol.types
                :outbound-message
                :make-outbound-message
                :outbound-message-target
                :outbound-message-thread
                :outbound-message-text
                :outbound-message-reply-to-id
                :outbound-message-silent-p
                :outbound-message-format
                :outbound-message-effect
                :outbound-message-attachments
                :attachment
                :attachment-type
                :attachment-url
                :attachment-path
                :attachment-filename
                :attachment-caption)
  (:export
   :format-telegram-outbound
   :format-discord-outbound
   :format-irc-outbound
   :split-long-message
   :+telegram-max-message-length+
   :+discord-max-message-length+
   :+irc-max-message-length+))

(in-package :cl-claw.channel-protocol.format)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Message length limits
;;; -----------------------------------------------------------------------

(defconstant +telegram-max-message-length+ 4096
  "Telegram maximum message length in characters.")

(defconstant +discord-max-message-length+ 2000
  "Discord maximum message length in characters.")

(defconstant +irc-max-message-length+ 450
  "IRC maximum message length in characters (safe limit).")

;;; -----------------------------------------------------------------------
;;; Message splitting
;;; -----------------------------------------------------------------------

(declaim (ftype (function (string fixnum) list) split-long-message))
(defun split-long-message (text max-length)
  "Split a long message into chunks respecting max-length.
Tries to split at newlines or spaces."
  (declare (type string text)
           (type fixnum max-length))
  (if (<= (length text) max-length)
      (list text)
      (let ((chunks '())
            (start 0))
        (declare (type fixnum start))
        (loop while (< start (length text))
              do (let* ((end (min (+ start max-length) (length text)))
                        (chunk-end (if (= end (length text))
                                       end
                                       ;; Try to find a good split point
                                       (or (position #\Newline text :from-end t
                                                                     :start start :end end)
                                           (position #\Space text :from-end t
                                                                   :start (+ start (floor max-length 2))
                                                                   :end end)
                                           end))))
                   (declare (type fixnum end chunk-end))
                   (push (subseq text start chunk-end) chunks)
                   (setf start (if (< chunk-end end)
                                   (1+ chunk-end) ; skip the split character
                                   chunk-end))))
        (nreverse chunks))))

;;; -----------------------------------------------------------------------
;;; Telegram formatting
;;; -----------------------------------------------------------------------

(declaim (ftype (function (outbound-message) hash-table) format-telegram-outbound))
(defun format-telegram-outbound (msg)
  "Format an outbound message for the Telegram Bot API."
  (declare (type outbound-message msg))
  (let ((payload (make-hash-table :test 'equal)))
    (setf (gethash "chat_id" payload) (outbound-message-target msg))
    (setf (gethash "text" payload) (outbound-message-text msg))
    ;; Parse mode
    (let ((fmt (outbound-message-format msg)))
      (cond
        ((string= fmt "markdown")
         (setf (gethash "parse_mode" payload) "MarkdownV2"))
        ((string= fmt "html")
         (setf (gethash "parse_mode" payload) "HTML"))))
    ;; Thread/topic
    (when (outbound-message-thread msg)
      (setf (gethash "message_thread_id" payload)
            (outbound-message-thread msg)))
    ;; Reply
    (when (outbound-message-reply-to-id msg)
      (let ((reply-params (make-hash-table :test 'equal)))
        (setf (gethash "message_id" reply-params)
              (outbound-message-reply-to-id msg))
        (setf (gethash "reply_parameters" payload) reply-params)))
    ;; Silent
    (when (outbound-message-silent-p msg)
      (setf (gethash "disable_notification" payload) t))
    ;; Effect
    (when (outbound-message-effect msg)
      (setf (gethash "message_effect_id" payload)
            (outbound-message-effect msg)))
    payload))

;;; -----------------------------------------------------------------------
;;; Discord formatting
;;; -----------------------------------------------------------------------

(declaim (ftype (function (outbound-message) hash-table) format-discord-outbound))
(defun format-discord-outbound (msg)
  "Format an outbound message for the Discord REST API."
  (declare (type outbound-message msg))
  (let ((payload (make-hash-table :test 'equal)))
    (setf (gethash "content" payload) (outbound-message-text msg))
    ;; Reply
    (when (outbound-message-reply-to-id msg)
      (let ((ref (make-hash-table :test 'equal)))
        (setf (gethash "message_id" ref) (outbound-message-reply-to-id msg))
        (setf (gethash "message_reference" payload) ref)))
    ;; Silent (suppress notifications)
    (when (outbound-message-silent-p msg)
      (setf (gethash "flags" payload) 4096)) ; SUPPRESS_NOTIFICATIONS
    payload))

;;; -----------------------------------------------------------------------
;;; IRC formatting
;;; -----------------------------------------------------------------------

(declaim (ftype (function (outbound-message) list) format-irc-outbound))
(defun format-irc-outbound (msg)
  "Format an outbound message for IRC.
Returns a list of IRC PRIVMSG commands (strings), since IRC
messages are line-based and may need splitting."
  (declare (type outbound-message msg))
  (let* ((target (outbound-message-target msg))
         (text (outbound-message-text msg))
         (chunks (split-long-message text +irc-max-message-length+)))
    (mapcar (lambda (chunk)
              (format nil "PRIVMSG ~A :~A" target chunk))
            chunks)))
