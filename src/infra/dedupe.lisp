;;;; dedupe.lisp - Deduplication utilities for cl-claw
;;;;
;;;; Provides deduplication helpers for preventing duplicate processing
;;;; of events, messages, and tool outputs.

(defpackage :cl-claw.infra.dedupe
  (:use :cl)
  (:export :make-dedupe-tracker
           :dedupe-tracker-seen-p
           :dedupe-tracker-record
           :dedupe-tracker-seen-and-record
           :dedupe-tracker-clear
           :dedupe-tracker-size
           :make-lru-dedupe
           :lru-dedupe-seen-p
           :lru-dedupe-record))
(in-package :cl-claw.infra.dedupe)

;;; Simple deduplication tracker (unbounded)

(defstruct dedupe-tracker
  "Tracks seen signatures for deduplication."
  (table (make-hash-table :test #'equal) :type hash-table))

(defun dedupe-tracker-seen-p (tracker signature)
  "Return T if SIGNATURE has already been seen."
  (declare (type dedupe-tracker tracker))
  (nth-value 1 (gethash signature (dedupe-tracker-table tracker))))

(defun dedupe-tracker-record (tracker signature)
  "Record SIGNATURE as seen. Returns T if it was new (not a duplicate)."
  (declare (type dedupe-tracker tracker))
  (let ((already-seen (dedupe-tracker-seen-p tracker signature)))
    (setf (gethash signature (dedupe-tracker-table tracker)) t)
    (not already-seen)))

(defun dedupe-tracker-seen-and-record (tracker signature)
  "Check and record SIGNATURE atomically.
Returns T if it was already seen (is a duplicate), NIL if it was new."
  (declare (type dedupe-tracker tracker))
  (let ((was-seen (dedupe-tracker-seen-p tracker signature)))
    (setf (gethash signature (dedupe-tracker-table tracker)) t)
    was-seen))

(defun dedupe-tracker-clear (tracker &optional signature)
  "Clear all seen signatures, or just SIGNATURE if provided."
  (declare (type dedupe-tracker tracker))
  (if signature
      (remhash signature (dedupe-tracker-table tracker))
      (clrhash (dedupe-tracker-table tracker))))

(defun dedupe-tracker-size (tracker)
  "Return the number of tracked signatures."
  (declare (type dedupe-tracker tracker))
  (hash-table-count (dedupe-tracker-table tracker)))

;;; LRU-bounded deduplication tracker
;;; Uses a separate struct name (lru-dedupe-state) internally
;;; to avoid conflict with the public make-lru-dedupe constructor.

(defstruct (lru-dedupe-state (:constructor %make-lru-dedupe-state))
  "Internal LRU-bounded deduplication tracker state."
  (table (make-hash-table :test #'equal) :type hash-table)
  (order nil :type list)               ; list of keys in insertion order (oldest first)
  (max-size 1000 :type (integer 1)))

;; Public type alias
(deftype lru-dedupe () 'lru-dedupe-state)

(defun make-lru-dedupe (&key (max-size 1000))
  "Create an LRU-bounded dedupe tracker with MAX-SIZE capacity."
  (%make-lru-dedupe-state :max-size max-size))

(defun lru-dedupe-seen-p (lru signature)
  "Return T if SIGNATURE has been seen in this LRU tracker."
  (declare (type lru-dedupe-state lru))
  (nth-value 1 (gethash signature (lru-dedupe-state-table lru))))

(defun lru-dedupe-record (lru signature)
  "Record SIGNATURE. Returns T if it was new (not a duplicate).
Evicts oldest entry when max-size is exceeded."
  (declare (type lru-dedupe-state lru))
  (let ((was-seen (lru-dedupe-seen-p lru signature)))
    (unless was-seen
      ;; Evict oldest if at capacity
      (when (>= (hash-table-count (lru-dedupe-state-table lru))
                (lru-dedupe-state-max-size lru))
        (let ((oldest (pop (lru-dedupe-state-order lru))))
          (remhash oldest (lru-dedupe-state-table lru))))
      (setf (gethash signature (lru-dedupe-state-table lru)) t)
      (setf (lru-dedupe-state-order lru)
            (append (lru-dedupe-state-order lru) (list signature))))
    (not was-seen)))
