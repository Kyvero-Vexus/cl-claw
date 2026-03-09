;;;; fiveam-context-engine.test.lisp — Tests for the context engine
;;;;
;;;; Covers: types, tokens, workspace, prompt, history, registry, core.

(defpackage :cl-claw.context-engine.test
  (:use :cl :fiveam)
  (:import-from :cl-claw.context-engine.types
                :make-context-engine-info)
  (:import-from :cl-claw.context-engine
                ;; Types
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
                :make-compact-result-detail
                :compact-result-detail-summary
                :compact-result-detail-tokens-before
                :compact-result-detail-tokens-after
                :context-file
                :make-context-file
                :context-file-path
                :context-file-content
                ;; Tokens
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
                ;; Workspace
                :+default-workspace-files+
                :+max-workspace-file-bytes+
                :strip-front-matter
                :load-workspace-context-files
                :format-context-files-section
                ;; Prompt
                :runtime-info
                :make-runtime-info
                :system-prompt-params
                :make-system-prompt-params
                :build-agent-system-prompt
                :build-runtime-line
                :sanitize-for-prompt-literal
                ;; History
                :assemble-history
                :truncate-messages-to-budget
                :truncate-single-message
                :messages-need-compaction-p
                :compute-compaction-threshold
                ;; Registry
                :register-context-engine
                :get-context-engine-factory
                :list-context-engine-ids
                :resolve-context-engine
                :legacy-context-engine
                :register-legacy-context-engine
                :ensure-context-engines-initialized
                ;; Core
                :build-full-context))

(in-package :cl-claw.context-engine.test)

(def-suite context-engine-suite
  :description "Context engine tests")

(in-suite context-engine-suite)

;;; -----------------------------------------------------------------------
;;; Helper utilities
;;; -----------------------------------------------------------------------

(defun make-test-message (role content &optional (timestamp 0))
  "Create a test agent message hash-table."
  (let ((msg (make-hash-table :test 'equal)))
    (setf (gethash "role" msg) role)
    (setf (gethash "content" msg) content)
    (setf (gethash "timestampMs" msg) timestamp)
    msg))

(defun make-temp-workspace ()
  "Create a temporary workspace directory with test files."
  (let* ((dir (format nil "/tmp/cl-claw-ctx-test-~A/" (get-universal-time)))
         (dir-path (ensure-directories-exist
                    (uiop:ensure-directory-pathname dir))))
    ;; Create SOUL.md
    (with-open-file (s (merge-pathnames "SOUL.md" dir-path)
                       :direction :output :if-exists :supersede)
      (write-string "# SOUL.md
You are a helpful assistant." s))
    ;; Create AGENTS.md
    (with-open-file (s (merge-pathnames "AGENTS.md" dir-path)
                       :direction :output :if-exists :supersede)
      (write-string "# AGENTS.md
Follow these instructions." s))
    ;; Create TOOLS.md
    (with-open-file (s (merge-pathnames "TOOLS.md" dir-path)
                       :direction :output :if-exists :supersede)
      (write-string "# TOOLS.md
Tool notes here." s))
    (namestring dir-path)))

(defun cleanup-temp-workspace (dir)
  "Remove a temporary workspace directory."
  (uiop:delete-directory-tree (pathname dir) :validate t :if-does-not-exist :ignore))

;;; =======================================================================
;;; 1. Token estimation tests
;;; =======================================================================

(test token-estimation-chars
  "estimate-tokens-from-chars uses chars/4 heuristic"
  (is (= 0 (estimate-tokens-from-chars 0)))
  (is (= 1 (estimate-tokens-from-chars 1)))
  (is (= 1 (estimate-tokens-from-chars 4)))
  (is (= 2 (estimate-tokens-from-chars 5)))
  (is (= 25 (estimate-tokens-from-chars 100)))
  (is (= 0 (estimate-tokens-from-chars -5))))

(test token-estimation-string
  "estimate-tokens-from-string estimates token count"
  (is (= 0 (estimate-tokens-from-string "")))
  (is (= 3 (estimate-tokens-from-string "hello world")))
  (is (= 25 (estimate-tokens-from-string (make-string 100 :initial-element #\a)))))

(test token-estimation-message
  "estimate-message-tokens adds role overhead"
  (let ((msg (make-test-message "user" "hello")))
    ;; 4 overhead + ceil(5/4) = 4 + 2 = 6
    (is (= 6 (estimate-message-tokens msg)))))

(test token-estimation-messages
  "estimate-messages-tokens sums token counts"
  (let ((msgs (list (make-test-message "user" "hello")
                    (make-test-message "assistant" "world"))))
    (let ((total (estimate-messages-tokens msgs)))
      (is (> total 0))
      ;; Should be sum of individual estimates
      (is (= total (+ (estimate-message-tokens (first msgs))
                       (estimate-message-tokens (second msgs))))))))

;;; =======================================================================
;;; 2. Context window lookup tests
;;; =======================================================================

(test context-window-defaults
  "default context tokens is 200000"
  (is (= 200000 +default-context-tokens+)))

(test context-window-lookup-known
  "lookup-context-tokens finds known models"
  (is (= 200000 (lookup-context-tokens "claude-3-5-sonnet")))
  (is (= 128000 (lookup-context-tokens "gpt-4o")))
  (is (= 1048576 (lookup-context-tokens "gemini-2.5-pro"))))

(test context-window-lookup-unknown
  "lookup-context-tokens returns nil for unknown models"
  (is (null (lookup-context-tokens "unknown-model-xyz"))))

(test context-window-lookup-case-insensitive
  "lookup-context-tokens is case-insensitive"
  (is (= 200000 (lookup-context-tokens "Claude-3-5-Sonnet"))))

(test resolve-context-tokens-priority
  "resolve-context-tokens respects priority: override > agent > model > default"
  ;; Override wins
  (is (= 1000 (resolve-context-tokens :model "claude-3-5-sonnet"
                                       :agent-context-tokens 2000
                                       :override 1000)))
  ;; Agent config wins over model
  (is (= 2000 (resolve-context-tokens :model "claude-3-5-sonnet"
                                       :agent-context-tokens 2000)))
  ;; Model lookup
  (is (= 200000 (resolve-context-tokens :model "claude-3-5-sonnet")))
  ;; Default fallback
  (is (= 200000 (resolve-context-tokens))))

;;; =======================================================================
;;; 3. Token budget tests
;;; =======================================================================

(test token-budget-computation
  "compute-token-budget correctly computes remaining tokens"
  (let ((budget (compute-token-budget :context-window 100000
                                       :system-prompt-tokens 10000
                                       :reserve-tokens 5000)))
    (is (= 100000 (token-budget-context-window budget)))
    (is (= 10000 (token-budget-system-prompt-tokens budget)))
    (is (= 85000 (token-budget-remaining budget)))))

(test token-budget-zero-floor
  "compute-token-budget floors remaining at 0"
  (let ((budget (compute-token-budget :context-window 100
                                       :system-prompt-tokens 200
                                       :reserve-tokens 0)))
    (is (= 0 (token-budget-remaining budget)))))

;;; =======================================================================
;;; 4. Workspace file tests
;;; =======================================================================

(test strip-front-matter-basic
  "strip-front-matter removes YAML front matter"
  (is (string= "Content here"
                (strip-front-matter "---
title: Test
---
Content here")))
  ;; No front matter
  (is (string= "No front matter" (strip-front-matter "No front matter")))
  ;; Incomplete front matter (no closing ---)
  (is (string= "---
just dashes" (strip-front-matter "---
just dashes"))))

(test load-workspace-files
  "load-workspace-context-files loads existing files"
  (let ((dir (make-temp-workspace)))
    (unwind-protect
         (let ((files (load-workspace-context-files dir)))
           ;; Should find SOUL.md, AGENTS.md, TOOLS.md (not IDENTITY.md, USER.md)
           (is (= 3 (length files)))
           (is (every (lambda (cf)
                        (and (plusp (length (context-file-path cf)))
                             (plusp (length (context-file-content cf)))))
                      files)))
      (cleanup-temp-workspace dir))))

(test format-context-files-empty
  "format-context-files-section returns empty for no files"
  (is (string= "" (format-context-files-section '()))))

(test format-context-files-with-soul
  "format-context-files-section includes SOUL.md guidance when present"
  (let ((files (list (make-context-file :path "SOUL.md" :content "Be helpful.")
                     (make-context-file :path "TOOLS.md" :content "Notes."))))
    (let ((section (format-context-files-section files)))
      (is (search "# Project Context" section))
      (is (search "SOUL.md" section))
      (is (search "embody its persona" section))
      (is (search "Be helpful." section))
      (is (search "TOOLS.md" section)))))

;;; =======================================================================
;;; 5. Prompt construction tests
;;; =======================================================================

(test sanitize-prompt-literal
  "sanitize-for-prompt-literal handles control characters"
  (is (string= "hello world" (sanitize-for-prompt-literal "hello world")))
  (is (string= "a b" (sanitize-for-prompt-literal (format nil "a~Cb" #\Newline))))
  (is (string= "ab" (sanitize-for-prompt-literal (format nil "a~Cb" #\Return)))))

(test build-runtime-line-full
  "build-runtime-line produces correct format"
  (let* ((info (make-runtime-info :agent-id "gensym"
                                  :host "slopbian"
                                  :os "Linux 6.12"
                                  :arch "x64"
                                  :model "anthropic/claude-opus-4-6"
                                  :channel "telegram"
                                  :capabilities '("inlineButtons")))
         (line (build-runtime-line info "off")))
    (is (search "agent=gensym" line))
    (is (search "host=slopbian" line))
    (is (search "os=Linux 6.12 (x64)" line))
    (is (search "model=anthropic/claude-opus-4-6" line))
    (is (search "channel=telegram" line))
    (is (search "capabilities=inlineButtons" line))
    (is (search "thinking=off" line))))

(test build-runtime-line-minimal
  "build-runtime-line handles nil info"
  (let ((line (build-runtime-line nil "adaptive")))
    (is (search "Runtime:" line))
    (is (search "thinking=adaptive" line))))

(test build-system-prompt-none-mode
  "build-agent-system-prompt with none mode returns minimal"
  (let* ((params (make-system-prompt-params :workspace-dir "/tmp"
                                            :prompt-mode "none"))
         (prompt (build-agent-system-prompt params)))
    (is (string= "You are a personal assistant running inside OpenClaw." prompt))))

(test build-system-prompt-full-mode
  "build-agent-system-prompt with full mode includes all sections"
  (let* ((params (make-system-prompt-params
                  :workspace-dir "/tmp/test"
                  :tool-names '("read" "write" "exec")
                  :runtime-info (make-runtime-info :agent-id "test"
                                                   :channel "telegram")
                  :context-files (list (make-context-file :path "SOUL.md"
                                                         :content "Be good."))
                  :prompt-mode "full"
                  :reasoning-level "off"
                  :default-think-level "off"))
         (prompt (build-agent-system-prompt params)))
    ;; Check key sections exist
    (is (search "personal assistant" prompt))
    (is (search "## Tooling" prompt))
    (is (search "- read: Read file contents" prompt))
    (is (search "## Safety" prompt))
    (is (search "## Workspace" prompt))
    (is (search "/tmp/test" prompt))
    (is (search "# Project Context" prompt))
    (is (search "Be good." prompt))
    (is (search "## Runtime" prompt))
    (is (search "agent=test" prompt))))

(test build-system-prompt-with-reactions
  "build-agent-system-prompt includes reaction guidance"
  (let* ((params (make-system-prompt-params
                  :workspace-dir "/tmp"
                  :prompt-mode "full"
                  :reaction-guidance '("minimal" . "telegram")))
         (prompt (build-agent-system-prompt params)))
    (is (search "## Reactions" prompt))
    (is (search "MINIMAL mode" prompt))
    (is (search "telegram" prompt))))

(test build-system-prompt-with-timezone
  "build-agent-system-prompt includes timezone when set"
  (let* ((params (make-system-prompt-params
                  :workspace-dir "/tmp"
                  :prompt-mode "full"
                  :user-timezone "America/New_York"))
         (prompt (build-agent-system-prompt params)))
    (is (search "America/New_York" prompt))
    (is (search "session_status" prompt))))

(test build-system-prompt-extra-prompt
  "build-agent-system-prompt includes extra system prompt"
  (let* ((params (make-system-prompt-params
                  :workspace-dir "/tmp"
                  :prompt-mode "minimal"
                  :extra-system-prompt "You are a subagent."))
         (prompt (build-agent-system-prompt params)))
    (is (search "## Subagent Context" prompt))
    (is (search "You are a subagent." prompt))))

;;; =======================================================================
;;; 6. History assembly tests
;;; =======================================================================

(test truncate-single-message-no-change
  "truncate-single-message returns original when under limit"
  (let ((msg (make-test-message "user" "hello")))
    (is (eq msg (truncate-single-message msg 100)))))

(test truncate-single-message-truncates
  "truncate-single-message truncates oversized messages"
  (let* ((long-content (make-string 50000 :initial-element #\a))
         (msg (make-test-message "user" long-content))
         (truncated (truncate-single-message msg 100)))
    (is (not (eq msg truncated)))
    (is (search "[truncated]" (gethash "content" truncated)))
    (is (< (length (gethash "content" truncated))
            (length long-content)))))

(test truncate-messages-to-budget-under
  "truncate-messages-to-budget returns all when under budget"
  (let ((msgs (list (make-test-message "user" "hi")
                    (make-test-message "assistant" "hello"))))
    (let ((result (truncate-messages-to-budget msgs 10000)))
      (is (= 2 (length result))))))

(test truncate-messages-to-budget-over
  "truncate-messages-to-budget drops oldest messages when over budget"
  (let ((msgs (loop for i from 1 to 100
                    collect (make-test-message "user"
                                              (make-string 200 :initial-element #\a)))))
    ;; Each message is ~54 tokens. Budget for ~5 messages = 270
    (let ((result (truncate-messages-to-budget msgs 270)))
      (is (< (length result) 100))
      (is (> (length result) 0)))))

(test truncate-messages-empty
  "truncate-messages-to-budget handles empty list"
  (is (null (truncate-messages-to-budget '() 10000))))

(test truncate-messages-zero-budget
  "truncate-messages-to-budget with zero budget returns empty"
  (let ((msgs (list (make-test-message "user" "hi"))))
    (is (null (truncate-messages-to-budget msgs 0)))))

(test assemble-history-basic
  "assemble-history returns truncated messages"
  (let ((msgs (list (make-test-message "user" "hello")
                    (make-test-message "assistant" "world"))))
    (let ((result (assemble-history msgs 10000)))
      (is (= 2 (length result))))))

;;; =======================================================================
;;; 7. Compaction helper tests
;;; =======================================================================

(test compaction-threshold
  "compute-compaction-threshold is 85% of budget"
  (is (= 85000 (compute-compaction-threshold 100000)))
  (is (= 0 (compute-compaction-threshold 0))))

(test messages-need-compaction
  "messages-need-compaction-p detects when compaction needed"
  ;; Small messages, big budget — no compaction
  (let ((msgs (list (make-test-message "user" "hi"))))
    (is (not (messages-need-compaction-p msgs 100000))))
  ;; Many big messages, small budget — needs compaction
  (let ((msgs (loop for i from 1 to 100
                    collect (make-test-message "user"
                                              (make-string 1000 :initial-element #\a)))))
    (is (messages-need-compaction-p msgs 100))))

;;; =======================================================================
;;; 8. Registry tests
;;; =======================================================================

(test registry-register-and-resolve
  "register-context-engine and resolve work together"
  (ensure-context-engines-initialized)
  ;; Legacy engine should be available
  (is (not (null (get-context-engine-factory "legacy"))))
  (let ((engine (resolve-context-engine)))
    (is (typep engine 'legacy-context-engine))
    (is (string= "legacy" (context-engine-info-id (engine-info engine))))))

(test registry-list-ids
  "list-context-engine-ids returns registered IDs"
  (ensure-context-engines-initialized)
  (let ((ids (list-context-engine-ids)))
    (is (member "legacy" ids :test #'string=))))

(test registry-custom-engine
  "custom engines can be registered and resolved"
  (let ((factory-called nil))
    (register-context-engine "test-custom"
                             (lambda ()
                               (setf factory-called t)
                               (make-instance 'legacy-context-engine)))
    (is-true (get-context-engine-factory "test-custom"))
    (let ((engine (resolve-context-engine
                   (let ((cfg (make-hash-table :test 'equal))
                         (plugins (make-hash-table :test 'equal))
                         (slots (make-hash-table :test 'equal)))
                     (setf (gethash "contextEngine" slots) "test-custom")
                     (setf (gethash "slots" plugins) slots)
                     (setf (gethash "plugins" cfg) plugins)
                     cfg))))
      (is-true factory-called)
      (is (typep engine 'context-engine)))))

(test registry-unknown-engine-error
  "resolving unknown engine signals error"
  (signals error
    (resolve-context-engine
     (let ((cfg (make-hash-table :test 'equal))
           (plugins (make-hash-table :test 'equal))
           (slots (make-hash-table :test 'equal)))
       (setf (gethash "contextEngine" slots) "nonexistent-xyz")
       (setf (gethash "slots" plugins) slots)
       (setf (gethash "plugins" cfg) plugins)
       cfg))))

(test registry-overwrite
  "registering same ID overwrites previous factory"
  (let ((f1 (lambda () (make-instance 'legacy-context-engine)))
        (f2 (lambda () (make-instance 'legacy-context-engine))))
    (register-context-engine "overwrite-test" f1)
    (is (eq f1 (get-context-engine-factory "overwrite-test")))
    (register-context-engine "overwrite-test" f2)
    (is (eq f2 (get-context-engine-factory "overwrite-test")))))

(test initialization-idempotent
  "ensure-context-engines-initialized is idempotent"
  (ensure-context-engines-initialized)
  (ensure-context-engines-initialized)
  (is (member "legacy" (list-context-engine-ids) :test #'string=)))

;;; =======================================================================
;;; 9. Legacy engine parity tests
;;; =======================================================================

(test legacy-ingest-noop
  "legacy engine ingest returns ingested=false"
  (let* ((engine (make-instance 'legacy-context-engine))
         (result (engine-ingest engine "s1" (make-test-message "user" "hi"))))
    (is (not (ingest-result-ingested-p result)))))

(test legacy-assemble-passthrough
  "legacy engine assemble passes messages through"
  (let* ((engine (make-instance 'legacy-context-engine))
         (msgs (list (make-test-message "user" "first")
                     (make-test-message "assistant" "second")))
         (result (engine-assemble engine "s1" msgs)))
    (is (eq msgs (assemble-result-messages result)))
    (is (= 0 (assemble-result-estimated-tokens result)))
    (is (null (assemble-result-system-prompt-addition result)))))

(test legacy-compact-noop
  "legacy engine compact returns ok=true, compacted=false"
  (let* ((engine (make-instance 'legacy-context-engine))
         (result (engine-compact engine "s1" "/tmp/session.json")))
    (is (compact-result-ok-p result))
    (is (not (compact-result-compacted-p result)))))

(test legacy-dispose
  "legacy engine dispose completes without error"
  (let ((engine (make-instance 'legacy-context-engine)))
    (engine-dispose engine)
    (pass "dispose completed")))

;;; =======================================================================
;;; 10. Full context build tests
;;; =======================================================================

(test build-full-context-basic
  "build-full-context assembles a complete context"
  (let* ((msgs (list (make-test-message "user" "hello")
                     (make-test-message "assistant" "hi there")))
         (params (make-system-prompt-params
                  :workspace-dir "/tmp/test"
                  :prompt-mode "full"))
         (ctx (build-full-context :workspace-dir "/tmp/test"
                                  :model "claude-3-5-sonnet"
                                  :messages msgs
                                  :prompt-params params)))
    (is (plusp (length (cl-claw.context-engine::full-context-system-prompt ctx))))
    (is (= 2 (length (cl-claw.context-engine::full-context-messages ctx))))
    (is (plusp (cl-claw.context-engine::full-context-estimated-tokens ctx)))
    (is (not (null (cl-claw.context-engine::full-context-token-budget ctx))))))

(test build-full-context-with-engine
  "build-full-context uses engine when provided"
  (ensure-context-engines-initialized)
  (let* ((engine (resolve-context-engine))
         (msgs (list (make-test-message "user" "test")))
         (ctx (build-full-context :workspace-dir "/tmp"
                                  :messages msgs
                                  :engine engine
                                  :session-id "test-session")))
    (is (= 1 (length (cl-claw.context-engine::full-context-messages ctx))))))

(test build-full-context-empty-messages
  "build-full-context handles empty messages"
  (let ((ctx (build-full-context :workspace-dir "/tmp"
                                 :messages '())))
    (is (null (cl-claw.context-engine::full-context-messages ctx)))
    (is (plusp (length (cl-claw.context-engine::full-context-system-prompt ctx))))))

;;; =======================================================================
;;; 11. Result struct tests
;;; =======================================================================

(test ingest-result-struct
  "ingest-result struct works correctly"
  (let ((r (make-ingest-result :ingested-p t)))
    (is (ingest-result-ingested-p r)))
  (let ((r (make-ingest-result :ingested-p nil)))
    (is (not (ingest-result-ingested-p r)))))

(test assemble-result-struct
  "assemble-result struct works correctly"
  (let ((r (make-assemble-result :messages '("a" "b")
                                  :estimated-tokens 42
                                  :system-prompt-addition "extra")))
    (is (= 2 (length (assemble-result-messages r))))
    (is (= 42 (assemble-result-estimated-tokens r)))
    (is (string= "extra" (assemble-result-system-prompt-addition r)))))

(test compact-result-struct
  "compact-result struct works correctly"
  (let ((r (make-compact-result :ok-p t
                                 :compacted-p t
                                 :reason "test"
                                 :detail (make-compact-result-detail
                                          :summary "sum"
                                          :tokens-before 100
                                          :tokens-after 50))))
    (is (compact-result-ok-p r))
    (is (compact-result-compacted-p r))
    (is (string= "test" (compact-result-reason r)))
    (is (string= "sum" (compact-result-detail-summary (compact-result-detail r))))
    (is (= 100 (compact-result-detail-tokens-before (compact-result-detail r))))
    (is (= 50 (compact-result-detail-tokens-after (compact-result-detail r))))))

(test context-file-struct
  "context-file struct works correctly"
  (let ((cf (make-context-file :path "SOUL.md" :content "Be good.")))
    (is (string= "SOUL.md" (context-file-path cf)))
    (is (string= "Be good." (context-file-content cf)))))

(test context-engine-info-struct
  "context-engine-info struct works correctly"
  (let ((info (make-context-engine-info :id "test" :name "Test" :version "1.0")))
    (is (string= "test" (context-engine-info-id info)))
    (is (string= "Test" (context-engine-info-name info)))
    (is (string= "1.0" (context-engine-info-version info)))))
