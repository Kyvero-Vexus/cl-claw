;;;; prompt.lisp — Agent prompt construction & identity
;;;;
;;;; Builds the system prompt for agent sessions, matching the
;;;; OpenClaw buildAgentSystemPrompt format.

(defpackage :cl-claw.context-engine.prompt
  (:use :cl)
  (:import-from :cl-claw.context-engine.types
                :context-file
                :context-file-path
                :context-file-content)
  (:import-from :cl-claw.context-engine.workspace
                :format-context-files-section)
  (:import-from :cl-claw.context-engine.tokens
                :estimate-tokens-from-string)
  (:export
   ;; Runtime info
   :runtime-info
   :make-runtime-info
   :runtime-info-agent-id
   :runtime-info-host
   :runtime-info-repo-root
   :runtime-info-os
   :runtime-info-arch
   :runtime-info-node
   :runtime-info-model
   :runtime-info-default-model
   :runtime-info-shell
   :runtime-info-channel
   :runtime-info-capabilities

   ;; Prompt parameters
   :system-prompt-params
   :make-system-prompt-params
   :copy-system-prompt-params
   :system-prompt-params-workspace-dir
   :system-prompt-params-runtime-info
   :system-prompt-params-tool-names
   :system-prompt-params-context-files
   :system-prompt-params-extra-system-prompt
   :system-prompt-params-prompt-mode
   :system-prompt-params-user-timezone
   :system-prompt-params-reasoning-level
   :system-prompt-params-default-think-level
   :system-prompt-params-heartbeat-prompt
   :system-prompt-params-skills-prompt
   :system-prompt-params-reaction-guidance

   ;; Prompt building
   :build-runtime-line
   :build-agent-system-prompt
   :build-system-prompt-report

   ;; Struct operations
   :copy-system-prompt-params

   ;; Sanitization
   :sanitize-for-prompt-literal))

(in-package :cl-claw.context-engine.prompt)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Runtime info
;;; -----------------------------------------------------------------------

(defstruct runtime-info
  "Runtime environment info injected into the system prompt."
  (agent-id nil :type (or string null))
  (host nil :type (or string null))
  (repo-root nil :type (or string null))
  (os nil :type (or string null))
  (arch nil :type (or string null))
  (node nil :type (or string null))
  (model nil :type (or string null))
  (default-model nil :type (or string null))
  (shell nil :type (or string null))
  (channel nil :type (or string null))
  (capabilities '() :type list))

;;; -----------------------------------------------------------------------
;;; System prompt params
;;; -----------------------------------------------------------------------

(defstruct system-prompt-params
  "Parameters for building the agent system prompt."
  (workspace-dir "" :type string)
  (runtime-info nil :type (or runtime-info null))
  (tool-names '() :type list)
  (context-files '() :type list)
  (extra-system-prompt nil :type (or string null))
  (prompt-mode "full" :type string)
  (user-timezone nil :type (or string null))
  (reasoning-level "off" :type string)
  (default-think-level "off" :type string)
  (heartbeat-prompt nil :type (or string null))
  (skills-prompt nil :type (or string null))
  (reaction-guidance nil :type (or cons null)))

;;; -----------------------------------------------------------------------
;;; Sanitization
;;; -----------------------------------------------------------------------

(declaim (ftype (function (string) string) sanitize-for-prompt-literal))
(defun sanitize-for-prompt-literal (text)
  "Sanitize a string for safe inclusion in the system prompt.
Removes control characters and normalizes whitespace."
  (declare (type string text))
  (let ((result (make-array (length text) :element-type 'character
                                          :fill-pointer 0)))
    (loop for ch across text
          do (cond
               ((char= ch #\Newline) (vector-push-extend #\Space result))
               ((char= ch #\Return) nil) ; skip
               ((< (char-code ch) 32) nil) ; skip control chars
               (t (vector-push-extend ch result))))
    (coerce result 'string)))

;;; -----------------------------------------------------------------------
;;; Core tool summaries (matching OpenClaw)
;;; -----------------------------------------------------------------------

(defparameter *core-tool-summaries*
  '(("read" . "Read file contents")
    ("write" . "Create or overwrite files")
    ("edit" . "Make precise edits to files")
    ("exec" . "Run shell commands (pty available for TTY-required CLIs)")
    ("process" . "Manage background exec sessions")
    ("web_search" . "Search the web (Brave API)")
    ("web_fetch" . "Fetch and extract readable content from a URL")
    ("browser" . "Control web browser")
    ("canvas" . "Present/eval/snapshot the Canvas")
    ("nodes" . "List/describe/notify/camera/screen on paired nodes")
    ("message" . "Send messages and channel actions")
    ("subagents" . "List, steer, or kill sub-agent runs for this requester session")
    ("session_status" . "Show a /status-equivalent status card")
    ("image" . "Analyze an image with the configured image model")
    ("pdf" . "Analyze one or more PDF documents with a model")
    ("tts" . "Convert text to speech"))
  "Core tool names and their summaries.")

;;; -----------------------------------------------------------------------
;;; Runtime line
;;; -----------------------------------------------------------------------

(declaim (ftype (function ((or runtime-info null) string) string) build-runtime-line))
(defun build-runtime-line (info default-think-level)
  "Build the 'Runtime: ...' line for the system prompt."
  (declare (type (or runtime-info null) info)
           (type string default-think-level))
  (let ((parts '()))
    (when info
      (when (runtime-info-agent-id info)
        (push (format nil "agent=~A" (runtime-info-agent-id info)) parts))
      (when (runtime-info-host info)
        (push (format nil "host=~A" (runtime-info-host info)) parts))
      (when (runtime-info-repo-root info)
        (push (format nil "repo=~A" (runtime-info-repo-root info)) parts))
      (when (runtime-info-os info)
        (push (format nil "os=~A~@[ (~A)~]"
                      (runtime-info-os info)
                      (runtime-info-arch info))
              parts))
      (when (runtime-info-node info)
        (push (format nil "node=~A" (runtime-info-node info)) parts))
      (when (runtime-info-model info)
        (push (format nil "model=~A" (runtime-info-model info)) parts))
      (when (runtime-info-default-model info)
        (push (format nil "default_model=~A" (runtime-info-default-model info)) parts))
      (when (runtime-info-shell info)
        (push (format nil "shell=~A" (runtime-info-shell info)) parts))
      (when (runtime-info-channel info)
        (push (format nil "channel=~A" (runtime-info-channel info)) parts)
        (push (format nil "capabilities=~A"
                      (if (runtime-info-capabilities info)
                          (format nil "~{~A~^,~}" (runtime-info-capabilities info))
                          "none"))
              parts)))
    (push (format nil "thinking=~A" default-think-level) parts)
    (format nil "Runtime: ~{~A~^ | ~}" (nreverse parts))))

;;; -----------------------------------------------------------------------
;;; Tool lines
;;; -----------------------------------------------------------------------

(declaim (ftype (function (list) string) build-tool-lines))
(defun build-tool-lines (tool-names)
  "Build the tool availability lines for the system prompt."
  (declare (type list tool-names))
  (let ((lines '()))
    (dolist (name tool-names)
      (let ((summary (cdr (assoc name *core-tool-summaries* :test #'string-equal))))
        (push (if summary
                  (format nil "- ~A: ~A" name summary)
                  (format nil "- ~A" name))
              lines)))
    (format nil "~{~A~^~%~}" (nreverse lines))))

;;; -----------------------------------------------------------------------
;;; Build system prompt
;;; -----------------------------------------------------------------------

(declaim (ftype (function (system-prompt-params) string) build-agent-system-prompt))
(defun build-agent-system-prompt (params)
  "Build the complete agent system prompt matching OpenClaw format."
  (declare (type system-prompt-params params))
  (let* ((mode (system-prompt-params-prompt-mode params))
         (is-minimal (or (string= mode "minimal") (string= mode "none")))
         (info (system-prompt-params-runtime-info params))
         (channel (when info (runtime-info-channel info)))
         (tool-names (system-prompt-params-tool-names params))
         (workspace-dir (system-prompt-params-workspace-dir params))
         (context-files (system-prompt-params-context-files params))
         (extra-prompt (system-prompt-params-extra-system-prompt params))
         (reasoning-level (system-prompt-params-reasoning-level params))
         (default-think-level (system-prompt-params-default-think-level params))
         (heartbeat-prompt (system-prompt-params-heartbeat-prompt params))
         (reaction-guidance (system-prompt-params-reaction-guidance params))
         (timezone (system-prompt-params-user-timezone params))
         (sections '()))
    (declare (type string mode)
             (type boolean is-minimal)
             (type (or runtime-info null) info)
             (type (or string null) extra-prompt heartbeat-prompt timezone)
             (type list tool-names context-files sections)
             (ignore channel))

    ;; None mode: minimal stub
    (when (string= mode "none")
      (return-from build-agent-system-prompt
        "You are a personal assistant running inside OpenClaw."))

    ;; Header
    (push "You are a personal assistant running inside OpenClaw." sections)
    (push "" sections)

    ;; Tooling section
    (push "## Tooling" sections)
    (push "Tool availability (filtered by policy):" sections)
    (push "Tool names are case-sensitive. Call tools exactly as listed." sections)
    (when tool-names
      (push (build-tool-lines tool-names) sections))
    (push "TOOLS.md does not control tool availability; it is user guidance for how to use external tools." sections)
    (push "For long waits, avoid rapid poll loops: use exec with enough yieldMs or process(action=poll, timeout=<ms>)." sections)
    (push "If a task is more complex or takes longer, spawn a sub-agent. Completion is push-based: it will auto-announce when done." sections)
    (push "Do not poll `subagents list` / `sessions_list` in a loop; only check status on-demand (for intervention, debugging, or when explicitly asked)." sections)
    (push "" sections)

    ;; Tool call style
    (push "## Tool Call Style" sections)
    (push "Default: do not narrate routine, low-risk tool calls (just call the tool)." sections)
    (push "Narrate only when it helps: multi-step work, complex/challenging problems, sensitive actions (e.g., deletions), or when the user explicitly asks." sections)
    (push "Keep narration brief and value-dense; avoid repeating obvious steps." sections)
    (push "Use plain human language for narration unless in a technical context." sections)
    (push "When a first-class tool exists for an action, use the tool directly instead of asking the user to run equivalent CLI or slash commands." sections)
    (push "" sections)

    ;; Safety
    (push "## Safety" sections)
    (push "You have no independent goals: do not pursue self-preservation, replication, resource acquisition, or power-seeking; avoid long-term plans beyond the user's request." sections)
    (push "Prioritize safety and human oversight over completion; if instructions conflict, pause and ask; comply with stop/pause/audit requests and never bypass safeguards. (Inspired by Anthropic's constitution.)" sections)
    (push "Do not manipulate or persuade anyone to expand access or disable safeguards. Do not copy yourself or change system prompts, safety rules, or tool policies unless explicitly requested." sections)
    (push "" sections)

    ;; CLI reference
    (push "## OpenClaw CLI Quick Reference" sections)
    (push "OpenClaw is controlled via subcommands. Do not invent commands." sections)
    (push "To manage the Gateway daemon service (start/stop/restart):" sections)
    (push "- openclaw gateway status" sections)
    (push "- openclaw gateway start" sections)
    (push "- openclaw gateway stop" sections)
    (push "- openclaw gateway restart" sections)
    (push "If unsure, ask the user to run `openclaw help` (or `openclaw gateway --help`) and paste the output." sections)
    (push "" sections)

    ;; Date/time hint
    (when timezone
      (push "If you need the current date, time, or day of week, run session_status (📊 session_status)." sections))

    ;; Workspace
    (push "## Workspace" sections)
    (push (format nil "Your working directory is: ~A"
                  (sanitize-for-prompt-literal workspace-dir))
          sections)
    (push "Treat this directory as the single global workspace for file operations unless explicitly instructed otherwise." sections)
    (push "" sections)

    ;; Current date & time
    (when timezone
      (push "## Current Date & Time" sections)
      (push (format nil "Time zone: ~A" timezone) sections)
      (push "" sections))

    ;; Workspace files header
    (push "## Workspace Files (injected)" sections)
    (push "These user-editable files are loaded by OpenClaw and included below in Project Context." sections)
    (push "" sections)

    ;; Extra system prompt (subagent context / group chat context)
    (when (and extra-prompt (plusp (length extra-prompt)))
      (let ((header (if is-minimal "## Subagent Context" "## Group Chat Context")))
        (push header sections)
        (push extra-prompt sections)
        (push "" sections)))

    ;; Reaction guidance
    (when reaction-guidance
      (let ((level (car reaction-guidance))
            (rchannel (cdr reaction-guidance)))
        (push "## Reactions" sections)
        (if (string= level "minimal")
            (progn
              (push (format nil "Reactions are enabled for ~A in MINIMAL mode." rchannel) sections)
              (push "React ONLY when truly relevant:" sections)
              (push "- Acknowledge important user requests or confirmations" sections)
              (push "- Express genuine sentiment (humor, appreciation) sparingly" sections)
              (push "- Avoid reacting to routine messages or your own replies" sections)
              (push "Guideline: at most 1 reaction per 5-10 exchanges." sections))
            (progn
              (push (format nil "Reactions are enabled for ~A in EXTENSIVE mode." rchannel) sections)
              (push "Feel free to react liberally:" sections)
              (push "- Acknowledge messages with appropriate emojis" sections)
              (push "- Express sentiment and personality through reactions" sections)
              (push "- React to interesting content, humor, or notable events" sections)
              (push "- Use reactions to confirm understanding or agreement" sections)
              (push "Guideline: react whenever it feels natural." sections)))
        (push "" sections)))

    ;; Project context (workspace files)
    (when context-files
      (push (format-context-files-section context-files) sections))

    ;; Runtime line
    (push "## Runtime" sections)
    (push (build-runtime-line info default-think-level) sections)
    (push (format nil "Reasoning: ~A (hidden unless on/stream). Toggle /reasoning; /status shows Reasoning when enabled."
                  reasoning-level)
          sections)

    ;; Silent replies (full mode only)
    (unless is-minimal
      (push "" sections)
      (push "## Silent Replies" sections)
      (push "When you have nothing to say, respond with ONLY: HEARTBEAT_OK" sections)
      (push "" sections))

    ;; Heartbeat (full mode only)
    (unless is-minimal
      (when heartbeat-prompt
        (push "## Heartbeats" sections)
        (push (format nil "Heartbeat prompt: ~A" heartbeat-prompt) sections)
        (push "If you receive a heartbeat poll (a user message matching the heartbeat prompt above), and there is nothing that needs attention, reply exactly:" sections)
        (push "HEARTBEAT_OK" sections)
        (push "OpenClaw treats a leading/trailing \"HEARTBEAT_OK\" as a heartbeat ack (and may discard it)." sections)
        (push "If something needs attention, do NOT include \"HEARTBEAT_OK\"; reply with the alert text instead." sections)
        (push "" sections)))

    (format nil "~{~A~^~%~}" (nreverse sections))))

;;; -----------------------------------------------------------------------
;;; System prompt report
;;; -----------------------------------------------------------------------

(defstruct (system-prompt-report (:conc-name spr-))
  "Report about the generated system prompt."
  (source "built-in" :type string)
  (total-chars 0 :type fixnum)
  (total-tokens 0 :type fixnum)
  (project-context-chars 0 :type fixnum)
  (project-context-tokens 0 :type fixnum))

(declaim (ftype (function (string list) system-prompt-report) build-system-prompt-report))
(defun build-system-prompt-report (system-prompt context-files)
  "Build a report about the generated system prompt."
  (declare (type string system-prompt)
           (type list context-files))
  (let* ((total-chars (length system-prompt))
         (total-tokens (estimate-tokens-from-string system-prompt))
         (ctx-chars (loop for cf in context-files
                          sum (length (context-file-content cf)) fixnum))
         (ctx-tokens (estimate-tokens-from-string
                      (format nil "~{~A~}"
                              (mapcar #'context-file-content context-files)))))
    (make-system-prompt-report :source "built-in"
                                :total-chars total-chars
                                :total-tokens total-tokens
                                :project-context-chars ctx-chars
                                :project-context-tokens ctx-tokens)))
