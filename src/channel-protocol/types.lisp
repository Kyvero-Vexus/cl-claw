;;;; types.lisp — Channel protocol type definitions
;;;;
;;;; Core types for the channel system: normalized messages, channel state,
;;;; lifecycle events, and the channel protocol (CLOS generics).

(defpackage :cl-claw.channel-protocol.types
  (:use :cl)
  (:export
   ;; Normalized message
   :normalized-message
   :make-normalized-message
   :normalized-message-id
   :normalized-message-channel
   :normalized-message-account
   :normalized-message-target
   :normalized-message-thread
   :normalized-message-sender-id
   :normalized-message-sender-name
   :normalized-message-text
   :normalized-message-timestamp-ms
   :normalized-message-reply-to-id
   :normalized-message-attachments
   :normalized-message-raw
   :normalized-message-agent-id
   :normalized-message-is-group-p
   :normalized-message-is-mention-p

   ;; Outbound message
   :outbound-message
   :make-outbound-message
   :outbound-message-target
   :outbound-message-thread
   :outbound-message-text
   :outbound-message-reply-to-id
   :outbound-message-attachments
   :outbound-message-silent-p
   :outbound-message-format
   :outbound-message-effect

   ;; Attachment
   :attachment
   :make-attachment
   :attachment-type
   :attachment-url
   :attachment-path
   :attachment-mime-type
   :attachment-filename
   :attachment-size-bytes
   :attachment-caption

   ;; Channel state
   :+channel-state-disconnected+
   :+channel-state-connecting+
   :+channel-state-connected+
   :+channel-state-reconnecting+
   :+channel-state-error+
   :channel-state

   ;; Channel account
   :channel-account
   :make-channel-account
   :channel-account-id
   :channel-account-channel
   :channel-account-display-name
   :channel-account-bot-token
   :channel-account-extra

   ;; Channel info
   :channel-info
   :make-channel-info
   :channel-info-id
   :channel-info-name
   :channel-info-version
   :channel-info-supports

   ;; Channel protocol
   :channel
   :channel-get-info
   :channel-connect
   :channel-disconnect
   :channel-get-state
   :channel-send-message
   :channel-set-message-handler
   :channel-format-outbound

   ;; Rate limiting
   :rate-limiter
   :make-rate-limiter
   :rate-limiter-max-per-second
   :rate-limiter-max-per-minute
   :rate-limiter-window-ms
   :rate-limit-check
   :rate-limit-record))

(in-package :cl-claw.channel-protocol.types)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Attachment
;;; -----------------------------------------------------------------------

(defstruct attachment
  "A media attachment on a message."
  (type "file" :type string)
  (url nil :type (or string null))
  (path nil :type (or string null))
  (mime-type nil :type (or string null))
  (filename nil :type (or string null))
  (size-bytes 0 :type fixnum)
  (caption nil :type (or string null)))

;;; -----------------------------------------------------------------------
;;; Normalized inbound message
;;; -----------------------------------------------------------------------

(defstruct normalized-message
  "A channel-agnostic inbound message representation."
  (id "" :type string)
  (channel "" :type string)
  (account "default" :type string)
  (target "" :type string)
  (thread nil :type (or string null))
  (sender-id "" :type string)
  (sender-name "" :type string)
  (text "" :type string)
  (timestamp-ms 0 :type fixnum)
  (reply-to-id nil :type (or string null))
  (attachments '() :type list)
  (raw nil :type (or hash-table null))
  (agent-id "main" :type string)
  (is-group-p nil :type boolean)
  (is-mention-p nil :type boolean))

;;; -----------------------------------------------------------------------
;;; Outbound message
;;; -----------------------------------------------------------------------

(defstruct outbound-message
  "A channel-agnostic outbound message representation."
  (target "" :type string)
  (thread nil :type (or string null))
  (text "" :type string)
  (reply-to-id nil :type (or string null))
  (attachments '() :type list)
  (silent-p nil :type boolean)
  (format "text" :type string)
  (effect nil :type (or string null)))

;;; -----------------------------------------------------------------------
;;; Channel state
;;; -----------------------------------------------------------------------

(deftype channel-state ()
  '(member :disconnected :connecting :connected :reconnecting :error))

(defconstant +channel-state-disconnected+ :disconnected)
(defconstant +channel-state-connecting+ :connecting)
(defconstant +channel-state-connected+ :connected)
(defconstant +channel-state-reconnecting+ :reconnecting)
(defconstant +channel-state-error+ :error)

;;; -----------------------------------------------------------------------
;;; Channel account
;;; -----------------------------------------------------------------------

(defstruct channel-account
  "Configuration for a channel account (e.g., a Telegram bot token)."
  (id "default" :type string)
  (channel "" :type string)
  (display-name "" :type string)
  (bot-token nil :type (or string null))
  (extra nil :type (or hash-table null)))

;;; -----------------------------------------------------------------------
;;; Channel info
;;; -----------------------------------------------------------------------

(defstruct channel-info
  "Metadata about a channel implementation."
  (id "" :type string)
  (name "" :type string)
  (version "1.0.0" :type string)
  (supports '() :type list))

;;; -----------------------------------------------------------------------
;;; Channel protocol (CLOS generic functions)
;;; -----------------------------------------------------------------------

(defclass channel ()
  ((state :initform :disconnected :type channel-state :accessor channel-state-slot)
   (message-handler :initform nil :type (or function null) :accessor channel-message-handler))
  (:documentation "Abstract base class for channel implementations."))

(defgeneric channel-get-info (channel)
  (:documentation "Return channel-info metadata."))

(defgeneric channel-connect (channel account)
  (:documentation "Connect the channel using the given account."))

(defgeneric channel-disconnect (channel)
  (:documentation "Disconnect the channel gracefully."))

(defgeneric channel-get-state (channel)
  (:documentation "Return the current channel-state.")
  (:method ((channel channel))
    (channel-state-slot channel)))

(defgeneric channel-send-message (channel outbound)
  (:documentation "Send an outbound message through the channel.
Returns the message ID on success."))

(defgeneric channel-set-message-handler (channel handler)
  (:documentation "Set the inbound message handler callback.
HANDLER: (normalized-message) -> void")
  (:method ((channel channel) handler)
    (setf (channel-message-handler channel) handler)))

(defgeneric channel-format-outbound (channel message)
  (:documentation "Format a normalized outbound message for this specific channel.
Returns channel-specific payload (hash-table)."))

;;; -----------------------------------------------------------------------
;;; Rate limiter
;;; -----------------------------------------------------------------------

(defstruct rate-limiter
  "Token-bucket rate limiter for channel message sending."
  (max-per-second 1.0 :type single-float)
  (max-per-minute 30.0 :type single-float)
  (window-ms 1000 :type fixnum)
  (timestamps '() :type list)
  (lock (bt:make-lock "rate-limiter") :type t))

(declaim (ftype (function (rate-limiter) boolean) rate-limit-check))
(defun rate-limit-check (limiter)
  "Check if a message can be sent within rate limits.
Returns T if allowed, NIL if rate-limited."
  (declare (type rate-limiter limiter))
  (bt:with-lock-held ((rate-limiter-lock limiter))
    (let* ((now (get-internal-real-time))
           (one-sec-ago (- now (* internal-time-units-per-second 1)))
           (one-min-ago (- now (* internal-time-units-per-second 60)))
           ;; Clean old timestamps
           (recent (remove-if (lambda (ts) (< ts one-min-ago))
                              (rate-limiter-timestamps limiter)))
           (last-second (count-if (lambda (ts) (>= ts one-sec-ago)) recent)))
      (declare (type fixnum last-second))
      (setf (rate-limiter-timestamps limiter) recent)
      (and (< last-second (floor (rate-limiter-max-per-second limiter)))
           (< (length recent) (floor (rate-limiter-max-per-minute limiter)))))))

(declaim (ftype (function (rate-limiter) (values)) rate-limit-record))
(defun rate-limit-record (limiter)
  "Record a message send timestamp."
  (declare (type rate-limiter limiter))
  (bt:with-lock-held ((rate-limiter-lock limiter))
    (push (get-internal-real-time) (rate-limiter-timestamps limiter)))
  (values))
