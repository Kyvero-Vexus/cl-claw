;;;; core.lisp — Context engine core — prompt assembly
;;;;
;;;; The top-level context engine API that orchestrates prompt assembly,
;;;; workspace file injection, token budget computation, and history
;;;; assembly into a complete context for LLM calls.

(defpackage :cl-claw.context-engine
  (:use :cl)
  (:import-from :cl-claw.context-engine.types
                :context-engine
                :engine-info
                :engine-ingest
                :engine-assemble
                :engine-compact
                :engine-dispose
                :context-engine-info
                :context-engine-info-id
                :context-engine-info-name
                :context-engine-info-version
                :ingest-result
                :make-ingest-result
                :ingest-result-ingested-p
                :assemble-result
                :make-assemble-result
                :assemble-result-messages
                :assemble-result-estimated-tokens
                :assemble-result-system-prompt-addition
                :compact-result
                :make-compact-result
                :compact-result-ok-p
                :compact-result-compacted-p
                :compact-result-reason
                :compact-result-detail
                :compact-result-detail
                :make-compact-result-detail
                :compact-result-detail-summary
                :compact-result-detail-tokens-before
                :compact-result-detail-tokens-after
                :context-file
                :make-context-file
                :context-file-path
                :context-file-content)
  (:import-from :cl-claw.context-engine.tokens
                :+default-context-tokens+
                :estimate-tokens-from-chars
                :estimate-tokens-from-string
                :estimate-message-tokens
                :estimate-messages-tokens
                :lookup-context-tokens
                :resolve-context-tokens
                :token-budget
                :make-token-budget
                :token-budget-context-window
                :token-budget-system-prompt-tokens
                :token-budget-remaining
                :compute-token-budget)
  (:import-from :cl-claw.context-engine.workspace
                :+default-workspace-files+
                :+max-workspace-file-bytes+
                :read-workspace-file
                :load-workspace-context-files
                :strip-front-matter
                :format-context-files-section)
  (:import-from :cl-claw.context-engine.prompt
                :runtime-info
                :make-runtime-info
                :system-prompt-params
                :make-system-prompt-params
                :system-prompt-params-context-files
                :system-prompt-params-workspace-dir
                :system-prompt-params-prompt-mode
                :copy-system-prompt-params
                :build-agent-system-prompt
                :build-runtime-line
                :build-system-prompt-report
                :sanitize-for-prompt-literal)
  (:import-from :cl-claw.context-engine.history
                :assemble-history
                :truncate-messages-to-budget
                :truncate-single-message
                :messages-need-compaction-p
                :compute-compaction-threshold)
  (:import-from :cl-claw.context-engine.registry
                :register-context-engine
                :get-context-engine-factory
                :list-context-engine-ids
                :resolve-context-engine
                :legacy-context-engine
                :register-legacy-context-engine
                :ensure-context-engines-initialized)
  (:export
   ;; Re-export types
   :context-engine
   :engine-info
   :engine-ingest
   :engine-assemble
   :engine-compact
   :engine-dispose
   :context-engine-info
   :context-engine-info-id
   :context-engine-info-name
   :context-engine-info-version
   :ingest-result
   :make-ingest-result
   :ingest-result-ingested-p
   :assemble-result
   :make-assemble-result
   :assemble-result-messages
   :assemble-result-estimated-tokens
   :assemble-result-system-prompt-addition
   :compact-result
   :make-compact-result
   :compact-result-ok-p
   :compact-result-compacted-p
   :compact-result-reason
   :compact-result-detail
   :compact-result-detail
   :make-compact-result-detail
   :compact-result-detail-summary
   :compact-result-detail-tokens-before
   :compact-result-detail-tokens-after
   :context-file
   :make-context-file
   :context-file-path
   :context-file-content

   ;; Re-export tokens
   :+default-context-tokens+
   :estimate-tokens-from-chars
   :estimate-tokens-from-string
   :estimate-message-tokens
   :estimate-messages-tokens
   :lookup-context-tokens
   :resolve-context-tokens
   :token-budget
   :make-token-budget
   :token-budget-context-window
   :token-budget-system-prompt-tokens
   :token-budget-remaining
   :compute-token-budget

   ;; Re-export workspace
   :+default-workspace-files+
   :+max-workspace-file-bytes+
   :read-workspace-file
   :load-workspace-context-files
   :strip-front-matter
   :format-context-files-section

   ;; Re-export prompt
   :runtime-info
   :make-runtime-info
   :system-prompt-params
   :make-system-prompt-params
   :copy-system-prompt-params
   :system-prompt-params-context-files
   :system-prompt-params-workspace-dir
   :system-prompt-params-prompt-mode
   :build-agent-system-prompt
   :build-runtime-line
   :build-system-prompt-report
   :sanitize-for-prompt-literal

   ;; Re-export history
   :assemble-history
   :truncate-messages-to-budget
   :truncate-single-message
   :messages-need-compaction-p
   :compute-compaction-threshold

   ;; Re-export registry
   :register-context-engine
   :get-context-engine-factory
   :list-context-engine-ids
   :resolve-context-engine
   :legacy-context-engine
   :register-legacy-context-engine
   :ensure-context-engines-initialized

   ;; Top-level API
   :build-full-context))

(in-package :cl-claw.context-engine)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Top-level context assembly API
;;; -----------------------------------------------------------------------

(defstruct full-context
  "Complete assembled context ready for LLM submission."
  (system-prompt "" :type string)
  (messages '() :type list)
  (token-budget nil :type (or token-budget null))
  (estimated-tokens 0 :type fixnum)
  (context-files '() :type list)
  (engine-addition nil :type (or string null)))

(declaim (ftype (function (&key (:workspace-dir string)
                                (:model (or string null))
                                (:messages list)
                                (:prompt-params (or system-prompt-params null))
                                (:context-tokens-override (or fixnum null))
                                (:agent-context-tokens (or fixnum null))
                                (:reserve-tokens fixnum)
                                (:engine (or context-engine null))
                                (:session-id (or string null)))
                          full-context)
                build-full-context))
(defun build-full-context (&key (workspace-dir "")
                                model
                                (messages '())
                                prompt-params
                                context-tokens-override
                                agent-context-tokens
                                (reserve-tokens 4096)
                                engine
                                session-id)
  "Build a complete context for an LLM call.

Orchestrates:
1. Workspace file loading (from PROMPT-PARAMS context-files, or loaded from disk)
2. System prompt construction
3. Token budget computation
4. History assembly with truncation
5. Context engine augmentation (if engine provided)

Returns a FULL-CONTEXT struct."
  (declare (type string workspace-dir)
           (type (or string null) model session-id)
           (type list messages)
           (type (or system-prompt-params null) prompt-params)
           (type (or fixnum null) context-tokens-override agent-context-tokens)
           (type fixnum reserve-tokens)
           (type (or context-engine null) engine))

  ;; 1. Load context files if not already provided
  (let* ((params (or prompt-params
                     (make-system-prompt-params :workspace-dir workspace-dir)))
         (context-files (system-prompt-params-context-files params))
         (context-files (if context-files
                            context-files
                            (when (and (plusp (length workspace-dir))
                                       (uiop:directory-exists-p workspace-dir))
                              (load-workspace-context-files workspace-dir))))
         ;; Update params with loaded files if needed
         (params (if (and (null (system-prompt-params-context-files params))
                          context-files)
                     (let ((p (copy-system-prompt-params params)))
                       (setf (system-prompt-params-context-files p) context-files)
                       p)
                     params)))

    ;; 2. Build system prompt
    (let* ((system-prompt (build-agent-system-prompt params))
           (system-tokens (estimate-tokens-from-string system-prompt)))

      ;; 3. Compute token budget
      (let* ((ctx-window (resolve-context-tokens :model model
                                                  :agent-context-tokens agent-context-tokens
                                                  :override context-tokens-override))
             (budget (compute-token-budget :context-window ctx-window
                                           :system-prompt-tokens system-tokens
                                           :reserve-tokens reserve-tokens))
             (history-budget (token-budget-remaining budget)))

        ;; 4. Assemble history with truncation
        (let* ((assembled-messages (assemble-history messages history-budget))
               (history-tokens (estimate-messages-tokens assembled-messages))
               ;; 5. Context engine augmentation
               (engine-result (when (and engine session-id)
                                (engine-assemble engine session-id assembled-messages
                                                 :token-budget history-budget)))
               (final-messages (if engine-result
                                   (assemble-result-messages engine-result)
                                   assembled-messages))
               (engine-addition (when engine-result
                                  (assemble-result-system-prompt-addition engine-result)))
               (total-tokens (+ system-tokens
                                (if engine-result
                                    (assemble-result-estimated-tokens engine-result)
                                    history-tokens))))

          ;; Build the final system prompt with engine additions
          (let ((final-prompt (if (and engine-addition (plusp (length engine-addition)))
                                  (format nil "~A~%~%~A" system-prompt engine-addition)
                                  system-prompt)))

            (make-full-context :system-prompt final-prompt
                               :messages final-messages
                               :token-budget budget
                               :estimated-tokens total-tokens
                               :context-files (or context-files '())
                               :engine-addition engine-addition)))))))
