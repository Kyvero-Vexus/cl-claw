;;;; FiveAM tests for cl-claw logging domain
;;;;
;;;; Tests for: timestamps, redact, logger

(defpackage :cl-claw.logging.test
  (:use :cl :fiveam))
(in-package :cl-claw.logging.test)

(def-suite logging-suite
  :description "Tests for the cl-claw logging domain")

(in-suite logging-suite)

;;; ─── timestamps tests ────────────────────────────────────────────────────────

(def-suite timestamps-suite
  :description "Timestamp formatting tests"
  :in logging-suite)

(in-suite timestamps-suite)

(test is-valid-time-zone-accepts-valid-iana
  "Returns true for valid IANA timezones"
  (is-true (cl-claw.logging.timestamps:is-valid-time-zone "UTC"))
  (is-true (cl-claw.logging.timestamps:is-valid-time-zone "America/New_York"))
  (is-true (cl-claw.logging.timestamps:is-valid-time-zone "Asia/Shanghai")))

(test is-valid-time-zone-rejects-invalid
  "Returns false for invalid timezone strings"
  (is-false (cl-claw.logging.timestamps:is-valid-time-zone "not-a-tz"))
  (is-false (cl-claw.logging.timestamps:is-valid-time-zone ""))
  (is-false (cl-claw.logging.timestamps:is-valid-time-zone "yo agent's")))

(test format-local-iso-with-offset-utc
  "Produces +00:00 offset for UTC"
  (let* ((ts (local-time:parse-timestring "2025-01-01T04:00:00.000Z"))
         (result (cl-claw.logging.timestamps:format-local-iso-with-offset ts "UTC")))
    (declare (type string result))
    (is (string= "2025-01-01T04:00:00.000+00:00" result))))

(test format-local-iso-with-offset-shanghai
  "Produces +08:00 offset for Asia/Shanghai"
  (let* ((ts (local-time:parse-timestring "2025-01-01T04:00:00.000Z"))
         (result (cl-claw.logging.timestamps:format-local-iso-with-offset ts "Asia/Shanghai")))
    (declare (type string result))
    (is (string= "2025-01-01T12:00:00.000+08:00" result))))

(test format-local-iso-with-offset-new-york-winter
  "Produces correct -05:00 offset for America/New_York in winter (EST)"
  (let* ((ts (local-time:parse-timestring "2025-01-01T04:00:00.000Z"))
         (result (cl-claw.logging.timestamps:format-local-iso-with-offset ts "America/New_York")))
    (declare (type string result))
    ;; Jan 1 is EST = UTC-5
    (is (string= "2024-12-31T23:00:00.000-05:00" result))))

(test format-local-iso-with-offset-new-york-summer
  "Produces correct -04:00 offset for America/New_York in summer (EDT)"
  (let* ((ts (local-time:parse-timestring "2025-07-01T12:00:00.000Z"))
         (result (cl-claw.logging.timestamps:format-local-iso-with-offset ts "America/New_York")))
    (declare (type string result))
    ;; July is EDT = UTC-4
    (is (string= "2025-07-01T08:00:00.000-04:00" result))))

(test format-local-iso-with-offset-valid-iso8601-format
  "Outputs a valid ISO 8601 string with offset"
  (let* ((ts (local-time:parse-timestring "2025-01-01T04:00:00.000Z"))
         (result (cl-claw.logging.timestamps:format-local-iso-with-offset ts "Asia/Shanghai")))
    (declare (type string result))
    (is (cl-ppcre:scan
         "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}[+-]\\d{2}:\\d{2}$"
         result))))

(test format-local-iso-with-offset-invalid-tz-fallback
  "Falls back gracefully for an invalid timezone"
  (let* ((ts (local-time:parse-timestring "2025-01-01T04:00:00.000Z"))
         (result (cl-claw.logging.timestamps:format-local-iso-with-offset ts "not-a-tz")))
    (declare (type string result))
    ;; Should still produce a valid ISO 8601 string
    (is (cl-ppcre:scan
         "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}[+-]\\d{2}:\\d{2}$"
         result))))

;;; ─── redact tests ────────────────────────────────────────────────────────────

(def-suite redact-suite
  :description "Redaction tests"
  :in logging-suite)

(in-suite redact-suite)

(test redact-sensitive-text-mode-off-returns-unchanged
  "Skips redaction when mode is off"
  (let* ((input "OPENAI_API_KEY=sk-1234567890abcdef")
         (defaults (cl-claw.logging.redact:get-default-redact-patterns))
         (output (cl-claw.logging.redact:redact-sensitive-text
                  input :mode "off" :patterns defaults)))
    (is (string= input output))))

(test redact-sensitive-text-masks-env-assignments
  "Masks env assignments while keeping the key"
  (let* ((input "OPENAI_API_KEY=sk-1234567890abcdef")
         (defaults (cl-claw.logging.redact:get-default-redact-patterns))
         (output (cl-claw.logging.redact:redact-sensitive-text
                  input :mode "tools" :patterns defaults)))
    (declare (type string output))
    ;; Output should contain the key name
    (is (search "OPENAI_API_KEY" output))
    ;; Output should not contain the full secret value
    (is-false (search "sk-1234567890abcdef" output))
    ;; Output should contain ellipsis
    (is (search "…" output))))

(test redact-sensitive-text-ignores-unsafe-patterns
  "Ignores unsafe nested-repetition custom patterns"
  (let* ((input (make-string 28 :initial-element #\a))
         (input (format nil "~a!" input))
         (output (cl-claw.logging.redact:redact-sensitive-text
                  input :mode "tools" :patterns '("(a+)+$"))))
    ;; Unsafe pattern should be skipped, input returned unchanged
    (is (string= input output))))

(test get-default-redact-patterns-returns-list
  "Returns a non-empty list of default patterns"
  (let ((patterns (cl-claw.logging.redact:get-default-redact-patterns)))
    (is (listp patterns))
    (is (> (length patterns) 0))))

(test redact-sensitive-text-tools-mode-is-active
  "Tools mode actively redacts"
  (let* ((defaults (cl-claw.logging.redact:get-default-redact-patterns))
         ;; Use a test string that clearly matches the env assign pattern
         (output (cl-claw.logging.redact:redact-sensitive-text
                  "OPENAI_API_KEY=sk-1234567890abcdef"
                  :mode "tools"
                  :patterns defaults)))
    (declare (type string output))
    ;; The original secret value should not appear verbatim
    (is-false (search "sk-1234567890abcdef" output))))

;;; ─── logger tests ────────────────────────────────────────────────────────────

(def-suite logger-suite
  :description "Logger tests"
  :in logging-suite)

(in-suite logger-suite)

(test parse-log-level-debug
  "Parses 'debug' to level 0"
  (is (= cl-claw.logging.logger:+level-debug+
         (cl-claw.logging.logger:parse-log-level "debug"))))

(test parse-log-level-info
  "Parses 'info' to level 1"
  (is (= cl-claw.logging.logger:+level-info+
         (cl-claw.logging.logger:parse-log-level "info"))))

(test parse-log-level-warn
  "Parses 'warn' to level 2"
  (is (= cl-claw.logging.logger:+level-warn+
         (cl-claw.logging.logger:parse-log-level "warn"))))

(test parse-log-level-error
  "Parses 'error' to level 3"
  (is (= cl-claw.logging.logger:+level-error+
         (cl-claw.logging.logger:parse-log-level "error"))))

(test parse-log-level-silent
  "Parses 'silent' to level 9"
  (is (= cl-claw.logging.logger:+level-silent+
         (cl-claw.logging.logger:parse-log-level "silent"))))

(test parse-log-level-unknown-defaults-to-info
  "Unknown level defaults to info"
  (is (= cl-claw.logging.logger:+level-info+
         (cl-claw.logging.logger:parse-log-level "bogus"))))

(test log-level-name-round-trip
  "Level names round-trip through parse"
  (dolist (name '("debug" "info" "warn" "error" "silent"))
    (declare (type string name))
    (is (string= name
                 (cl-claw.logging.logger:log-level-name
                  (cl-claw.logging.logger:parse-log-level name))))))

(test logger-enabled-p-level-filtering
  "Logger filters messages below configured level"
  (let ((lgr (cl-claw.logging.logger:make-logger
              :level cl-claw.logging.logger:+level-warn+)))
    (declare (type cl-claw.logging.logger:logger lgr))
    (is-false (cl-claw.logging.logger:logger-enabled-p
               lgr cl-claw.logging.logger:+level-debug+))
    (is-false (cl-claw.logging.logger:logger-enabled-p
               lgr cl-claw.logging.logger:+level-info+))
    (is-true  (cl-claw.logging.logger:logger-enabled-p
               lgr cl-claw.logging.logger:+level-warn+))
    (is-true  (cl-claw.logging.logger:logger-enabled-p
               lgr cl-claw.logging.logger:+level-error+))))

(test logger-writes-to-output-stream
  "Logger writes formatted messages to output stream"
  (let ((output (make-string-output-stream)))
    (declare (type stream output))
    (let ((lgr (cl-claw.logging.logger:make-logger
                :level cl-claw.logging.logger:+level-debug+
                :output-stream output)))
      (declare (type cl-claw.logging.logger:logger lgr))
      (cl-claw.logging.logger:log-info lgr "test message ~a" 42))
    (let ((text (get-output-stream-string output)))
      (declare (type string text))
      (is (search "test message 42" text))
      (is (search "info" text)))))

(test logger-silent-level-suppresses-all
  "Silent level suppresses all output"
  (let ((output (make-string-output-stream)))
    (declare (type stream output))
    (let ((lgr (cl-claw.logging.logger:make-logger
                :level cl-claw.logging.logger:+level-silent+
                :output-stream output)))
      (declare (type cl-claw.logging.logger:logger lgr))
      (cl-claw.logging.logger:log-debug lgr "debug msg")
      (cl-claw.logging.logger:log-info  lgr "info msg")
      (cl-claw.logging.logger:log-warn  lgr "warn msg")
      (cl-claw.logging.logger:log-error lgr "error msg"))
    (let ((text (get-output-stream-string output)))
      (declare (type string text))
      (is (string= "" text)))))

(test logger-with-subsystem
  "Logger includes subsystem in output"
  (let ((output (make-string-output-stream)))
    (declare (type stream output))
    (let ((lgr (cl-claw.logging.logger:make-logger
                :level cl-claw.logging.logger:+level-debug+
                :subsystem "mymodule"
                :output-stream output)))
      (declare (type cl-claw.logging.logger:logger lgr))
      (cl-claw.logging.logger:log-info lgr "something happened"))
    (let ((text (get-output-stream-string output)))
      (declare (type string text))
      (is (search "mymodule" text)))))
