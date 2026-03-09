;;;; history.lisp — Session history assembly with truncation
;;;;
;;;; Assembles session transcript messages for inclusion in LLM context,
;;;; with token-aware truncation to fit within budget.

(defpackage :cl-claw.context-engine.history
  (:use :cl)
  (:import-from :cl-claw.context-engine.types
                :agent-message-role
                :agent-message-content)
  (:import-from :cl-claw.context-engine.tokens
                :estimate-message-tokens
                :estimate-messages-tokens
                :estimate-tokens-from-string)
  (:export
   ;; History assembly
   :assemble-history
   :truncate-messages-to-budget
   :truncate-single-message

   ;; Compaction helpers
   :messages-need-compaction-p
   :compute-compaction-threshold))

(in-package :cl-claw.context-engine.history)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Constants
;;; -----------------------------------------------------------------------

(defconstant +compaction-threshold-ratio+ 0.85
  "Trigger compaction when history uses this fraction of token budget.")

(defconstant +compaction-target-ratio+ 0.5
  "Target history size after compaction as fraction of budget.")

(defconstant +max-single-message-tokens+ 8192
  "Maximum tokens for a single message before truncation.")

(defvar +truncation-suffix+ "[truncated]"
  "Suffix appended to truncated message content.")

;;; -----------------------------------------------------------------------
;;; Single message truncation
;;; -----------------------------------------------------------------------

(declaim (ftype (function (hash-table fixnum) hash-table) truncate-single-message))
(defun truncate-single-message (message max-tokens)
  "Truncate a single message's content to fit within MAX-TOKENS.
Returns a new hash-table if truncation was needed, or the original."
  (declare (type hash-table message)
           (type fixnum max-tokens))
  (let ((tokens (estimate-message-tokens message)))
    (declare (type fixnum tokens))
    (if (<= tokens max-tokens)
        message
        ;; Need to truncate content
        (let* ((content (agent-message-content message))
               ;; Subtract role overhead (4 tokens) and suffix
               (content-budget (- max-tokens 4
                                  (estimate-tokens-from-string +truncation-suffix+)))
               (max-chars (* (max 1 content-budget) 4))
               (truncated (if (> (length content) max-chars)
                              (concatenate 'string
                                           (subseq content 0 (min max-chars (length content)))
                                           +truncation-suffix+)
                              content))
               (new-msg (make-hash-table :test 'equal)))
          (declare (type string content truncated)
                   (type fixnum content-budget max-chars)
                   (type hash-table new-msg))
          ;; Copy all keys
          (maphash (lambda (k v)
                     (setf (gethash k new-msg)
                           (if (string= k "content") truncated v)))
                   message)
          new-msg))))

;;; -----------------------------------------------------------------------
;;; History truncation
;;; -----------------------------------------------------------------------

(declaim (ftype (function (list fixnum) list) truncate-messages-to-budget))
(defun truncate-messages-to-budget (messages token-budget)
  "Truncate a list of messages to fit within TOKEN-BUDGET.
Strategy:
1. First, truncate individual oversized messages.
2. If still over budget, drop oldest messages (keeping newest).
3. Always try to keep the first message (system context) if present."
  (declare (type list messages)
           (type fixnum token-budget))
  (when (null messages)
    (return-from truncate-messages-to-budget '()))
  (when (<= token-budget 0)
    (return-from truncate-messages-to-budget '()))

  ;; Step 1: Truncate individual oversized messages
  (let* ((truncated (mapcar (lambda (msg)
                              (truncate-single-message msg +max-single-message-tokens+))
                            messages))
         (total (estimate-messages-tokens truncated)))
    (declare (type list truncated)
             (type fixnum total))

    ;; If under budget, return as-is
    (when (<= total token-budget)
      (return-from truncate-messages-to-budget truncated))

    ;; Step 2: Drop oldest messages until within budget
    ;; Keep dropping from the front (oldest) while over budget
    (let ((result (reverse truncated))
          (running-tokens 0))
      (declare (type list result)
               (type fixnum running-tokens))
      (setf result
            (loop for msg in result
                  for msg-tokens fixnum = (estimate-message-tokens msg)
                  while (<= (+ running-tokens msg-tokens) token-budget)
                  do (incf running-tokens msg-tokens)
                  collect msg))
      (nreverse result))))

;;; -----------------------------------------------------------------------
;;; History assembly
;;; -----------------------------------------------------------------------

(declaim (ftype (function (list fixnum) list) assemble-history))
(defun assemble-history (messages token-budget)
  "Assemble session history messages for inclusion in LLM context.
Applies truncation to fit within TOKEN-BUDGET tokens.
Returns the assembled message list."
  (declare (type list messages)
           (type fixnum token-budget))
  (truncate-messages-to-budget messages token-budget))

;;; -----------------------------------------------------------------------
;;; Compaction helpers
;;; -----------------------------------------------------------------------

(declaim (ftype (function (fixnum) fixnum) compute-compaction-threshold))
(defun compute-compaction-threshold (token-budget)
  "Compute the token count threshold that triggers compaction."
  (declare (type fixnum token-budget))
  (the fixnum (floor (* token-budget +compaction-threshold-ratio+))))

(declaim (ftype (function (list fixnum) boolean) messages-need-compaction-p))
(defun messages-need-compaction-p (messages token-budget)
  "Check if messages exceed the compaction threshold.
Returns T if the messages use more than 85% of the token budget."
  (declare (type list messages)
           (type fixnum token-budget))
  (let ((total (estimate-messages-tokens messages))
        (threshold (compute-compaction-threshold token-budget)))
    (declare (type fixnum total threshold))
    (> total threshold)))
