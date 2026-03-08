;;;; store.lisp — Session metadata persistence and lookup

(defpackage :cl-claw.sessions.store
  (:use :cl)
  (:export
   :session-entry
   :session-entry-key
   :session-entry-session-file
   :session-entry-created-at-ms
   :session-entry-updated-at-ms
   :session-entry-message-count
   :session-entry-last-compaction-at-ms
   :session-store
   :session-store-root-dir
   :create-session-store
   :normalize-session-key
   :session-file-for-key
   :session-store-get
   :session-store-list
   :session-store-upsert
   :session-store-delete
   :session-store-save
   :session-store-load
   :now-ms))

(in-package :cl-claw.sessions.store)

(declaim (optimize (safety 3) (debug 3)))

(defstruct session-entry
  "Metadata for one logical session."
  (key "" :type string)
  (session-file "" :type string)
  (created-at-ms 0 :type fixnum)
  (updated-at-ms 0 :type fixnum)
  (message-count 0 :type fixnum)
  (last-compaction-at-ms 0 :type fixnum))

(defstruct (session-store (:constructor %make-session-store))
  "In-memory session index with disk persistence."
  (lock (bt:make-lock "session-store-lock") :type t)
  (entries (make-hash-table :test 'equal) :type hash-table)
  (root-dir "" :type string)
  (index-path "" :type string)
  (transcripts-dir "" :type string))

(declaim (ftype (function () fixnum) now-ms))
(defun now-ms ()
  (truncate (* 1000 (get-universal-time))))

(declaim (ftype (function (string) string) sanitize-key-fragment))
(defun sanitize-key-fragment (raw)
  (declare (type string raw))
  (let* ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) raw))
         (down (string-downcase trimmed)))
    (declare (type string trimmed down))
    (with-output-to-string (out)
      (loop for ch across down do
        (if (or (alphanumericp ch)
                (char= ch #\-)
                (char= ch #\_)
                (char= ch #\.))
            (write-char ch out)
            (write-char #\_ out))))))

(declaim (ftype (function (string) string) normalize-session-key))
(defun normalize-session-key (session-key)
  "Normalize session keys to a stable lowercase identifier."
  (declare (type string session-key))
  (let ((clean (sanitize-key-fragment session-key)))
    (if (string= clean "") "default" clean)))

(declaim (ftype (function (session-store string) string) session-file-for-key))
(defun session-file-for-key (store session-key)
  (declare (type session-store store)
           (type string session-key))
  (let ((name (normalize-session-key session-key)))
    (declare (type string name))
    (format nil "~a/~a.jsonl" (session-store-transcripts-dir store) name)))

(declaim (ftype (function (session-store) t) ensure-store-directories))
(defun ensure-store-directories (store)
  (declare (type session-store store))
  (uiop:ensure-all-directories-exist
   (list (session-store-root-dir store)
         (session-store-transcripts-dir store))))

(declaim (ftype (function (session-store) t) session-store-save))
(defun session-store-save (store)
  "Persist STORE index as JSON."
  (declare (type session-store store))
  (bt:with-lock-held ((session-store-lock store))
    (ensure-store-directories store)
    (let ((payload (make-hash-table :test 'equal)))
      (declare (type hash-table payload))
      (maphash
       (lambda (key entry)
         (declare (type string key)
                  (type session-entry entry))
         (setf (gethash key payload)
               (let ((obj (make-hash-table :test 'equal)))
                 (declare (type hash-table obj))
                 (setf (gethash "key" obj) (session-entry-key entry)
                       (gethash "sessionFile" obj) (session-entry-session-file entry)
                       (gethash "createdAtMs" obj) (session-entry-created-at-ms entry)
                       (gethash "updatedAtMs" obj) (session-entry-updated-at-ms entry)
                       (gethash "messageCount" obj) (session-entry-message-count entry)
                       (gethash "lastCompactionAtMs" obj) (session-entry-last-compaction-at-ms entry))
                 obj)))
       (session-store-entries store))
      (uiop:with-staging-pathname (tmp (session-store-index-path store))
        (uiop:with-output-file (out tmp :if-exists :supersede)
          (yason:encode payload out)
          (terpri out))))))

(declaim (ftype (function (session-store hash-table) t) parse-store-payload-into-entries))
(defun parse-store-payload-into-entries (store payload)
  (declare (type session-store store)
           (type hash-table payload))
  (clrhash (session-store-entries store))
  (maphash
   (lambda (key value)
     (declare (type string key)
              (type t value))
     (when (hash-table-p value)
       (let* ((normalized (normalize-session-key key))
              (entry (make-session-entry
                      :key normalized
                      :session-file (format nil "~a" (gethash "sessionFile" value
                                                               (session-file-for-key store normalized)))
                      :created-at-ms (truncate (or (gethash "createdAtMs" value) (now-ms)))
                      :updated-at-ms (truncate (or (gethash "updatedAtMs" value) (now-ms)))
                      :message-count (truncate (or (gethash "messageCount" value) 0))
                      :last-compaction-at-ms (truncate (or (gethash "lastCompactionAtMs" value) 0)))))
         (declare (type string normalized)
                  (type session-entry entry))
         (setf (gethash normalized (session-store-entries store)) entry))))
   payload))

(declaim (ftype (function (session-store) session-store) session-store-load))
(defun session-store-load (store)
  "Reload STORE entries from disk if index exists."
  (declare (type session-store store))
  (bt:with-lock-held ((session-store-lock store))
    (when (uiop:file-exists-p (session-store-index-path store))
      (handler-case
          (let* ((content (uiop:read-file-string (session-store-index-path store)))
                 (parsed (yason:parse content :object-as :hash-table)))
            (declare (type string content)
                     (type t parsed))
            (when (hash-table-p parsed)
              (parse-store-payload-into-entries store parsed)))
        (error ()
          (clrhash (session-store-entries store)))))
    store))

(declaim (ftype (function (&key (:root-dir (or string null))
                                (:index-path (or string null))
                                (:transcripts-dir (or string null)))
                          session-store)
                create-session-store))
(defun create-session-store (&key root-dir index-path transcripts-dir)
  (declare (type (or string null) root-dir index-path transcripts-dir))
  (let* ((root (or root-dir
                   (format nil "~a/cl-claw-state" (uiop:native-namestring (uiop:temporary-directory)))))
         (idx (or index-path (format nil "~a/sessions.json" root)))
         (tx-dir (or transcripts-dir (format nil "~a/sessions" root)))
         (store (%make-session-store :root-dir root :index-path idx :transcripts-dir tx-dir)))
    (declare (type string root idx tx-dir)
             (type session-store store))
    (ensure-store-directories store)
    (session-store-load store)
    store))

(declaim (ftype (function (session-store string) (or session-entry null)) session-store-get))
(defun session-store-get (store session-key)
  (declare (type session-store store)
           (type string session-key))
  (let ((normalized (normalize-session-key session-key)))
    (declare (type string normalized))
    (bt:with-lock-held ((session-store-lock store))
      (gethash normalized (session-store-entries store)))))

(declaim (ftype (function (session-store) list) session-store-list))
(defun session-store-list (store)
  (declare (type session-store store))
  (bt:with-lock-held ((session-store-lock store))
    (let ((items '()))
      (declare (type list items))
      (maphash (lambda (_key entry)
                 (declare (ignore _key)
                          (type session-entry entry))
                 (push entry items))
               (session-store-entries store))
      (sort items #'> :key #'session-entry-updated-at-ms))))

(declaim (ftype (function (session-store string &key (:session-file (or string null))
                                                  (:message-count (or fixnum null))
                                                  (:last-compaction-at-ms (or fixnum null)))
                          session-entry)
                session-store-upsert))
(defun session-store-upsert (store session-key &key session-file message-count last-compaction-at-ms)
  (declare (type session-store store)
           (type string session-key)
           (type (or string null) session-file)
           (type (or fixnum null) message-count last-compaction-at-ms))
  (let* ((normalized (normalize-session-key session-key))
         (timestamp (now-ms)))
    (declare (type string normalized)
             (type fixnum timestamp))
    (let ((result nil))
      (declare (type (or session-entry null) result))
      (bt:with-lock-held ((session-store-lock store))
        (let ((existing (gethash normalized (session-store-entries store))))
          (declare (type (or session-entry null) existing))
          (let ((entry (or existing
                           (make-session-entry
                            :key normalized
                            :session-file (or session-file (session-file-for-key store normalized))
                            :created-at-ms timestamp
                            :updated-at-ms timestamp
                            :message-count 0
                            :last-compaction-at-ms 0))))
            (declare (type session-entry entry))
            (when session-file
              (setf (session-entry-session-file entry) session-file))
            (when message-count
              (setf (session-entry-message-count entry) message-count))
            (when last-compaction-at-ms
              (setf (session-entry-last-compaction-at-ms entry) last-compaction-at-ms))
            (setf (session-entry-updated-at-ms entry) timestamp)
            (setf (gethash normalized (session-store-entries store)) entry)
            (setf result entry))))
      (session-store-save store)
      (the session-entry result))))

(declaim (ftype (function (session-store string) boolean) session-store-delete))
(defun session-store-delete (store session-key)
  (declare (type session-store store)
           (type string session-key))
  (let ((normalized (normalize-session-key session-key))
        (removed nil))
    (declare (type string normalized)
             (type boolean removed))
    (bt:with-lock-held ((session-store-lock store))
      (let ((entry (gethash normalized (session-store-entries store))))
        (declare (type (or session-entry null) entry))
        (when entry
          (remhash normalized (session-store-entries store))
          (setf removed t))))
    (when removed
      (session-store-save store))
    removed))