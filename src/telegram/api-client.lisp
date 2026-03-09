;;;; api-client.lisp — Telegram Bot API client
;;;;
;;;; HTTP client for the Telegram Bot API. Uses curl subprocess for
;;;; HTTP requests (matching OpenClaw's http-based approach).

(defpackage :cl-claw.telegram.api-client
  (:use :cl)
  (:export
   ;; Client
   :telegram-client
   :make-telegram-client
   :telegram-client-token
   :telegram-client-api-base

   ;; API methods
   :tg-get-me
   :tg-send-message
   :tg-send-photo
   :tg-send-document
   :tg-send-voice
   :tg-forward-message
   :tg-delete-message
   :tg-edit-message-text
   :tg-set-message-reaction
   :tg-get-updates
   :tg-set-webhook
   :tg-delete-webhook
   :tg-get-file
   :tg-download-file

   ;; Low-level
   :tg-api-call
   :tg-api-url))

(in-package :cl-claw.telegram.api-client)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Telegram client
;;; -----------------------------------------------------------------------

(defstruct telegram-client
  "Telegram Bot API client."
  (token "" :type string)
  (api-base "https://api.telegram.org" :type string))

;;; -----------------------------------------------------------------------
;;; URL construction
;;; -----------------------------------------------------------------------

(declaim (ftype (function (telegram-client string) string) tg-api-url))
(defun tg-api-url (client method)
  "Build the API URL for a Telegram Bot API method."
  (declare (type telegram-client client)
           (type string method))
  (format nil "~A/bot~A/~A"
          (telegram-client-api-base client)
          (telegram-client-token client)
          method))

;;; -----------------------------------------------------------------------
;;; Low-level API call (JSON POST via curl)
;;; -----------------------------------------------------------------------

(declaim (ftype (function (telegram-client string &optional hash-table)
                          (values hash-table boolean))
                tg-api-call))
(defun tg-api-call (client method &optional (params (make-hash-table :test 'equal)))
  "Make a Telegram Bot API call.
Returns (values response-hash-table success-p)."
  (declare (type telegram-client client)
           (type string method)
           (type hash-table params))
  (let* ((url (tg-api-url client method))
         (json-body (with-output-to-string (s)
                      (yason:encode params s))))
    (declare (type string url json-body))
    (handler-case
        (multiple-value-bind (output error-output exit-code)
            (uiop:run-program
             (list "curl" "-sS"
                   "-X" "POST"
                   "-H" "Content-Type: application/json"
                   "-d" json-body
                   "--max-time" "30"
                   url)
             :output '(:string :stripped t)
             :error-output '(:string :stripped t)
             :ignore-error-status t)
          (declare (ignore error-output)
                   (type string output))
          (if (and exit-code (zerop exit-code) (plusp (length output)))
              (let* ((response (yason:parse output))
                     (ok (and (hash-table-p response)
                              (gethash "ok" response))))
                (if ok
                    (values (or (gethash "result" response) response) t)
                    (values response nil)))
              (let ((err (make-hash-table :test 'equal)))
                (setf (gethash "error" err) (format nil "HTTP request failed (exit ~A)" exit-code))
                (values err nil))))
      (error (e)
        (let ((err (make-hash-table :test 'equal)))
          (setf (gethash "error" err) (format nil "~A" e))
          (values err nil))))))

;;; -----------------------------------------------------------------------
;;; Bot info
;;; -----------------------------------------------------------------------

(defun tg-get-me (client)
  "Get bot info (getMe)."
  (declare (type telegram-client client))
  (tg-api-call client "getMe"))

;;; -----------------------------------------------------------------------
;;; Message sending
;;; -----------------------------------------------------------------------

(defun tg-send-message (client chat-id text &key parse-mode thread-id
                                                  reply-parameters
                                                  disable-notification
                                                  message-effect-id)
  "Send a text message."
  (declare (type telegram-client client)
           (type string text))
  (let ((params (make-hash-table :test 'equal)))
    (setf (gethash "chat_id" params) chat-id)
    (setf (gethash "text" params) text)
    (when parse-mode
      (setf (gethash "parse_mode" params) parse-mode))
    (when thread-id
      (setf (gethash "message_thread_id" params) thread-id))
    (when reply-parameters
      (setf (gethash "reply_parameters" params) reply-parameters))
    (when disable-notification
      (setf (gethash "disable_notification" params) t))
    (when message-effect-id
      (setf (gethash "message_effect_id" params) message-effect-id))
    (tg-api-call client "sendMessage" params)))

(defun tg-send-photo (client chat-id photo &key caption parse-mode thread-id)
  "Send a photo."
  (declare (type telegram-client client))
  (let ((params (make-hash-table :test 'equal)))
    (setf (gethash "chat_id" params) chat-id)
    (setf (gethash "photo" params) photo)
    (when caption
      (setf (gethash "caption" params) caption))
    (when parse-mode
      (setf (gethash "parse_mode" params) parse-mode))
    (when thread-id
      (setf (gethash "message_thread_id" params) thread-id))
    (tg-api-call client "sendPhoto" params)))

(defun tg-send-document (client chat-id document &key caption thread-id)
  "Send a document."
  (declare (type telegram-client client))
  (let ((params (make-hash-table :test 'equal)))
    (setf (gethash "chat_id" params) chat-id)
    (setf (gethash "document" params) document)
    (when caption
      (setf (gethash "caption" params) caption))
    (when thread-id
      (setf (gethash "message_thread_id" params) thread-id))
    (tg-api-call client "sendDocument" params)))

(defun tg-send-voice (client chat-id voice &key caption thread-id)
  "Send a voice message."
  (declare (type telegram-client client))
  (let ((params (make-hash-table :test 'equal)))
    (setf (gethash "chat_id" params) chat-id)
    (setf (gethash "voice" params) voice)
    (when caption
      (setf (gethash "caption" params) caption))
    (when thread-id
      (setf (gethash "message_thread_id" params) thread-id))
    (tg-api-call client "sendVoice" params)))

;;; -----------------------------------------------------------------------
;;; Message operations
;;; -----------------------------------------------------------------------

(defun tg-forward-message (client chat-id from-chat-id message-id)
  "Forward a message."
  (declare (type telegram-client client))
  (let ((params (make-hash-table :test 'equal)))
    (setf (gethash "chat_id" params) chat-id)
    (setf (gethash "from_chat_id" params) from-chat-id)
    (setf (gethash "message_id" params) message-id)
    (tg-api-call client "forwardMessage" params)))

(defun tg-delete-message (client chat-id message-id)
  "Delete a message."
  (declare (type telegram-client client))
  (let ((params (make-hash-table :test 'equal)))
    (setf (gethash "chat_id" params) chat-id)
    (setf (gethash "message_id" params) message-id)
    (tg-api-call client "deleteMessage" params)))

(defun tg-edit-message-text (client chat-id message-id text &key parse-mode)
  "Edit a message's text."
  (declare (type telegram-client client)
           (type string text))
  (let ((params (make-hash-table :test 'equal)))
    (setf (gethash "chat_id" params) chat-id)
    (setf (gethash "message_id" params) message-id)
    (setf (gethash "text" params) text)
    (when parse-mode
      (setf (gethash "parse_mode" params) parse-mode))
    (tg-api-call client "editMessageText" params)))

(defun tg-set-message-reaction (client chat-id message-id emoji &key is-big)
  "Set a reaction on a message."
  (declare (type telegram-client client)
           (type string emoji))
  (let ((params (make-hash-table :test 'equal))
        (reaction (make-hash-table :test 'equal)))
    (setf (gethash "type" reaction) "emoji")
    (setf (gethash "emoji" reaction) emoji)
    (setf (gethash "chat_id" params) chat-id)
    (setf (gethash "message_id" params) message-id)
    (setf (gethash "reaction" params) (list reaction))
    (when is-big
      (setf (gethash "is_big" params) t))
    (tg-api-call client "setMessageReaction" params)))

;;; -----------------------------------------------------------------------
;;; Polling & webhooks
;;; -----------------------------------------------------------------------

(defun tg-get-updates (client &key offset limit timeout allowed-updates)
  "Get updates via long polling."
  (declare (type telegram-client client))
  (let ((params (make-hash-table :test 'equal)))
    (when offset
      (setf (gethash "offset" params) offset))
    (when limit
      (setf (gethash "limit" params) limit))
    (when timeout
      (setf (gethash "timeout" params) timeout))
    (when allowed-updates
      (setf (gethash "allowed_updates" params) allowed-updates))
    (tg-api-call client "getUpdates" params)))

(defun tg-set-webhook (client url &key certificate max-connections allowed-updates)
  "Set webhook URL."
  (declare (type telegram-client client)
           (type string url))
  (let ((params (make-hash-table :test 'equal)))
    (setf (gethash "url" params) url)
    (when certificate
      (setf (gethash "certificate" params) certificate))
    (when max-connections
      (setf (gethash "max_connections" params) max-connections))
    (when allowed-updates
      (setf (gethash "allowed_updates" params) allowed-updates))
    (tg-api-call client "setWebhook" params)))

(defun tg-delete-webhook (client &key drop-pending-updates)
  "Delete webhook."
  (declare (type telegram-client client))
  (let ((params (make-hash-table :test 'equal)))
    (when drop-pending-updates
      (setf (gethash "drop_pending_updates" params) t))
    (tg-api-call client "deleteWebhook" params)))

;;; -----------------------------------------------------------------------
;;; File operations
;;; -----------------------------------------------------------------------

(defun tg-get-file (client file-id)
  "Get file info for downloading."
  (declare (type telegram-client client)
           (type string file-id))
  (let ((params (make-hash-table :test 'equal)))
    (setf (gethash "file_id" params) file-id)
    (tg-api-call client "getFile" params)))

(declaim (ftype (function (telegram-client string) string) tg-download-file))
(defun tg-download-file (client file-path)
  "Get the download URL for a file path from getFile."
  (declare (type telegram-client client)
           (type string file-path))
  (format nil "~A/file/bot~A/~A"
          (telegram-client-api-base client)
          (telegram-client-token client)
          file-path))
