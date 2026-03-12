;;;; provider-streaming-tool-test.lisp — E2E: Provider call → streaming → tool → response
;;;;
;;;; Tests the full lifecycle of:
;;;; 1. Provider makes LLM call
;;;; 2. Receives streaming response (SSE-style chunks)
;;;; 3. Dispatches tool call extracted from stream
;;;; 4. Returns final answer incorporating tool result

(in-package :cl-claw.e2e.tests)

(in-suite :e2e-provider-streaming-tool)

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Streaming infrastructure — simulate SSE-style chunk delivery
;;; ═══════════════════════════════════════════════════════════════════════════

(defstruct stream-chunk
  "A single chunk from a streaming LLM response."
  (type :text :type keyword)  ; :text, :tool-call-start, :tool-call-args, :tool-call-end, :done
  (content "" :type string)
  (tool-call-id nil :type (or string null))
  (tool-name nil :type (or string null))
  (index 0 :type fixnum))

(defstruct streaming-response
  "Accumulator for a streaming LLM response."
  (text-parts '() :type list)
  (tool-calls '() :type list)       ; accumulated tool-call structs
  (pending-tool nil :type (or list null))  ; partial tool-call being built
  (done-p nil :type boolean)
  (error nil :type (or string null)))

(declaim (ftype (function () streaming-response) make-fresh-streaming-response))
(defun make-fresh-streaming-response ()
  "Create a fresh streaming response accumulator."
  (make-streaming-response))

(declaim (ftype (function (streaming-response stream-chunk) streaming-response)
                process-stream-chunk))
(defun process-stream-chunk (response chunk)
  "Process a single stream chunk, accumulating into the response.
Returns the updated response."
  (declare (type streaming-response response)
           (type stream-chunk chunk))
  (ecase (stream-chunk-type chunk)
    (:text
     (push (stream-chunk-content chunk) (streaming-response-text-parts response)))
    (:tool-call-start
     ;; Begin accumulating a new tool call
     (setf (streaming-response-pending-tool response)
           (list :id (stream-chunk-tool-call-id chunk)
                 :name (stream-chunk-tool-name chunk)
                 :args-parts '())))
    (:tool-call-args
     ;; Append argument chunk to pending tool call
     (let ((pending (streaming-response-pending-tool response)))
       (when pending
         (push (stream-chunk-content chunk) (getf pending :args-parts))
         (setf (streaming-response-pending-tool response) pending))))
    (:tool-call-end
     ;; Finalize the pending tool call
     (let ((pending (streaming-response-pending-tool response)))
       (when pending
         (let* ((args-str (format nil "~{~a~}"
                                  (reverse (getf pending :args-parts))))
                (tool-call (cl-claw.tools.types:make-tool-call
                            :id (getf pending :id)
                            :name (getf pending :name)
                            :arguments (parse-json-args args-str))))
           (push tool-call (streaming-response-tool-calls response))
           (setf (streaming-response-pending-tool response) nil)))))
    (:done
     (setf (streaming-response-done-p response) t)))
  response)

(declaim (ftype (function (string) hash-table) parse-json-args))
(defun parse-json-args (json-str)
  "Parse a JSON argument string into a hash-table.
For testing, uses simple key-value parsing."
  (declare (type string json-str))
  (let ((ht (make-hash-table :test 'equal)))
    ;; Simple JSON parse via yason
    (handler-case
        (let ((parsed (yason:parse json-str)))
          (when (hash-table-p parsed)
            (setf ht parsed)))
      (error ()
        ;; Return empty hash-table on parse failure
        nil))
    ht))

(declaim (ftype (function (streaming-response) string) assemble-text))
(defun assemble-text (response)
  "Assemble accumulated text parts into final text."
  (declare (type streaming-response response))
  (format nil "~{~a~}" (reverse (streaming-response-text-parts response))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Mock streaming provider — simulates HTTP SSE response
;;; ═══════════════════════════════════════════════════════════════════════════

(defun make-text-only-chunks (text &optional (chunk-size 10))
  "Generate a sequence of text-only stream chunks from TEXT."
  (declare (type string text)
           (type fixnum chunk-size))
  (let ((chunks '())
        (len (length text)))
    (loop for i from 0 below len by chunk-size
          for end = (min (+ i chunk-size) len)
          for idx from 0
          do (push (make-stream-chunk
                    :type :text
                    :content (subseq text i end)
                    :index idx)
                   chunks))
    (push (make-stream-chunk :type :done :index (length chunks)) chunks)
    (nreverse chunks)))

(defun make-tool-call-chunks (text-before tool-id tool-name args-json text-after)
  "Generate chunks: text → tool-call → text → done."
  (declare (type string text-before tool-id tool-name args-json text-after))
  (let ((chunks '())
        (idx 0))
    ;; Text before tool call (in small chunks to simulate streaming)
    (when (plusp (length text-before))
      (loop for i from 0 below (length text-before) by 8
            for end = (min (+ i 8) (length text-before))
            do (push (make-stream-chunk
                      :type :text
                      :content (subseq text-before i end)
                      :index (incf idx))
                     chunks)))
    ;; Tool call start
    (push (make-stream-chunk
           :type :tool-call-start
           :tool-call-id tool-id
           :tool-name tool-name
           :index (incf idx))
          chunks)
    ;; Tool call arguments (split into 2 chunks to test accumulation)
    (let ((mid (floor (length args-json) 2)))
      (push (make-stream-chunk
             :type :tool-call-args
             :content (subseq args-json 0 mid)
             :index (incf idx))
            chunks)
      (push (make-stream-chunk
             :type :tool-call-args
             :content (subseq args-json mid)
             :index (incf idx))
            chunks))
    ;; Tool call end
    (push (make-stream-chunk
           :type :tool-call-end
           :index (incf idx))
          chunks)
    ;; Text after (final response text, if any)
    (when (plusp (length text-after))
      (loop for i from 0 below (length text-after) by 8
            for end = (min (+ i 8) (length text-after))
            do (push (make-stream-chunk
                      :type :text
                      :content (subseq text-after i end)
                      :index (incf idx))
                     chunks)))
    ;; Done
    (push (make-stream-chunk :type :done :index (incf idx)) chunks)
    (nreverse chunks)))

(defstruct mock-streaming-provider
  "Mock LLM provider that delivers pre-configured stream chunks."
  (name "mock-streaming" :type string)
  (chunks '() :type list)
  (call-count 0 :type fixnum)
  (received-prompts '() :type list)
  ;; Optional: second-round chunks (for after tool result is fed back)
  (second-round-chunks '() :type list))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Stream consumer — orchestrates chunk processing + tool dispatch
;;; ═══════════════════════════════════════════════════════════════════════════

(defstruct stream-orchestrator
  "Orchestrates streaming response processing with tool dispatch."
  (provider nil :type (or mock-streaming-provider null))
  (tool-dispatch-fn nil :type (or function null))
  (max-tool-rounds 5 :type fixnum)
  (tool-results '() :type list)
  (total-chunks-processed 0 :type fixnum))

(declaim (ftype (function (stream-orchestrator list) streaming-response)
                consume-stream))
(defun consume-stream (orchestrator chunks)
  "Consume a list of stream chunks, building a streaming-response."
  (declare (type stream-orchestrator orchestrator)
           (type list chunks))
  (let ((response (make-fresh-streaming-response)))
    (dolist (chunk chunks response)
      (declare (type stream-chunk chunk))
      (incf (stream-orchestrator-total-chunks-processed orchestrator))
      (setf response (process-stream-chunk response chunk)))))

(declaim (ftype (function (stream-orchestrator string) string)
                orchestrate-streaming-turn))
(defun orchestrate-streaming-turn (orchestrator prompt)
  "Run a full streaming turn: call provider, process chunks, dispatch tools, loop.
Returns the final assembled text response."
  (declare (type stream-orchestrator orchestrator)
           (type string prompt))
  (let* ((provider (stream-orchestrator-provider orchestrator))
         (dispatch-fn (stream-orchestrator-tool-dispatch-fn orchestrator))
         (round 0)
         (final-text ""))
    (declare (type fixnum round)
             (type string final-text))

    ;; Record the prompt
    (push prompt (mock-streaming-provider-received-prompts provider))
    (incf (mock-streaming-provider-call-count provider))

    ;; First round: consume initial chunks
    (let* ((chunks (mock-streaming-provider-chunks provider))
           (response (consume-stream orchestrator chunks)))

      ;; Process tool calls if any
      (loop while (and (streaming-response-tool-calls response)
                       (< round (stream-orchestrator-max-tool-rounds orchestrator)))
            do
               (incf round)
               ;; Dispatch each tool call
               (let ((tool-results '()))
                 (dolist (tc (reverse (streaming-response-tool-calls response)))
                   (declare (type cl-claw.tools.types:tool-call tc))
                   (let ((result (if dispatch-fn
                                     (funcall dispatch-fn tc)
                                     (cl-claw.tools.dispatch:dispatch-tool-call tc))))
                     (push result tool-results)
                     (push result (stream-orchestrator-tool-results orchestrator))))

                 ;; Feed tool results back to provider (use second-round chunks)
                 (let ((second-chunks (mock-streaming-provider-second-round-chunks provider)))
                   (when second-chunks
                     (incf (mock-streaming-provider-call-count provider))
                     (push (format nil "[tool-results: ~{~a~^, ~}]"
                                   (mapcar #'cl-claw.tools.types:tool-result-content
                                           (reverse tool-results)))
                           (mock-streaming-provider-received-prompts provider))
                     (setf response (consume-stream orchestrator second-chunks))))))

      ;; Assemble final text
      (setf final-text (assemble-text response)))

    final-text))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 1: Text-only streaming — no tool calls
;;; ═══════════════════════════════════════════════════════════════════════════

(test streaming-text-only
  "Streaming response with text only — no tool calls."
  (let* ((full-text "The answer to life, the universe, and everything is 42.")
         (chunks (make-text-only-chunks full-text 12))
         (provider (make-mock-streaming-provider
                    :name "text-provider"
                    :chunks chunks))
         (orchestrator (make-stream-orchestrator :provider provider)))

    (let ((result (orchestrate-streaming-turn orchestrator "What is the answer?")))
      ;; Text should be fully assembled
      (is (string= full-text result)
          "Full text assembled from stream chunks")
      ;; Provider called exactly once
      (is (= 1 (mock-streaming-provider-call-count provider))
          "Provider called exactly once")
      ;; No tool results
      (is (null (stream-orchestrator-tool-results orchestrator))
          "No tool calls dispatched")
      ;; All chunks processed (text chunks + done)
      (is (> (stream-orchestrator-total-chunks-processed orchestrator) 0)
          "Chunks were processed"))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 2: Streaming with tool call → tool dispatch → final response
;;; ═══════════════════════════════════════════════════════════════════════════

(test streaming-with-tool-call
  "Full flow: stream text, encounter tool call, dispatch it, get final answer."
  ;; Set up tool registry with a test tool
  (let ((saved-registry (cl-claw.tools.dispatch:list-tools)))
    (unwind-protect
         (progn
           (cl-claw.tools.dispatch:clear-tool-registry)

           ;; Register a "weather" tool
           (cl-claw.tools.dispatch:register-tool
            (cl-claw.tools.types:make-tool-definition
             :name "get_weather"
             :description "Get current weather for a location"
             :handler (lambda (args)
                        (declare (type hash-table args))
                        (let ((location (gethash "location" args "unknown")))
                          (format nil "Weather in ~a: 72°F, sunny" location)))
             :category "test"))

           ;; Create chunks: initial text → tool call → done
           ;; Provider's first response includes a tool call
           (let* ((args-json "{\"location\": \"San Francisco\"}")
                  (first-chunks (make-tool-call-chunks
                                 "Let me check " ; text before tool
                                 "call_001"
                                 "get_weather"
                                 args-json
                                 ""))     ; no text after (tool call ends stream)
                  ;; Second round: provider responds with final text after tool result
                  (second-chunks (make-text-only-chunks
                                  "The weather in San Francisco is 72°F and sunny!" 10))
                  (provider (make-mock-streaming-provider
                             :name "tool-provider"
                             :chunks first-chunks
                             :second-round-chunks second-chunks))
                  (orchestrator (make-stream-orchestrator :provider provider)))

             (let ((result (orchestrate-streaming-turn orchestrator "What's the weather in SF?")))
               ;; Final text should be the second-round response
               (is (string= "The weather in San Francisco is 72°F and sunny!" result)
                   "Final response assembled after tool dispatch")
               ;; Provider called twice (initial + after tool result)
               (is (= 2 (mock-streaming-provider-call-count provider))
                   "Provider called twice: initial + post-tool")
               ;; One tool result
               (is (= 1 (length (stream-orchestrator-tool-results orchestrator)))
                   "Exactly one tool dispatched")
               ;; Tool result content is correct
               (let ((tr (first (stream-orchestrator-tool-results orchestrator))))
                 (is (string= "Weather in San Francisco: 72°F, sunny"
                              (cl-claw.tools.types:tool-result-content tr))
                     "Tool result has correct content")
                 (is (not (cl-claw.tools.types:tool-result-error-p tr))
                     "Tool result is not an error")))))

      ;; Restore registry
      (cl-claw.tools.dispatch:clear-tool-registry)
      (dolist (tool saved-registry)
        (cl-claw.tools.dispatch:register-tool tool)))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 3: Tool call with error → error propagated in result
;;; ═══════════════════════════════════════════════════════════════════════════

(test streaming-tool-call-error
  "Tool handler raises an error — error captured in tool result."
  (let ((saved-registry (cl-claw.tools.dispatch:list-tools)))
    (unwind-protect
         (progn
           (cl-claw.tools.dispatch:clear-tool-registry)

           ;; Register a tool that always errors
           (cl-claw.tools.dispatch:register-tool
            (cl-claw.tools.types:make-tool-definition
             :name "failing_tool"
             :description "A tool that always fails"
             :handler (lambda (args)
                        (declare (ignore args))
                        (error "Database connection refused"))
             :category "test"))

           (let* ((first-chunks (make-tool-call-chunks
                                 "" "call_err_001" "failing_tool"
                                 "{}" ""))
                  (second-chunks (make-text-only-chunks
                                  "Sorry, I encountered an error with the tool." 10))
                  (provider (make-mock-streaming-provider
                             :chunks first-chunks
                             :second-round-chunks second-chunks))
                  (orchestrator (make-stream-orchestrator :provider provider)))

             (let ((result (orchestrate-streaming-turn orchestrator "Do something")))
               ;; Final text is the error-recovery response
               (is (search "error" result :test #'char-equal)
                   "Final response mentions the error")
               ;; Tool result should be an error
               (let ((tr (first (stream-orchestrator-tool-results orchestrator))))
                 (is (cl-claw.tools.types:tool-result-error-p tr)
                     "Tool result is flagged as error")
                 (is (search "Database connection refused"
                             (cl-claw.tools.types:tool-result-content tr))
                     "Error message propagated in tool result")))))

      (cl-claw.tools.dispatch:clear-tool-registry)
      (dolist (tool saved-registry)
        (cl-claw.tools.dispatch:register-tool tool)))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 4: Multiple tool calls in a single stream
;;; ═══════════════════════════════════════════════════════════════════════════

(test streaming-multiple-tool-calls
  "Stream contains multiple tool calls — all dispatched, results fed back."
  (let ((saved-registry (cl-claw.tools.dispatch:list-tools)))
    (unwind-protect
         (progn
           (cl-claw.tools.dispatch:clear-tool-registry)

           ;; Register two tools
           (cl-claw.tools.dispatch:register-tool
            (cl-claw.tools.types:make-tool-definition
             :name "get_time"
             :description "Get current time"
             :handler (lambda (args)
                        (declare (ignore args))
                        "2026-03-12T12:00:00Z")
             :category "test"))

           (cl-claw.tools.dispatch:register-tool
            (cl-claw.tools.types:make-tool-definition
             :name "get_weather"
             :description "Get weather"
             :handler (lambda (args)
                        (declare (type hash-table args))
                        (format nil "~a: Clear skies" (gethash "city" args "unknown")))
             :category "test"))

           ;; Build chunks with two tool calls
           (let* ((chunks '())
                  (idx 0))
             ;; Text chunk
             (push (make-stream-chunk :type :text :content "Checking " :index (incf idx)) chunks)
             ;; First tool call: get_time
             (push (make-stream-chunk :type :tool-call-start
                                      :tool-call-id "tc_01" :tool-name "get_time"
                                      :index (incf idx)) chunks)
             (push (make-stream-chunk :type :tool-call-args :content "{}" :index (incf idx)) chunks)
             (push (make-stream-chunk :type :tool-call-end :index (incf idx)) chunks)
             ;; Second tool call: get_weather
             (push (make-stream-chunk :type :tool-call-start
                                      :tool-call-id "tc_02" :tool-name "get_weather"
                                      :index (incf idx)) chunks)
             (push (make-stream-chunk :type :tool-call-args
                                      :content "{\"city\": \"NYC\"}" :index (incf idx)) chunks)
             (push (make-stream-chunk :type :tool-call-end :index (incf idx)) chunks)
             ;; Done
             (push (make-stream-chunk :type :done :index (incf idx)) chunks)

             (let* ((first-chunks (nreverse chunks))
                    (second-chunks (make-text-only-chunks
                                    "It's noon in NYC with clear skies!" 10))
                    (provider (make-mock-streaming-provider
                               :chunks first-chunks
                               :second-round-chunks second-chunks))
                    (orchestrator (make-stream-orchestrator :provider provider)))

               (let ((result (orchestrate-streaming-turn orchestrator "Time and weather?")))
                 ;; Both tools dispatched
                 (is (= 2 (length (stream-orchestrator-tool-results orchestrator)))
                     "Two tool calls dispatched")
                 ;; Final text assembled
                 (is (search "noon" result :test #'char-equal)
                     "Final response includes time info")
                 ;; Provider called twice
                 (is (= 2 (mock-streaming-provider-call-count provider))
                     "Provider called for initial + post-tool round")))))

      (cl-claw.tools.dispatch:clear-tool-registry)
      (dolist (tool saved-registry)
        (cl-claw.tools.dispatch:register-tool tool)))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 5: Chunk accumulation correctness
;;; ═══════════════════════════════════════════════════════════════════════════

(test streaming-chunk-accumulation
  "Verify chunk-by-chunk accumulation produces correct results."
  (let* ((response (make-fresh-streaming-response))
         (chunks (list
                  (make-stream-chunk :type :text :content "Hello" :index 0)
                  (make-stream-chunk :type :text :content ", " :index 1)
                  (make-stream-chunk :type :text :content "world" :index 2)
                  (make-stream-chunk :type :text :content "!" :index 3)
                  (make-stream-chunk :type :done :index 4))))

    ;; Process each chunk
    (dolist (chunk chunks)
      (setf response (process-stream-chunk response chunk)))

    ;; Verify text assembly
    (is (string= "Hello, world!" (assemble-text response))
        "Text chunks assemble correctly")
    (is (streaming-response-done-p response)
        "Done flag set after :done chunk")
    (is (null (streaming-response-tool-calls response))
        "No tool calls in text-only stream")
    (is (= 4 (length (streaming-response-text-parts response)))
        "Four text parts accumulated")))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 6: Tool argument streaming (partial JSON reassembly)
;;; ═══════════════════════════════════════════════════════════════════════════

(test streaming-tool-args-reassembly
  "Tool call arguments arrive in multiple chunks and are correctly reassembled."
  (let* ((response (make-fresh-streaming-response))
         (full-args "{\"query\": \"Common Lisp macros\", \"limit\": 10}")
         (mid (floor (length full-args) 2))
         (chunks (list
                  (make-stream-chunk :type :tool-call-start
                                     :tool-call-id "tc_args_01"
                                     :tool-name "search"
                                     :index 0)
                  (make-stream-chunk :type :tool-call-args
                                     :content (subseq full-args 0 mid)
                                     :index 1)
                  (make-stream-chunk :type :tool-call-args
                                     :content (subseq full-args mid)
                                     :index 2)
                  (make-stream-chunk :type :tool-call-end :index 3)
                  (make-stream-chunk :type :done :index 4))))

    (dolist (chunk chunks)
      (setf response (process-stream-chunk response chunk)))

    ;; One tool call accumulated
    (is (= 1 (length (streaming-response-tool-calls response)))
        "One tool call extracted from stream")

    ;; Tool call has correct metadata
    (let ((tc (first (streaming-response-tool-calls response))))
      (is (string= "tc_args_01" (cl-claw.tools.types:tool-call-id tc))
          "Tool call ID preserved")
      (is (string= "search" (cl-claw.tools.types:tool-call-name tc))
          "Tool name preserved")
      ;; Arguments parsed correctly
      (let ((args (cl-claw.tools.types:tool-call-arguments tc)))
        (is (string= "Common Lisp macros" (gethash "query" args))
            "Query argument parsed from reassembled JSON")
        (is (= 10 (gethash "limit" args))
            "Limit argument parsed from reassembled JSON")))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 7: Provider fallback with streaming
;;; ═══════════════════════════════════════════════════════════════════════════

(test streaming-provider-integration
  "Streaming orchestrator integrates with provider registry for provider selection."
  (let* ((registry (cl-claw.providers:create-provider-registry))
         (call-log '()))

    ;; Register a provider that records calls
    (cl-claw.providers:register-provider
     registry
     (cl-claw.providers:make-provider-adapter
      :name "streaming-test"
      :priority 10
      :invoke-fn (lambda (request)
                   (declare (type cl-claw.providers:provider-request request))
                   (push (cl-claw.providers:provider-request-prompt request) call-log)
                   (cl-claw.providers::make-provider-response
                    :ok-p t
                    :provider "streaming-test"
                    :model "test-model"
                    :text (format nil "Response to: ~a"
                                  (cl-claw.providers:provider-request-prompt request))))))

    ;; Use provider to make initial call, then feed to streaming orchestrator
    (let* ((request (cl-claw.providers:make-provider-request
                     :prompt "What's 2+2?"
                     :model "test-model"))
           (provider-resp (cl-claw.providers:invoke-with-fallback registry request)))

      ;; Provider responded
      (is (cl-claw.providers:provider-response-ok-p provider-resp)
          "Provider call succeeded")
      (is (= 1 (length call-log))
          "Provider was called exactly once")

      ;; Now simulate streaming the provider's response through our orchestrator
      (let* ((text (cl-claw.providers:provider-response-text provider-resp))
             (chunks (make-text-only-chunks text 8))
             (mock-provider (make-mock-streaming-provider :chunks chunks))
             (orchestrator (make-stream-orchestrator :provider mock-provider)))

        (let ((result (orchestrate-streaming-turn orchestrator "What's 2+2?")))
          (is (string= text result)
              "Streaming orchestrator assembles provider response correctly"))))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 8: Max tool rounds safety limit
;;; ═══════════════════════════════════════════════════════════════════════════

(test streaming-max-tool-rounds
  "Orchestrator respects max-tool-rounds to prevent infinite tool loops."
  (let ((saved-registry (cl-claw.tools.dispatch:list-tools)))
    (unwind-protect
         (progn
           (cl-claw.tools.dispatch:clear-tool-registry)

           (cl-claw.tools.dispatch:register-tool
            (cl-claw.tools.types:make-tool-definition
             :name "echo_tool"
             :description "Echoes input"
             :handler (lambda (args)
                        (declare (type hash-table args))
                        (gethash "text" args "echo"))
             :category "test"))

           ;; Both rounds produce tool calls — should stop after max rounds
           (let* ((tool-chunks (make-tool-call-chunks
                                "" "tc_loop_01" "echo_tool"
                                "{\"text\": \"loop\"}" ""))
                  (provider (make-mock-streaming-provider
                             :chunks tool-chunks
                             :second-round-chunks tool-chunks))
                  (orchestrator (make-stream-orchestrator
                                 :provider provider
                                 :max-tool-rounds 1)))

             ;; With max-tool-rounds=1, only one round of tool dispatch
             (orchestrate-streaming-turn orchestrator "test")

             ;; Should have dispatched exactly 1 round of tools
             (is (<= (length (stream-orchestrator-tool-results orchestrator)) 2)
                 "Tool dispatch bounded by max-tool-rounds")))

      (cl-claw.tools.dispatch:clear-tool-registry)
      (dolist (tool saved-registry)
        (cl-claw.tools.dispatch:register-tool tool)))))
