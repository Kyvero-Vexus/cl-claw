;;;; media.lisp — Telegram media upload/download
;;;;
;;;; Handles downloading files from Telegram servers and uploading
;;;; media files via the Bot API.

(defpackage :cl-claw.telegram.media
  (:use :cl)
  (:import-from :cl-claw.telegram.api-client
                :telegram-client
                :telegram-client-token
                :telegram-client-api-base
                :tg-get-file
                :tg-download-file
                :tg-send-photo
                :tg-send-document
                :tg-send-voice)
  (:export
   ;; Download
   :download-telegram-file
   :resolve-file-url
   :download-to-path

   ;; Upload
   :upload-photo
   :upload-document
   :upload-voice

   ;; Helpers
   :file-id-to-path))

(in-package :cl-claw.telegram.media)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; File resolution & download
;;; -----------------------------------------------------------------------

(declaim (ftype (function (telegram-client string) (or string null))
                resolve-file-url))
(defun resolve-file-url (client file-id)
  "Resolve a Telegram file_id to a downloadable URL.
Returns the URL string or nil on failure."
  (declare (type telegram-client client)
           (type string file-id))
  (multiple-value-bind (result ok) (tg-get-file client file-id)
    (when (and ok (hash-table-p result))
      (let ((file-path (gethash "file_path" result)))
        (when (and file-path (stringp file-path))
          (tg-download-file client file-path))))))

(declaim (ftype (function (string string) boolean) download-to-path))
(defun download-to-path (url dest-path)
  "Download a URL to a local file path.
Returns T on success, NIL on failure."
  (declare (type string url dest-path))
  (ensure-directories-exist (pathname dest-path))
  (handler-case
      (multiple-value-bind (output error-output exit-code)
          (uiop:run-program (list "curl" "-sL" "-o" dest-path
                                  "--max-time" "120"
                                  url)
                            :output '(:string :stripped t)
                            :error-output '(:string :stripped t)
                            :ignore-error-status t)
        (declare (ignore output error-output))
        (and exit-code (zerop exit-code)
             (probe-file dest-path)
             t))
    (error () nil)))

(declaim (ftype (function (telegram-client string string) (or string null))
                download-telegram-file))
(defun download-telegram-file (client file-id dest-path)
  "Download a Telegram file to a local path.
Returns the dest-path on success, nil on failure."
  (declare (type telegram-client client)
           (type string file-id dest-path))
  (let ((url (resolve-file-url client file-id)))
    (when url
      (when (download-to-path url dest-path)
        dest-path))))

(defun file-id-to-path (file-id &optional (base-dir "/tmp"))
  "Generate a local path for a Telegram file."
  (declare (type string file-id base-dir))
  (format nil "~A/tg-~A" base-dir file-id))

;;; -----------------------------------------------------------------------
;;; Upload (via file_id or URL; multipart not implemented yet)
;;; -----------------------------------------------------------------------

(defun upload-photo (client chat-id photo-source &key caption thread-id)
  "Upload a photo to a Telegram chat.
PHOTO-SOURCE can be a file_id, URL, or local path."
  (declare (type telegram-client client)
           (type string photo-source))
  (tg-send-photo client chat-id photo-source
                 :caption caption
                 :thread-id thread-id))

(defun upload-document (client chat-id doc-source &key caption thread-id)
  "Upload a document to a Telegram chat."
  (declare (type telegram-client client)
           (type string doc-source))
  (tg-send-document client chat-id doc-source
                    :caption caption
                    :thread-id thread-id))

(defun upload-voice (client chat-id voice-source &key caption thread-id)
  "Upload a voice message to a Telegram chat."
  (declare (type telegram-client client)
           (type string voice-source))
  (tg-send-voice client chat-id voice-source
                 :caption caption
                 :thread-id thread-id))
