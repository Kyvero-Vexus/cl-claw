;;;; acp-subagent-test.lisp — E2E: ACP spawn → sub-agent → result relay
;;;;
;;;; Tests the full lifecycle of spawning a sub-agent from a parent ACP session,
;;;; executing a turn in the sub-agent session, and relaying results back to
;;;; the parent via stream relay.

(in-package :cl-claw.e2e.tests)

(def-suite :e2e-acp-subagent :in :cl-claw.e2e.tests
  :description "ACP sub-agent spawn, execute, and result relay E2E tests")

(in-suite :e2e-acp-subagent)

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 1: Full spawn → execute → relay lifecycle
;;; ═══════════════════════════════════════════════════════════════════════════

(test acp-subagent-full-lifecycle
  "Complete flow: parent spawns sub-agent, sub-agent runs, result relayed back."
  (let* (;; Step 1: Create the ACP session manager with enabled config
         (dispatch (make-test-config "enabled" t))
         (acp-cfg (make-test-config "enabled" t "dispatch" dispatch))
         (config (make-test-config "acp" acp-cfg))
         (manager (cl-claw.acp:make-acp-session-manager config)))

    ;; Step 2: Initialize the parent session
    (let ((parent-entry (cl-claw.acp:manager-initialize-session
                         manager
                         :session-id "parent-main"
                         :session-key "agent:ceo:main"
                         :cwd "/home/user/workspace")))
      (is (not (null parent-entry))
          "Parent session created successfully")
      (is (string= "parent-main"
                    (cl-claw.acp.types:acp-session-entry-session-id parent-entry))
          "Parent session ID matches"))

    ;; Step 3: Resolve spawn session key for sub-agent
    (let ((child-key (cl-claw.agents.spawn:resolve-spawn-session-key
                      "implementer"
                      :parent-key "agent:ceo:main"
                      :label "task-42")))
      (is (search "subagent" child-key)
          "Child session key contains 'subagent'")
      (is (search "implementer" child-key)
          "Child session key contains agent ID")
      (is (search "task-42" child-key)
          "Child session key contains label")

      ;; Step 4: Build spawn config
      (let ((spawn-cfg (cl-claw.agents.spawn:make-spawn-config
                        :agent-id "implementer"
                        :session-key child-key
                        :cwd "/home/user/workspace"
                        :backend "acpx"
                        :parent-session-key "agent:ceo:main")))
        (is (string= "implementer"
                      (cl-claw.agents.spawn:spawn-config-agent-id spawn-cfg))
            "Spawn config has correct agent ID")
        (is (string= "agent:ceo:main"
                      (cl-claw.agents.spawn:spawn-config-parent-session-key spawn-cfg))
            "Spawn config links to parent session key")

        ;; Step 5: Build spawn environment
        (let ((env (cl-claw.agents.spawn:build-spawn-env spawn-cfg)))
          (is (string= "acp-client" (gethash "OPENCLAW_SHELL" env))
              "Spawn env sets OPENCLAW_SHELL=acp-client")
          (is (string= "implementer" (gethash "OPENCLAW_AGENT_ID" env))
              "Spawn env sets OPENCLAW_AGENT_ID")
          (is (string= "agent:ceo:main" (gethash "OPENCLAW_PARENT_SESSION_KEY" env))
              "Spawn env sets OPENCLAW_PARENT_SESSION_KEY"))

        ;; Step 6: Initialize child session in the manager
        (let ((child-entry (cl-claw.acp:manager-initialize-session
                            manager
                            :session-id "child-impl-42"
                            :session-key child-key
                            :cwd "/home/user/workspace")))
          (is (not (null child-entry))
              "Child session created successfully")

          ;; Step 7: Simulate active run on child
          (cl-claw.acp.session:session-store-set-active-run
           (cl-claw.acp::acp-manager-session-store manager)
           "child-impl-42" "run-001" :mock-controller)

          ;; Verify child has active run
          (let ((child-with-run (cl-claw.acp:manager-resolve-session
                                 manager "child-impl-42")))
            (is (string= "run-001"
                          (cl-claw.acp.types:acp-session-entry-active-run-id
                           child-with-run))
                "Child session has active run"))

          ;; Step 8: Set up stream relay from child to parent
          (let ((relay (cl-claw.agents.spawn:make-stream-relay
                        :parent-key "agent:ceo:main"
                        :child-key child-key)))
            (is (string= "agent:ceo:main"
                          (cl-claw.agents.spawn:stream-relay-parent-key relay))
                "Relay targets parent session")
            (is (not (cl-claw.agents.spawn:relay-closed-p relay))
                "Relay is initially open")

            ;; Step 9: Simulate sub-agent producing output
            (cl-claw.agents.spawn:relay-append relay "Task started: implementing feature X")
            (cl-claw.agents.spawn:relay-append relay "File created: src/feature-x.lisp")
            (cl-claw.agents.spawn:relay-append relay "Tests passing: 3/3")

            ;; Step 10: Parent flushes relay to collect results
            (let ((results (cl-claw.agents.spawn:relay-flush relay)))
              (is (= 3 (length results))
                  "Parent receives all 3 output chunks")
              (is (string= "Task started: implementing feature X" (first results))
                  "First chunk matches")
              (is (string= "Tests passing: 3/3" (third results))
                  "Last chunk matches"))

            ;; Verify flush clears buffer
            (let ((empty (cl-claw.agents.spawn:relay-flush relay)))
              (is (= 0 (length empty))
                  "Relay buffer empty after flush"))

            ;; Step 11: Close relay when sub-agent completes
            (cl-claw.agents.spawn:relay-close relay)
            (is (cl-claw.agents.spawn:relay-closed-p relay)
                "Relay is closed after sub-agent completes")

            ;; Step 12: Closed relay drops new appends silently
            (cl-claw.agents.spawn:relay-append relay "Should be dropped")
            (let ((post-close (cl-claw.agents.spawn:relay-flush relay)))
              (is (= 0 (length post-close))
                  "No new data after relay closed")))

          ;; Step 13: Cancel child's active run
          (cl-claw.acp.session:session-store-cancel-active-run
           (cl-claw.acp::acp-manager-session-store manager)
           "child-impl-42")
          (let ((child-done (cl-claw.acp:manager-resolve-session
                             manager "child-impl-42")))
            (is (null (cl-claw.acp.types:acp-session-entry-active-run-id child-done))
                "Child run cancelled after completion"))

          ;; Step 14: Close child session
          (let ((close-result (cl-claw.acp:manager-close-session
                               manager "child-impl-42")))
            (is (gethash "metaCleared" close-result)
                "Child session metadata cleared"))

          ;; Step 15: Parent session still exists and is operational
          (let ((parent-still (cl-claw.acp:manager-resolve-session
                               manager "parent-main")))
            (is (not (null parent-still))
                "Parent session survives child lifecycle")))))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 2: Concurrent sub-agent streams relay independently
;;; ═══════════════════════════════════════════════════════════════════════════

(test acp-subagent-concurrent-relays
  "Multiple sub-agents relay results concurrently without cross-contamination."
  (let ((relay-a (cl-claw.agents.spawn:make-stream-relay
                  :parent-key "agent:ceo:main"
                  :child-key "agent:ceo:main:subagent:worker-a"))
        (relay-b (cl-claw.agents.spawn:make-stream-relay
                  :parent-key "agent:ceo:main"
                  :child-key "agent:ceo:main:subagent:worker-b")))

    ;; Both sub-agents produce output concurrently
    (cl-claw.agents.spawn:relay-append relay-a "A: result 1")
    (cl-claw.agents.spawn:relay-append relay-b "B: result 1")
    (cl-claw.agents.spawn:relay-append relay-a "A: result 2")
    (cl-claw.agents.spawn:relay-append relay-b "B: result 2")

    ;; Flush independently
    (let ((a-results (cl-claw.agents.spawn:relay-flush relay-a))
          (b-results (cl-claw.agents.spawn:relay-flush relay-b)))
      (is (= 2 (length a-results)) "Worker A has 2 results")
      (is (= 2 (length b-results)) "Worker B has 2 results")
      (is (string= "A: result 1" (first a-results))
          "Worker A results are not contaminated by B")
      (is (string= "B: result 1" (first b-results))
          "Worker B results are not contaminated by A"))

    ;; Close independently
    (cl-claw.agents.spawn:relay-close relay-a)
    (is (cl-claw.agents.spawn:relay-closed-p relay-a)
        "Relay A closed")
    (is (not (cl-claw.agents.spawn:relay-closed-p relay-b))
        "Relay B still open after A closed")

    ;; B can still receive
    (cl-claw.agents.spawn:relay-append relay-b "B: final")
    (let ((b-final (cl-claw.agents.spawn:relay-flush relay-b)))
      (is (= 1 (length b-final))
          "Relay B receives after A closed"))
    (cl-claw.agents.spawn:relay-close relay-b)))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 3: Thread-safe relay under concurrent appends
;;; ═══════════════════════════════════════════════════════════════════════════

(test acp-subagent-relay-thread-safety
  "Stream relay handles concurrent appends from multiple threads safely."
  (let ((relay (cl-claw.agents.spawn:make-stream-relay
                :parent-key "parent" :child-key "child"))
        (threads nil)
        (per-thread 50)
        (num-threads 4))

    ;; Spawn threads that concurrently append
    (dotimes (i num-threads)
      (push (bt:make-thread
             (lambda ()
               (let ((tid (bt:current-thread)))
                 (dotimes (j per-thread)
                   (cl-claw.agents.spawn:relay-append
                    relay
                    (format nil "thread-~A-msg-~A" tid j)))))
             :name (format nil "relay-writer-~A" i))
            threads))

    ;; Wait for all threads
    (dolist (th threads)
      (bt:join-thread th))

    ;; Verify all messages arrived
    (let ((all-chunks (cl-claw.agents.spawn:relay-flush relay)))
      (is (= (* num-threads per-thread) (length all-chunks))
          (format nil "All ~A messages received from ~A threads"
                  (* num-threads per-thread) num-threads)))

    (cl-claw.agents.spawn:relay-close relay)))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 4: Spawn session key hierarchy
;;; ═══════════════════════════════════════════════════════════════════════════

(test acp-subagent-session-key-hierarchy
  "Session keys form a proper hierarchy from parent to sub-agent."
  ;; Top-level agent
  (let ((parent-key (cl-claw.agents.spawn:resolve-spawn-session-key "ceo")))
    (is (search "ceo" parent-key) "Parent key contains agent ID")

    ;; Sub-agent of the CEO
    (let ((child-key (cl-claw.agents.spawn:resolve-spawn-session-key
                      "implementer" :parent-key parent-key)))
      (is (search "subagent" child-key) "Child key has subagent marker")
      (is (search "implementer" child-key) "Child key has child agent ID")

      ;; Nested sub-agent (sub-sub-agent)
      (let ((grandchild-key (cl-claw.agents.spawn:resolve-spawn-session-key
                             "verifier" :parent-key child-key)))
        (is (search "subagent" grandchild-key)
            "Grandchild key has subagent marker")
        (is (search "verifier" grandchild-key)
            "Grandchild key has its agent ID")
        ;; Keys should all be distinct
        (is (not (string= parent-key child-key))
            "Parent and child keys are distinct")
        (is (not (string= child-key grandchild-key))
            "Child and grandchild keys are distinct")))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 5: Spawn env propagates parent linkage
;;; ═══════════════════════════════════════════════════════════════════════════

(test acp-subagent-env-parent-linkage
  "Spawn environment correctly propagates parent session key for sub-agents,
   and omits it for top-level spawns."
  ;; Sub-agent spawn: should have parent key
  (let* ((cfg (cl-claw.agents.spawn:make-spawn-config
               :agent-id "worker"
               :session-key "parent:subagent:worker"
               :cwd "/tmp"
               :parent-session-key "parent-key"))
         (env (cl-claw.agents.spawn:build-spawn-env cfg)))
    (is (string= "parent-key" (gethash "OPENCLAW_PARENT_SESSION_KEY" env))
        "Sub-agent env has OPENCLAW_PARENT_SESSION_KEY"))

  ;; Top-level spawn: should NOT have parent key
  (let* ((cfg (cl-claw.agents.spawn:make-spawn-config
               :agent-id "standalone"
               :session-key "agent:standalone:acp:direct"
               :cwd "/tmp"))
         (env (cl-claw.agents.spawn:build-spawn-env cfg)))
    (is (null (gethash "OPENCLAW_PARENT_SESSION_KEY" env))
        "Top-level spawn env has no OPENCLAW_PARENT_SESSION_KEY")))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 6: Manager handles child session lifecycle without affecting parent
;;; ═══════════════════════════════════════════════════════════════════════════

(test acp-subagent-manager-isolation
  "Parent and child sessions are isolated in the ACP manager."
  (let* ((dispatch (make-test-config "enabled" t))
         (acp-cfg (make-test-config "enabled" t "dispatch" dispatch))
         (config (make-test-config "acp" acp-cfg))
         (mgr (cl-claw.acp:make-acp-session-manager config)))

    ;; Create parent
    (cl-claw.acp:manager-initialize-session
     mgr :session-id "parent" :session-key "p:key" :cwd "/")

    ;; Create multiple children
    (cl-claw.acp:manager-initialize-session
     mgr :session-id "child-1" :session-key "c1:key" :cwd "/")
    (cl-claw.acp:manager-initialize-session
     mgr :session-id "child-2" :session-key "c2:key" :cwd "/")

    ;; Close child-1 — parent and child-2 unaffected
    (cl-claw.acp:manager-close-session mgr "child-1")
    (is (not (null (cl-claw.acp:manager-resolve-session mgr "parent")))
        "Parent survives child-1 close")
    (is (not (null (cl-claw.acp:manager-resolve-session mgr "child-2")))
        "Child-2 survives child-1 close")
    (is (null (cl-claw.acp:manager-resolve-session mgr "child-1"))
        "Child-1 is gone after close")

    ;; Close child-2
    (cl-claw.acp:manager-close-session mgr "child-2")
    (is (not (null (cl-claw.acp:manager-resolve-session mgr "parent")))
        "Parent survives all children closing")

    ;; Close parent last
    (cl-claw.acp:manager-close-session mgr "parent")
    (is (null (cl-claw.acp:manager-resolve-session mgr "parent"))
        "Parent closed at the end")))
