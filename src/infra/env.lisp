;;;; env.lisp - Environment variable utilities for cl-claw
;;;;
;;;; Implements environment variable helpers for checking truthiness and normalization.
;;;; Based on test specs from tests/cl-adapted/src/infra/env.test.lisp

(defpackage :cl-claw.infra.env
  (:use :cl)
  (:export :is-truthy-env-value
           :normalize-zai-env))
(in-package :cl-claw.infra.env)

(declaim (ftype (function ((or null string)) boolean) is-truthy-env-value))
(defun is-truthy-env-value (value)
  "Check if VALUE is a truthy environment variable value.

Truthy values: '1', 'true', 'yes', 'on' (case-insensitive, whitespace trimmed).
Returns NIL for nil, empty string, or any other value."
  (declare (type (or null string) value))
  (when (and value (stringp value))
    (let ((trimmed (string-trim '(#\Space #\Tab #\Newline) value)))
      (let ((lower (string-downcase trimmed)))
        (or (string= lower "1")
            (string= lower "true")
            (string= lower "yes")
            (string= lower "on"))))))

(declaim (ftype (function () t) normalize-zai-env))
(defun normalize-zai-env ()
  "Normalize z.ai environment variables.

If ZAI_API_KEY is not set (or empty) but Z_AI_API_KEY is set,
copy Z_AI_API_KEY to ZAI_API_KEY. This handles legacy z.ai API key naming."
  (let ((zai-key (uiop:getenv "ZAI_API_KEY"))
        (z-ai-key (uiop:getenv "Z_AI_API_KEY")))
    ;; Only copy if ZAI_API_KEY is empty/missing and Z_AI_API_KEY is non-blank
    (when (and (or (null zai-key) (string= zai-key ""))
               z-ai-key
               (not (string= (string-trim '(#\Space #\Tab) z-ai-key) "")))
      (setf (uiop:getenv "ZAI_API_KEY") z-ai-key))))
