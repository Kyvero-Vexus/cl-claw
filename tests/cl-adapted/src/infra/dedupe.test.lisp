;;;; dedupe.test.lisp - Tests for dedupe module

(defpackage :cl-claw.infra.dedupe.test
  (:use :cl :fiveam))
(in-package :cl-claw.infra.dedupe.test)

(def-suite dedupe-suite
  :description "Tests for the dedupe module")
(in-suite dedupe-suite)

;;; Basic dedupe tracker tests

(test creates-tracker
  "Creates a fresh dedupe tracker"
  (let ((tracker (cl-claw.infra.dedupe:make-dedupe-tracker)))
    (is (not (null tracker)))))

(test new-signature-is-not-seen
  "Returns NIL for an unseen signature"
  (let ((tracker (cl-claw.infra.dedupe:make-dedupe-tracker)))
    (is-false (cl-claw.infra.dedupe:dedupe-tracker-seen-p tracker "sig-1"))))

(test record-returns-true-for-new-signature
  "Returns T (new) when recording a fresh signature"
  (let ((tracker (cl-claw.infra.dedupe:make-dedupe-tracker)))
    (is-true (cl-claw.infra.dedupe:dedupe-tracker-record tracker "sig-1"))))

(test recorded-signature-is-seen
  "After recording, the signature is seen"
  (let ((tracker (cl-claw.infra.dedupe:make-dedupe-tracker)))
    (cl-claw.infra.dedupe:dedupe-tracker-record tracker "sig-1")
    (is-true (cl-claw.infra.dedupe:dedupe-tracker-seen-p tracker "sig-1"))))

(test record-returns-false-for-duplicate
  "Returns NIL (duplicate) when recording same signature again"
  (let ((tracker (cl-claw.infra.dedupe:make-dedupe-tracker)))
    (cl-claw.infra.dedupe:dedupe-tracker-record tracker "sig-1")
    (is-false (cl-claw.infra.dedupe:dedupe-tracker-record tracker "sig-1"))))

(test seen-and-record-returns-false-for-new
  "seen-and-record returns NIL (not a duplicate) for fresh signatures"
  (let ((tracker (cl-claw.infra.dedupe:make-dedupe-tracker)))
    (is-false (cl-claw.infra.dedupe:dedupe-tracker-seen-and-record tracker "sig-new"))))

(test seen-and-record-returns-true-for-duplicate
  "seen-and-record returns T (duplicate) for already-seen signatures"
  (let ((tracker (cl-claw.infra.dedupe:make-dedupe-tracker)))
    (cl-claw.infra.dedupe:dedupe-tracker-seen-and-record tracker "sig-dup")
    (is-true (cl-claw.infra.dedupe:dedupe-tracker-seen-and-record tracker "sig-dup"))))

(test dedupes-warnings-in-once-mode
  "Dedupes repeated signatures"
  (let ((tracker (cl-claw.infra.dedupe:make-dedupe-tracker))
        (count 0))
    (dotimes (i 3)
      (unless (cl-claw.infra.dedupe:dedupe-tracker-seen-and-record tracker "warning-1")
        (incf count)))
    ;; Only the first occurrence should be counted
    (is (= count 1))))

(test dedupes-once-mode-across-non-consecutive-repeated-signatures
  "Dedupes across non-consecutive occurrences of same signature"
  (let ((tracker (cl-claw.infra.dedupe:make-dedupe-tracker))
        (recorded '()))
    (dolist (sig '("a" "b" "a" "c" "b"))
      (unless (cl-claw.infra.dedupe:dedupe-tracker-seen-and-record tracker sig)
        (push sig recorded)))
    ;; Should only record a, b, c (3 unique)
    (is (= 3 (length recorded)))))

(test clear-removes-all-signatures
  "Clearing the tracker removes all signatures"
  (let ((tracker (cl-claw.infra.dedupe:make-dedupe-tracker)))
    (cl-claw.infra.dedupe:dedupe-tracker-record tracker "a")
    (cl-claw.infra.dedupe:dedupe-tracker-record tracker "b")
    (cl-claw.infra.dedupe:dedupe-tracker-clear tracker)
    (is (= 0 (cl-claw.infra.dedupe:dedupe-tracker-size tracker)))
    (is-false (cl-claw.infra.dedupe:dedupe-tracker-seen-p tracker "a"))))

(test clear-specific-signature
  "Clearing a specific signature removes only that signature"
  (let ((tracker (cl-claw.infra.dedupe:make-dedupe-tracker)))
    (cl-claw.infra.dedupe:dedupe-tracker-record tracker "a")
    (cl-claw.infra.dedupe:dedupe-tracker-record tracker "b")
    (cl-claw.infra.dedupe:dedupe-tracker-clear tracker "a")
    (is-false (cl-claw.infra.dedupe:dedupe-tracker-seen-p tracker "a"))
    (is-true (cl-claw.infra.dedupe:dedupe-tracker-seen-p tracker "b"))))

(test size-tracks-unique-signatures
  "Size returns the count of unique recorded signatures"
  (let ((tracker (cl-claw.infra.dedupe:make-dedupe-tracker)))
    (is (= 0 (cl-claw.infra.dedupe:dedupe-tracker-size tracker)))
    (cl-claw.infra.dedupe:dedupe-tracker-record tracker "x")
    (cl-claw.infra.dedupe:dedupe-tracker-record tracker "y")
    (cl-claw.infra.dedupe:dedupe-tracker-record tracker "x")  ; duplicate
    (is (= 2 (cl-claw.infra.dedupe:dedupe-tracker-size tracker)))))

;;; LRU dedupe tests

(test lru-dedupe-basic-deduplication
  "LRU dedupe correctly deduplicates"
  (let ((lru (cl-claw.infra.dedupe:make-lru-dedupe :max-size 5)))
    (is-true (cl-claw.infra.dedupe:lru-dedupe-record lru "sig-1"))
    (is-false (cl-claw.infra.dedupe:lru-dedupe-record lru "sig-1"))))

(test lru-dedupe-evicts-oldest-when-full
  "LRU dedupe evicts oldest entry when max-size is reached"
  (let ((lru (cl-claw.infra.dedupe:make-lru-dedupe :max-size 3)))
    (cl-claw.infra.dedupe:lru-dedupe-record lru "a")
    (cl-claw.infra.dedupe:lru-dedupe-record lru "b")
    (cl-claw.infra.dedupe:lru-dedupe-record lru "c")
    ;; At capacity; adding "d" should evict "a"
    (cl-claw.infra.dedupe:lru-dedupe-record lru "d")
    ;; "a" should be evicted and appear as new again
    (is-true (cl-claw.infra.dedupe:lru-dedupe-record lru "a"))))
