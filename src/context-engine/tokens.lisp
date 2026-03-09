;;;; tokens.lisp — Token counting & budget enforcement
;;;;
;;;; Provides token estimation (chars/4 heuristic matching OpenClaw),
;;;; model context window lookup, and budget computation.

(defpackage :cl-claw.context-engine.tokens
  (:use :cl)
  (:import-from :cl-claw.context-engine.types
                :agent-message-role
                :agent-message-content)
  (:export
   ;; Token estimation
   :estimate-tokens-from-chars
   :estimate-tokens-from-string
   :estimate-message-tokens
   :estimate-messages-tokens

   ;; Context window lookup
   :+default-context-tokens+
   :lookup-context-tokens
   :resolve-context-tokens

   ;; Budget
   :token-budget
   :make-token-budget
   :token-budget-context-window
   :token-budget-system-prompt-tokens
   :token-budget-history-tokens
   :token-budget-remaining
   :compute-token-budget))

(in-package :cl-claw.context-engine.tokens)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Constants
;;; -----------------------------------------------------------------------

(defconstant +chars-per-token+ 4
  "Rough heuristic: 4 chars ≈ 1 token (conservative for English text).")

(defconstant +default-context-tokens+ 200000
  "Default context window size in tokens (200k), matching OpenClaw.")

;;; -----------------------------------------------------------------------
;;; Token estimation
;;; -----------------------------------------------------------------------

(declaim (ftype (function (fixnum) fixnum) estimate-tokens-from-chars))
(defun estimate-tokens-from-chars (chars)
  "Estimate token count from character count using chars/4 heuristic."
  (declare (type fixnum chars))
  (the fixnum (ceiling (max 0 chars) +chars-per-token+)))

(declaim (ftype (function (string) fixnum) estimate-tokens-from-string))
(defun estimate-tokens-from-string (text)
  "Estimate token count for a string."
  (declare (type string text))
  (estimate-tokens-from-chars (length text)))

(declaim (ftype (function (hash-table) fixnum) estimate-message-tokens))
(defun estimate-message-tokens (message)
  "Estimate token count for a single agent message.
Accounts for role overhead (~4 tokens) plus content."
  (declare (type hash-table message))
  (the fixnum (+ 4 (estimate-tokens-from-string (agent-message-content message)))))

(declaim (ftype (function (list) fixnum) estimate-messages-tokens))
(defun estimate-messages-tokens (messages)
  "Estimate total token count for a list of agent messages."
  (declare (type list messages))
  (the fixnum
       (loop for msg in messages
             sum (estimate-message-tokens msg) fixnum)))

;;; -----------------------------------------------------------------------
;;; Context window lookup — model-specific context windows
;;; -----------------------------------------------------------------------

(defparameter *model-context-windows*
  (let ((table (make-hash-table :test 'equal)))
    ;; Anthropic
    (setf (gethash "claude-3-5-sonnet" table) 200000)
    (setf (gethash "claude-3-5-haiku" table) 200000)
    (setf (gethash "claude-3-opus" table) 200000)
    (setf (gethash "claude-sonnet-4" table) 200000)
    (setf (gethash "claude-opus-4" table) 200000)
    ;; OpenAI
    (setf (gethash "gpt-4o" table) 128000)
    (setf (gethash "gpt-4o-mini" table) 128000)
    (setf (gethash "gpt-4-turbo" table) 128000)
    (setf (gethash "gpt-4" table) 8192)
    (setf (gethash "o1" table) 200000)
    (setf (gethash "o1-mini" table) 128000)
    (setf (gethash "o1-pro" table) 200000)
    (setf (gethash "o3" table) 200000)
    (setf (gethash "o3-mini" table) 200000)
    (setf (gethash "o4-mini" table) 200000)
    ;; Google
    (setf (gethash "gemini-2.0-flash" table) 1048576)
    (setf (gethash "gemini-2.5-pro" table) 1048576)
    (setf (gethash "gemini-2.5-flash" table) 1048576)
    ;; DeepSeek
    (setf (gethash "deepseek-chat" table) 65536)
    (setf (gethash "deepseek-reasoner" table) 65536)
    table)
  "Map from model name fragment to context window size in tokens.")

(declaim (ftype (function (string) (or fixnum null)) lookup-context-tokens))
(defun lookup-context-tokens (model-name)
  "Look up the context window size for a model name.
Tries exact match first, then substring match. Returns nil if unknown."
  (declare (type string model-name))
  (let ((lower (string-downcase model-name)))
    (declare (type string lower))
    ;; Exact match
    (multiple-value-bind (val found) (gethash lower *model-context-windows*)
      (when found
        (return-from lookup-context-tokens (the fixnum val))))
    ;; Substring match — try each known model name
    (maphash (lambda (key val)
               (declare (type string key)
                        (type fixnum val))
               (when (search key lower)
                 (return-from lookup-context-tokens val)))
             *model-context-windows*)
    nil))

(declaim (ftype (function (&key (:model (or string null))
                                (:agent-context-tokens (or fixnum null))
                                (:override (or fixnum null)))
                          fixnum)
                resolve-context-tokens))
(defun resolve-context-tokens (&key model agent-context-tokens override)
  "Resolve the effective context token window.
Priority: override > agent config > model lookup > default."
  (declare (type (or string null) model)
           (type (or fixnum null) agent-context-tokens override))
  (the fixnum
       (or override
           agent-context-tokens
           (and model (lookup-context-tokens model))
           +default-context-tokens+)))

;;; -----------------------------------------------------------------------
;;; Token budget
;;; -----------------------------------------------------------------------

(defstruct token-budget
  "Computed token budget for a context assembly."
  (context-window +default-context-tokens+ :type fixnum)
  (system-prompt-tokens 0 :type fixnum)
  (history-tokens 0 :type fixnum)
  (remaining 0 :type fixnum))

(declaim (ftype (function (&key (:context-window fixnum)
                                (:system-prompt-tokens fixnum)
                                (:reserve-tokens fixnum))
                          token-budget)
                compute-token-budget))
(defun compute-token-budget (&key (context-window +default-context-tokens+)
                                  (system-prompt-tokens 0)
                                  (reserve-tokens 0))
  "Compute a token budget given context window and system prompt size.
RESERVE-TOKENS is additional space to hold back (e.g., for response tokens)."
  (declare (type fixnum context-window system-prompt-tokens reserve-tokens))
  (let* ((available (- context-window system-prompt-tokens reserve-tokens))
         (remaining (max 0 available)))
    (declare (type fixnum available remaining))
    (make-token-budget :context-window context-window
                       :system-prompt-tokens system-prompt-tokens
                       :history-tokens 0
                       :remaining remaining)))
