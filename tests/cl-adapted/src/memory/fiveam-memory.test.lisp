;;;; FiveAM tests for memory domain

(defpackage :cl-claw.memory.test
  (:use :cl :fiveam))

(in-package :cl-claw.memory.test)

(declaim (optimize (safety 3) (debug 3)))

(def-suite memory-suite
  :description "Tests for memory embeddings/search manager")

(in-suite memory-suite)

(test text-embedding-has-token-weights
  (let ((vec (cl-claw.memory:text->embedding "hello hello world")))
    (is (> (gethash "hello" vec 0.0d0)
           (gethash "world" vec 0.0d0)))
    (is (> (gethash "world" vec 0.0d0) 0.0d0))))

(test upsert-and-list-memory-items
  (let ((manager (cl-claw.memory:create-memory-manager)))
    (cl-claw.memory:upsert-memory-item manager "1" "alpha beta")
    (cl-claw.memory:upsert-memory-item manager "2" "gamma delta")
    (let ((items (cl-claw.memory:list-memory-items manager)))
      (is (= 2 (length items)))
      (is (find "1" items :key #'cl-claw.memory:memory-item-id :test #'string=))
      (is (find "2" items :key #'cl-claw.memory:memory-item-id :test #'string=)))))

(test search-memory-returns-best-match-first
  (let ((manager (cl-claw.memory:create-memory-manager)))
    (cl-claw.memory:upsert-memory-item manager "a" "lisp macros and compilers")
    (cl-claw.memory:upsert-memory-item manager "b" "gardening and tomatoes")
    (let ((results (cl-claw.memory:search-memory manager "lisp compiler" :top-k 1)))
      (is (= 1 (length results)))
      (is (string= "a"
                   (cl-claw.memory:memory-item-id
                    (cl-claw.memory:memory-search-result-item (first results))))))))

(test remove-memory-item-works
  (let ((manager (cl-claw.memory:create-memory-manager)))
    (cl-claw.memory:upsert-memory-item manager "dead" "temporary")
    (is-true (cl-claw.memory:remove-memory-item manager "dead"))
    (is-false (cl-claw.memory:remove-memory-item manager "dead"))))