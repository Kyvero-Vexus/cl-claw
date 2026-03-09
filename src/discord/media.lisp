;;;; media.lisp — Discord media/attachments & embeds
;;;;
;;;; Handles Discord attachment downloads and embed construction.

(defpackage :cl-claw.discord.media
  (:use :cl)
  (:export
   ;; Attachment extraction
   :extract-discord-attachments
   :download-discord-attachment

   ;; Embed construction
   :make-discord-embed
   :make-embed-field))

(in-package :cl-claw.discord.media)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Attachment extraction from Discord messages
;;; -----------------------------------------------------------------------

(defun extract-discord-attachments (message)
  "Extract attachments from a Discord message hash-table.
Returns a list of (url filename size content-type) tuples."
  (declare (type hash-table message))
  (let ((attachments (gethash "attachments" message))
        (result '()))
    (when (listp attachments)
      (dolist (att attachments)
        (when (hash-table-p att)
          (push (list (gethash "url" att)
                      (gethash "filename" att)
                      (or (gethash "size" att) 0)
                      (gethash "content_type" att))
                result))))
    (nreverse result)))

(defun download-discord-attachment (url dest-path)
  "Download a Discord attachment to a local path."
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

;;; -----------------------------------------------------------------------
;;; Embed construction
;;; -----------------------------------------------------------------------

(defun make-embed-field (name value &key inline)
  "Create a Discord embed field hash-table."
  (declare (type string name value))
  (let ((field (make-hash-table :test 'equal)))
    (setf (gethash "name" field) name)
    (setf (gethash "value" field) value)
    (when inline
      (setf (gethash "inline" field) t))
    field))

(defun make-discord-embed (&key title description color fields
                                 footer-text thumbnail-url image-url
                                 author-name author-url)
  "Create a Discord embed hash-table."
  (let ((embed (make-hash-table :test 'equal)))
    (when title
      (setf (gethash "title" embed) title))
    (when description
      (setf (gethash "description" embed) description))
    (when color
      (setf (gethash "color" embed) color))
    (when fields
      (setf (gethash "fields" embed) fields))
    (when footer-text
      (let ((footer (make-hash-table :test 'equal)))
        (setf (gethash "text" footer) footer-text)
        (setf (gethash "footer" embed) footer)))
    (when thumbnail-url
      (let ((thumb (make-hash-table :test 'equal)))
        (setf (gethash "url" thumb) thumbnail-url)
        (setf (gethash "thumbnail" embed) thumb)))
    (when image-url
      (let ((img (make-hash-table :test 'equal)))
        (setf (gethash "url" img) image-url)
        (setf (gethash "image" embed) img)))
    (when author-name
      (let ((author (make-hash-table :test 'equal)))
        (setf (gethash "name" author) author-name)
        (when author-url
          (setf (gethash "url" author) author-url))
        (setf (gethash "author" embed) author)))
    embed))
