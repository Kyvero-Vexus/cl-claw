;;;; storage.lisp — Secret storage: read/write encrypted or plaintext secret store
;;;;
;;;; Provides an in-memory secret store with optional file persistence.

(defpackage :cl-claw.secrets.storage
  (:use :cl)
  (:export
   :create-secret-store
   :secret-store
   :store-secret
   :retrieve-secret
   :delete-secret
   :list-secret-names
   :store-snapshot))

(in-package :cl-claw.secrets.storage)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Secret store ────────────────────────────────────────────────────────────

(defstruct (secret-store (:constructor %make-secret-store))
  "An in-memory secret store."
  (lock    (bt:make-lock "secret-store-lock") :type t)
  (secrets (make-hash-table :test 'equal) :type hash-table)
  (path    nil :type (or string null)))

(declaim (ftype (function (&key (:path (or string null))) secret-store)
                create-secret-store))
(defun create-secret-store (&key path)
  "Create a secret store. If PATH is provided, load from disk if it exists."
  (declare (type (or string null) path))
  (let ((store (%make-secret-store :path path)))
    (declare (type secret-store store))
    ;; Load from disk if path exists
    (when (and path (uiop:file-exists-p path))
      (handler-case
          (let* ((content (uiop:read-file-string path))
                 (parsed  (yason:parse content :object-as :hash-table)))
            (declare (type string content)
                     (type t parsed))
            (when (hash-table-p parsed)
              (maphash (lambda (k v)
                         (declare (type string k)
                                  (type t v))
                         (setf (gethash k (secret-store-secrets store))
                               (format nil "~a" v)))
                       parsed)))
        (error () nil)))
    store))

(declaim (ftype (function (secret-store string string) t) store-secret))
(defun store-secret (store name value)
  "Store a secret VALUE under NAME in STORE."
  (declare (type secret-store store)
           (type string name value))
  (bt:with-lock-held ((secret-store-lock store))
    (setf (gethash name (secret-store-secrets store)) value)
    ;; Persist to disk if path is set
    (when (secret-store-path store)
      (persist-store store))))

(declaim (ftype (function (secret-store string) (or string null)) retrieve-secret))
(defun retrieve-secret (store name)
  "Retrieve the secret VALUE for NAME from STORE, or NIL if not found."
  (declare (type secret-store store)
           (type string name))
  (bt:with-lock-held ((secret-store-lock store))
    (gethash name (secret-store-secrets store))))

(declaim (ftype (function (secret-store string) boolean) delete-secret))
(defun delete-secret (store name)
  "Delete the secret for NAME from STORE. Returns T if it existed."
  (declare (type secret-store store)
           (type string name))
  (bt:with-lock-held ((secret-store-lock store))
    (let ((existed (gethash name (secret-store-secrets store))))
      (declare (type t existed))
      (when existed
        (remhash name (secret-store-secrets store))
        (when (secret-store-path store)
          (persist-store store)))
      (not (null existed)))))

(declaim (ftype (function (secret-store) list) list-secret-names))
(defun list-secret-names (store)
  "Return a list of all secret names in STORE."
  (declare (type secret-store store))
  (bt:with-lock-held ((secret-store-lock store))
    (let ((names '()))
      (declare (type list names))
      (maphash (lambda (k v)
                 (declare (ignore v))
                 (push k names))
               (secret-store-secrets store))
      (sort names #'string<))))

(declaim (ftype (function (secret-store) hash-table) store-snapshot))
(defun store-snapshot (store)
  "Return a copy of all secrets in STORE as a hash-table."
  (declare (type secret-store store))
  (bt:with-lock-held ((secret-store-lock store))
    (let ((snap (make-hash-table :test 'equal)))
      (declare (type hash-table snap))
      (maphash (lambda (k v)
                 (setf (gethash k snap) v))
               (secret-store-secrets store))
      snap)))

;;; ─── Persistence ─────────────────────────────────────────────────────────────

(declaim (ftype (function (secret-store) t) persist-store))
(defun persist-store (store)
  "Write STORE's secrets to its path (must be called with lock held)."
  (declare (type secret-store store))
  (let ((path (secret-store-path store)))
    (declare (type (or string null) path))
    (when path
      (handler-case
          (let ((content (with-output-to-string (s)
                           (yason:encode (secret-store-secrets store) s)
                           (terpri s))))
            (declare (type string content))
            (uiop:ensure-all-directories-exist
             (list (uiop:pathname-directory-pathname path)))
            (uiop:with-staging-pathname (staging path)
              (uiop:with-output-file (out staging :if-exists :supersede)
                (write-string content out))))
        (error () nil)))))
