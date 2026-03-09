;;;; rest-client.lisp — Discord REST API client
;;;;
;;;; HTTP client for the Discord REST API. Uses curl subprocess.

(defpackage :cl-claw.discord.rest-client
  (:use :cl)
  (:export
   :discord-client
   :make-discord-client
   :discord-client-token
   :discord-client-api-base

   ;; API methods
   :dc-get-current-user
   :dc-send-message
   :dc-edit-message
   :dc-delete-message
   :dc-create-reaction
   :dc-delete-reaction
   :dc-get-channel
   :dc-create-thread
   :dc-get-gateway

   ;; Low-level
   :dc-api-call
   :dc-api-url))

(in-package :cl-claw.discord.rest-client)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Discord client
;;; -----------------------------------------------------------------------

(defstruct discord-client
  "Discord REST API client."
  (token "" :type string)
  (api-base "https://discord.com/api/v10" :type string))

;;; -----------------------------------------------------------------------
;;; URL construction
;;; -----------------------------------------------------------------------

(declaim (ftype (function (discord-client string) string) dc-api-url))
(defun dc-api-url (client path)
  "Build the API URL for a Discord REST API endpoint."
  (declare (type discord-client client)
           (type string path))
  (format nil "~A~A" (discord-client-api-base client) path))

;;; -----------------------------------------------------------------------
;;; Low-level API call
;;; -----------------------------------------------------------------------

(defun dc-api-call (client method path &optional body)
  "Make a Discord REST API call.
METHOD: HTTP method string (GET, POST, PUT, PATCH, DELETE).
Returns (values response-data success-p)."
  (declare (type discord-client client)
           (type string method path))
  (let* ((url (dc-api-url client path))
         (args (list "curl" "-sS"
                     "-X" method
                     "-H" (format nil "Authorization: Bot ~A" (discord-client-token client))
                     "-H" "Content-Type: application/json"
                     "--max-time" "30")))
    (when body
      (let ((json (with-output-to-string (s)
                    (yason:encode body s))))
        (setf args (append args (list "-d" json)))))
    (setf args (append args (list url)))
    (handler-case
        (multiple-value-bind (output error-output exit-code)
            (uiop:run-program args
                              :output '(:string :stripped t)
                              :error-output '(:string :stripped t)
                              :ignore-error-status t)
          (declare (ignore error-output))
          (if (and exit-code (zerop exit-code) (plusp (length output)))
              (handler-case
                  (let ((data (yason:parse output)))
                    (if (and (hash-table-p data) (gethash "code" data))
                        (values data nil) ; Discord error response
                        (values data t)))
                (error ()
                  (values output t))) ; Non-JSON response (e.g., 204 No Content)
              (let ((err (make-hash-table :test 'equal)))
                (setf (gethash "error" err) "HTTP request failed")
                (values err nil))))
      (error (e)
        (let ((err (make-hash-table :test 'equal)))
          (setf (gethash "error" err) (format nil "~A" e))
          (values err nil))))))

;;; -----------------------------------------------------------------------
;;; User info
;;; -----------------------------------------------------------------------

(defun dc-get-current-user (client)
  "Get current bot user info."
  (dc-api-call client "GET" "/users/@me"))

;;; -----------------------------------------------------------------------
;;; Messages
;;; -----------------------------------------------------------------------

(defun dc-send-message (client channel-id content &key reply-to flags)
  "Send a message to a channel."
  (declare (type discord-client client)
           (type string channel-id content))
  (let ((body (make-hash-table :test 'equal)))
    (setf (gethash "content" body) content)
    (when reply-to
      (let ((ref (make-hash-table :test 'equal)))
        (setf (gethash "message_id" ref) reply-to)
        (setf (gethash "message_reference" body) ref)))
    (when flags
      (setf (gethash "flags" body) flags))
    (dc-api-call client "POST"
                 (format nil "/channels/~A/messages" channel-id)
                 body)))

(defun dc-edit-message (client channel-id message-id content)
  "Edit a message."
  (declare (type discord-client client)
           (type string channel-id message-id content))
  (let ((body (make-hash-table :test 'equal)))
    (setf (gethash "content" body) content)
    (dc-api-call client "PATCH"
                 (format nil "/channels/~A/messages/~A" channel-id message-id)
                 body)))

(defun dc-delete-message (client channel-id message-id)
  "Delete a message."
  (declare (type discord-client client)
           (type string channel-id message-id))
  (dc-api-call client "DELETE"
               (format nil "/channels/~A/messages/~A" channel-id message-id)))

;;; -----------------------------------------------------------------------
;;; Reactions
;;; -----------------------------------------------------------------------

(defun dc-create-reaction (client channel-id message-id emoji)
  "Add a reaction to a message."
  (declare (type discord-client client)
           (type string channel-id message-id emoji))
  (dc-api-call client "PUT"
               (format nil "/channels/~A/messages/~A/reactions/~A/@me"
                       channel-id message-id emoji)))

(defun dc-delete-reaction (client channel-id message-id emoji)
  "Remove own reaction from a message."
  (declare (type discord-client client)
           (type string channel-id message-id emoji))
  (dc-api-call client "DELETE"
               (format nil "/channels/~A/messages/~A/reactions/~A/@me"
                       channel-id message-id emoji)))

;;; -----------------------------------------------------------------------
;;; Channels & threads
;;; -----------------------------------------------------------------------

(defun dc-get-channel (client channel-id)
  "Get channel info."
  (declare (type discord-client client)
           (type string channel-id))
  (dc-api-call client "GET"
               (format nil "/channels/~A" channel-id)))

(defun dc-create-thread (client channel-id name &key auto-archive-duration message-id)
  "Create a thread in a channel."
  (declare (type discord-client client)
           (type string channel-id name))
  (let ((body (make-hash-table :test 'equal)))
    (setf (gethash "name" body) name)
    (when auto-archive-duration
      (setf (gethash "auto_archive_duration" body) auto-archive-duration))
    (if message-id
        (dc-api-call client "POST"
                     (format nil "/channels/~A/messages/~A/threads" channel-id message-id)
                     body)
        (dc-api-call client "POST"
                     (format nil "/channels/~A/threads" channel-id)
                     body))))

;;; -----------------------------------------------------------------------
;;; Gateway
;;; -----------------------------------------------------------------------

(defun dc-get-gateway (client)
  "Get the gateway URL for WebSocket connections."
  (dc-api-call client "GET" "/gateway/bot"))
