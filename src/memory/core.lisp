;;;; core.lisp — In-process memory manager with embedding search

(defpackage :cl-claw.memory
  (:use :cl)
  (:export
   :memory-item
   :memory-item-id
   :memory-item-text
   :memory-item-embedding
   :memory-item-metadata
   :memory-item-created-at-ms
   :memory-search-result
   :memory-search-result-item
   :memory-search-result-score
   :memory-manager
   :create-memory-manager
   :text->embedding
   :upsert-memory-item
   :remove-memory-item
   :list-memory-items
   :search-memory))

(in-package :cl-claw.memory)

(declaim (optimize (safety 3) (debug 3)))

(defstruct memory-item
  (id "" :type string)
  (text "" :type string)
  (embedding (make-hash-table :test 'equal) :type hash-table)
  (metadata (make-hash-table :test 'equal) :type hash-table)
  (created-at-ms 0 :type fixnum))

(defstruct memory-search-result
  (item nil :type (or memory-item null))
  (score 0.0d0 :type double-float))

(defstruct (memory-manager (:constructor %make-memory-manager))
  (lock (bt:make-lock "memory-manager-lock") :type t)
  (items (make-hash-table :test 'equal) :type hash-table))

(declaim (ftype (function () fixnum) now-ms))
(defun now-ms ()
  (truncate (* 1000 (get-universal-time))))

(declaim (ftype (function () memory-manager) create-memory-manager))
(defun create-memory-manager ()
  (%make-memory-manager))

(declaim (ftype (function (string) list) tokenize))
(defun tokenize (text)
  (declare (type string text))
  (let ((clean (with-output-to-string (out)
                 (loop for ch across (string-downcase text) do
                   (if (alphanumericp ch)
                       (write-char ch out)
                       (write-char #\Space out))))))
    (declare (type string clean))
    (remove-if (lambda (s)
                 (declare (type string s))
                 (string= s ""))
               (uiop:split-string clean :separator '(#\Space)))))

(declaim (ftype (function (string) hash-table) text->embedding))
(defun text->embedding (text)
  "Build a simple normalized term-frequency embedding vector."
  (declare (type string text))
  (let ((vec (make-hash-table :test 'equal))
        (count 0))
    (declare (type hash-table vec)
             (type fixnum count))
    (dolist (token (tokenize text))
      (declare (type string token))
      (incf count)
      (setf (gethash token vec)
            (1+ (truncate (or (gethash token vec) 0)))))
    (when (> count 0)
      (maphash (lambda (k v)
                 (declare (type string k)
                          (type fixnum v))
                 (setf (gethash k vec)
                       (/ (coerce v 'double-float)
                          (coerce count 'double-float))))
               vec))
    vec))

(declaim (ftype (function (hash-table hash-table) double-float) cosine-similarity))
(defun cosine-similarity (a b)
  (declare (type hash-table a b))
  (let ((dot 0.0d0)
        (na 0.0d0)
        (nb 0.0d0))
    (declare (type double-float dot na nb))
    (maphash (lambda (k va)
               (declare (type string k)
                        (type double-float va))
               (let ((vb (gethash k b 0.0d0)))
                 (declare (type double-float vb))
                 (incf dot (* va vb))
                 (incf na (* va va))))
             a)
    (maphash (lambda (_k vb)
               (declare (ignore _k)
                        (type double-float vb))
               (incf nb (* vb vb)))
             b)
    (if (or (<= na 0.0d0) (<= nb 0.0d0))
        0.0d0
        (/ dot (* (sqrt na) (sqrt nb))))))

(declaim (ftype (function (memory-manager string string &key (:metadata (or hash-table null))) memory-item)
                upsert-memory-item))
(defun upsert-memory-item (manager id text &key metadata)
  (declare (type memory-manager manager)
           (type string id text)
           (type (or hash-table null) metadata))
  (let ((item (make-memory-item :id id
                                :text text
                                :embedding (text->embedding text)
                                :metadata (or metadata (make-hash-table :test 'equal))
                                :created-at-ms (now-ms))))
    (declare (type memory-item item))
    (bt:with-lock-held ((memory-manager-lock manager))
      (setf (gethash id (memory-manager-items manager)) item))
    item))

(declaim (ftype (function (memory-manager string) boolean) remove-memory-item))
(defun remove-memory-item (manager id)
  (declare (type memory-manager manager)
           (type string id))
  (bt:with-lock-held ((memory-manager-lock manager))
    (let ((exists (gethash id (memory-manager-items manager))))
      (declare (type t exists))
      (when exists
        (remhash id (memory-manager-items manager))
        t))))

(declaim (ftype (function (memory-manager) list) list-memory-items))
(defun list-memory-items (manager)
  (declare (type memory-manager manager))
  (bt:with-lock-held ((memory-manager-lock manager))
    (let ((items '()))
      (declare (type list items))
      (maphash (lambda (_id item)
                 (declare (ignore _id)
                          (type memory-item item))
                 (push item items))
               (memory-manager-items manager))
      (sort items #'< :key #'memory-item-created-at-ms))))

(declaim (ftype (function (memory-manager string &key (:top-k fixnum)) list) search-memory))
(defun search-memory (manager query &key (top-k 5))
  (declare (type memory-manager manager)
           (type string query)
           (type fixnum top-k))
  (let ((qvec (text->embedding query))
        (results '()))
    (declare (type hash-table qvec)
             (type list results))
    (bt:with-lock-held ((memory-manager-lock manager))
      (maphash
       (lambda (_id item)
         (declare (ignore _id)
                  (type memory-item item))
         (let ((score (cosine-similarity qvec (memory-item-embedding item))))
           (declare (type double-float score))
           (push (make-memory-search-result :item item :score score) results)))
       (memory-manager-items manager)))
    (let ((sorted (sort results #'> :key #'memory-search-result-score)))
      (if (and (> top-k 0) (> (length sorted) top-k))
          (subseq sorted 0 top-k)
          sorted))))