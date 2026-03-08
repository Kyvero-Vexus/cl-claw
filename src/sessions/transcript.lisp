;;;; transcript.lisp — Session transcript read/write helpers

(defpackage :cl-claw.sessions.transcript
  (:use :cl)
  (:import-from :cl-claw.sessions.store
                :session-store
                :session-entry
                :session-store-get
                :session-store-upsert
                :session-entry-session-file
                :session-entry-message-count
                :session-entry-last-compaction-at-ms
                :now-ms)
  (:export
   :make-transcript-message
   :append-transcript-message
   :read-transcript-messages
   :read-session-transcript
   :read-last-session-message
   :rewrite-session-transcript))

(in-package :cl-claw.sessions.transcript)

(declaim (optimize (safety 3) (debug 3)))

(declaim (ftype (function (string string &key (:timestamp-ms (or fixnum null))
                                           (:metadata (or hash-table null)))
                          hash-table)
                make-transcript-message))
(defun make-transcript-message (role content &key timestamp-ms metadata)
  (declare (type string role content)
           (type (or fixnum null) timestamp-ms)
           (type (or hash-table null) metadata))
  (let ((obj (make-hash-table :test 'equal)))
    (declare (type hash-table obj))
    (setf (gethash "role" obj) role
          (gethash "content" obj) content
          (gethash "timestampMs" obj) (or timestamp-ms (now-ms)))
    (when metadata
      (setf (gethash "metadata" obj) metadata))
    obj))

(declaim (ftype (function (hash-table stream) t) write-jsonl-line))
(defun write-jsonl-line (obj out)
  (declare (type hash-table obj)
           (type stream out))
  (yason:encode obj out)
  (terpri out))

(declaim (ftype (function (session-store string string string
                                          &key (:timestamp-ms (or fixnum null))
                                               (:metadata (or hash-table null)))
                          hash-table)
                append-transcript-message))
(defun append-transcript-message (store session-key role content &key timestamp-ms metadata)
  (declare (type session-store store)
           (type string session-key role content)
           (type (or fixnum null) timestamp-ms)
           (type (or hash-table null) metadata))
  (let* ((entry (or (session-store-get store session-key)
                    (session-store-upsert store session-key)))
         (path (session-entry-session-file entry))
         (message (make-transcript-message role content
                                           :timestamp-ms timestamp-ms
                                           :metadata metadata)))
    (declare (type session-entry entry)
             (type string path)
             (type hash-table message))
    (uiop:ensure-all-directories-exist (list (uiop:pathname-directory-pathname path)))
    (with-open-file (out path :direction :output
                              :if-does-not-exist :create
                              :if-exists :append)
      (write-jsonl-line message out))
    (session-store-upsert store session-key
                          :session-file path
                          :message-count (1+ (session-entry-message-count entry))
                          :last-compaction-at-ms (session-entry-last-compaction-at-ms entry))
    message))

(declaim (ftype (function (string) (or hash-table null)) parse-json-line))
(defun parse-json-line (line)
  (declare (type string line))
  (handler-case
      (let ((parsed (yason:parse line :object-as :hash-table)))
        (declare (type t parsed))
        (if (hash-table-p parsed) parsed nil))
    (error () nil)))

(declaim (ftype (function (string &key (:limit (or fixnum null))) list)
                read-transcript-messages))
(defun read-transcript-messages (path &key limit)
  (declare (type string path)
           (type (or fixnum null) limit))
  (if (not (uiop:file-exists-p path))
      '()
      (with-open-file (in path :direction :input)
        (let ((messages '()))
          (declare (type list messages))
          (loop for line = (read-line in nil nil)
                while line do
                  (let ((obj (parse-json-line line)))
                    (when obj
                      (push obj messages))))
          (let ((ordered (nreverse messages)))
            (declare (type list ordered))
            (if (and limit (> limit 0) (> (length ordered) limit))
                (subseq ordered (- (length ordered) limit))
                ordered))))))

(declaim (ftype (function (session-store string &key (:limit (or fixnum null))) list)
                read-session-transcript))
(defun read-session-transcript (store session-key &key limit)
  (declare (type session-store store)
           (type string session-key)
           (type (or fixnum null) limit))
  (let ((entry (session-store-get store session-key)))
    (if entry
        (read-transcript-messages (session-entry-session-file entry) :limit limit)
        '())))

(declaim (ftype (function (session-store string) (or hash-table null)) read-last-session-message))
(defun read-last-session-message (store session-key)
  (declare (type session-store store)
           (type string session-key))
  (let ((messages (read-session-transcript store session-key :limit 1)))
    (if messages (car messages) nil)))

(declaim (ftype (function (session-store string list &key (:last-compaction-at-ms (or fixnum null))) t)
                rewrite-session-transcript))
(defun rewrite-session-transcript (store session-key messages &key last-compaction-at-ms)
  (declare (type session-store store)
           (type string session-key)
           (type list messages)
           (type (or fixnum null) last-compaction-at-ms))
  (let* ((entry (or (session-store-get store session-key)
                    (session-store-upsert store session-key)))
         (path (session-entry-session-file entry)))
    (declare (type session-entry entry)
             (type string path))
    (uiop:ensure-all-directories-exist (list (uiop:pathname-directory-pathname path)))
    (with-open-file (out path :direction :output
                              :if-does-not-exist :create
                              :if-exists :supersede)
      (dolist (msg messages)
        (when (hash-table-p msg)
          (write-jsonl-line msg out))))
    (session-store-upsert store session-key
                          :session-file path
                          :message-count (length messages)
                          :last-compaction-at-ms (or last-compaction-at-ms
                                                     (session-entry-last-compaction-at-ms entry)))
    t))