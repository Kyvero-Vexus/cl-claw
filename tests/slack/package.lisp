;;;; package.lisp — Slack domain test suite
;;;;
;;;; Adapted from 49 upstream OpenClaw Slack test specification files.
;;;; Covers: accounts, actions, blocks, channel migration, client config,
;;;; draft streaming, formatting, HTTP registry, message actions, modals,
;;;; monitor (events, auth, context, media, message-handler, provider,
;;;; replies, slash commands), allowlists, channel/user resolution,
;;;; send (blocks, upload), thread cache, stream mode, targets, threading.

(defpackage :cl-claw.slack.tests
  (:use :cl :fiveam)
  (:export :run-slack-tests))

(in-package :cl-claw.slack.tests)

(declaim (optimize (safety 3) (debug 3)))

;;; ── Top-level suite ──────────────────────────────────────────────────

(def-suite :cl-claw.slack.tests
  :description "Slack domain test suite (49 spec files, 438 specs)")

;;; ── Sub-suites by spec file ──────────────────────────────────────────

(def-suite :slack-accounts          :in :cl-claw.slack.tests)
(def-suite :slack-actions-blocks    :in :cl-claw.slack.tests)
(def-suite :slack-actions-download  :in :cl-claw.slack.tests)
(def-suite :slack-actions-read      :in :cl-claw.slack.tests)
(def-suite :slack-blocks-fallback   :in :cl-claw.slack.tests)
(def-suite :slack-blocks-input      :in :cl-claw.slack.tests)
(def-suite :slack-channel-migration :in :cl-claw.slack.tests)
(def-suite :slack-client            :in :cl-claw.slack.tests)
(def-suite :slack-draft-stream      :in :cl-claw.slack.tests)
(def-suite :slack-format            :in :cl-claw.slack.tests)
(def-suite :slack-http-registry     :in :cl-claw.slack.tests)
(def-suite :slack-message-actions   :in :cl-claw.slack.tests)
(def-suite :slack-modal-metadata    :in :cl-claw.slack.tests)
(def-suite :slack-monitor           :in :cl-claw.slack.tests)
(def-suite :slack-monitor-threading-missing :in :cl-claw.slack.tests)
(def-suite :slack-monitor-tool-result :in :cl-claw.slack.tests)
(def-suite :slack-allow-list        :in :cl-claw.slack.tests)
(def-suite :slack-auth              :in :cl-claw.slack.tests)
(def-suite :slack-monitor-context   :in :cl-claw.slack.tests)
(def-suite :slack-events-channels   :in :cl-claw.slack.tests)
(def-suite :slack-events-interactions :in :cl-claw.slack.tests)
(def-suite :slack-events-members    :in :cl-claw.slack.tests)
(def-suite :slack-events-subtype    :in :cl-claw.slack.tests)
(def-suite :slack-events-messages   :in :cl-claw.slack.tests)
(def-suite :slack-events-pins       :in :cl-claw.slack.tests)
(def-suite :slack-events-reactions  :in :cl-claw.slack.tests)
(def-suite :slack-media             :in :cl-claw.slack.tests)
(def-suite :slack-msg-handler-race  :in :cl-claw.slack.tests)
(def-suite :slack-msg-handler-debounce :in :cl-claw.slack.tests)
(def-suite :slack-msg-handler       :in :cl-claw.slack.tests)
(def-suite :slack-dispatch-streaming :in :cl-claw.slack.tests)
(def-suite :slack-prepare           :in :cl-claw.slack.tests)
(def-suite :slack-prepare-thread-key :in :cl-claw.slack.tests)
(def-suite :slack-monitor-monitor   :in :cl-claw.slack.tests)
(def-suite :slack-provider-auth-errors :in :cl-claw.slack.tests)
(def-suite :slack-provider-group-policy :in :cl-claw.slack.tests)
(def-suite :slack-provider-reconnect :in :cl-claw.slack.tests)
(def-suite :slack-monitor-replies   :in :cl-claw.slack.tests)
(def-suite :slack-slash             :in :cl-claw.slack.tests)
(def-suite :slack-resolve-allowlist :in :cl-claw.slack.tests)
(def-suite :slack-resolve-channels  :in :cl-claw.slack.tests)
(def-suite :slack-resolve-users     :in :cl-claw.slack.tests)
(def-suite :slack-send-blocks       :in :cl-claw.slack.tests)
(def-suite :slack-send-upload       :in :cl-claw.slack.tests)
(def-suite :slack-sent-thread-cache :in :cl-claw.slack.tests)
(def-suite :slack-stream-mode       :in :cl-claw.slack.tests)
(def-suite :slack-targets           :in :cl-claw.slack.tests)
(def-suite :slack-threading-tool-ctx :in :cl-claw.slack.tests)
(def-suite :slack-threading         :in :cl-claw.slack.tests)

;;; ── Helpers ──────────────────────────────────────────────────────────

(defun run-slack-tests ()
  "Run the complete Slack domain test suite."
  (run! :cl-claw.slack.tests))

(defun hash (&rest kv)
  "Create hash table from key-value pairs."
  (let ((h (make-hash-table :test 'equal)))
    (loop for (k v) on kv by #'cddr do
      (setf (gethash k h) v))
    h))

(defun make-test-config (&rest pairs)
  "Create a test config hash table."
  (apply #'hash pairs))

(defun make-slack-config (&rest overrides)
  "Base Slack channel config with optional overrides."
  (let ((cfg (hash "channels" (hash "slack" (apply #'hash overrides)))))
    cfg))

(defun make-slack-event (&rest kv)
  "Create a mock Slack event payload."
  (apply #'hash kv))

(defun make-slack-message (&key channel thread-ts ts text user (type "message"))
  "Create a mock Slack message event."
  (let ((msg (hash "type" type "text" (or text ""))))
    (when channel (setf (gethash "channel" msg) channel))
    (when thread-ts (setf (gethash "thread_ts" msg) thread-ts))
    (when ts (setf (gethash "ts" msg) ts))
    (when user (setf (gethash "user" msg) user))
    msg))

(defun make-blocks (&rest block-specs)
  "Create a list of Slack block kit blocks."
  (mapcar (lambda (spec)
            (if (hash-table-p spec) spec
                (hash "type" (car spec) "text" (cadr spec))))
          block-specs))

(defvar *mock-call-log* nil
  "Accumulator for mock function calls.")

(defun reset-mocks ()
  "Clear mock call log."
  (setf *mock-call-log* nil))

(defun record-call (name &rest args)
  "Record a mock call."
  (push (cons name args) *mock-call-log*))

(defun mock-calls (name)
  "Return recorded calls for NAME."
  (remove-if-not (lambda (entry) (equal (car entry) name))
                 (reverse *mock-call-log*)))

(defun mock-call-count (name)
  "Count of calls for NAME."
  (length (mock-calls name)))
