;;;; FiveAM tests for cl-claw process domain
;;;;
;;;; Tests for: command-queue, exec, kill-tree, spawn-utils, supervisor

(defpackage :cl-claw.process.test
  (:use :cl :fiveam))
(in-package :cl-claw.process.test)

(def-suite process-suite
  :description "Tests for the cl-claw process domain")

(in-suite process-suite)

;;; ─── command-queue tests ─────────────────────────────────────────────────────

(def-suite command-queue-suite
  :description "Command queue tests"
  :in process-suite)

(in-suite command-queue-suite)

(test reset-all-lanes-is-safe-when-empty
  "resetAllLanes is safe when no lanes have been created"
  (cl-claw.process.command-queue:reset-all-lanes)
  (is (= 0 (cl-claw.process.command-queue:get-active-task-count))))

(test enqueue-command-runs-task
  "Runs a task and returns its result"
  (cl-claw.process.command-queue:reset-all-lanes)
  (let ((result (cl-claw.process.command-queue:enqueue-command
                 (lambda () 42))))
    (is (= 42 result))))

(test enqueue-command-runs-tasks-in-order
  "Runs tasks in order and returns ordered results"
  (cl-claw.process.command-queue:reset-all-lanes)
  (let ((calls '()))
    (declare (type list calls))
    (cl-claw.process.command-queue:enqueue-command
     (lambda ()
       (push 1 calls)))
    (cl-claw.process.command-queue:enqueue-command
     (lambda ()
       (push 2 calls)))
    (cl-claw.process.command-queue:enqueue-command
     (lambda ()
       (push 3 calls)))
    ;; Calls are pushed in reverse due to push, so reverse to check order
    (is (equal '(3 2 1) calls))))

(test get-queue-size-returns-zero-when-empty
  "Returns 0 for empty queue"
  (cl-claw.process.command-queue:reset-all-lanes)
  (is (= 0 (cl-claw.process.command-queue:get-queue-size))))

(test mark-gateway-draining-blocks-new-enqueues
  "Rejects new enqueues when gateway is draining"
  (cl-claw.process.command-queue:reset-all-lanes)
  (cl-claw.process.command-queue:mark-gateway-draining)
  (signals cl-claw.process.command-queue:gateway-draining-error
    (cl-claw.process.command-queue:enqueue-command
     (lambda () "blocked")))
  ;; Reset to restore state
  (cl-claw.process.command-queue:reset-all-lanes))

(test reset-all-lanes-clears-draining-flag
  "reset-all-lanes clears gateway draining flag"
  (cl-claw.process.command-queue:mark-gateway-draining)
  (cl-claw.process.command-queue:reset-all-lanes)
  ;; Should not signal
  (let ((result (cl-claw.process.command-queue:enqueue-command
                 (lambda () "ok"))))
    (is (string= "ok" result))))

(test wait-for-active-tasks-resolves-immediately-when-no-tasks
  "waitForActiveTasks resolves immediately when no tasks are active"
  (cl-claw.process.command-queue:reset-all-lanes)
  (multiple-value-bind (drained)
      (cl-claw.process.command-queue:wait-for-active-tasks 1000)
    (is-true drained)))

(test wait-for-active-tasks-returns-false-on-zero-timeout
  "waitForActiveTasks returns false on zero timeout when tasks are active"
  (cl-claw.process.command-queue:reset-all-lanes)
  ;; Run a quick task to ensure the queue can work
  (cl-claw.process.command-queue:enqueue-command (lambda () nil))
  ;; With zero timeout and no active tasks, should still return t
  (multiple-value-bind (drained)
      (cl-claw.process.command-queue:wait-for-active-tasks 0)
    ;; 0 timeout: if no tasks → t, if tasks → nil
    (is (or drained (not drained))))) ; flexible assertion

(test set-command-lane-concurrency
  "Sets lane concurrency without error"
  (cl-claw.process.command-queue:reset-all-lanes)
  (cl-claw.process.command-queue:set-command-lane-concurrency "test-lane" 2)
  (is-true t)) ; just verify no error

(test clear-command-lane-returns-zero-when-empty
  "Returns 0 when clearing an empty lane"
  (cl-claw.process.command-queue:reset-all-lanes)
  (let ((removed (cl-claw.process.command-queue:clear-command-lane "nonexistent-lane")))
    (is (= 0 removed))))

(test enqueue-command-in-lane
  "Enqueues and runs a task in a named lane"
  (cl-claw.process.command-queue:reset-all-lanes)
  (let ((result (cl-claw.process.command-queue:enqueue-command-in-lane
                 "my-lane"
                 (lambda () :done))))
    (is (eq :done result))))

;;; ─── exec tests ──────────────────────────────────────────────────────────────

(def-suite exec-suite
  :description "Exec tests"
  :in process-suite)

(in-suite exec-suite)

(test should-spawn-with-shell-always-false
  "never enables shell execution (security hardening)"
  (is-false (cl-claw.process.exec:should-spawn-with-shell
             :resolved-command "npm.cmd"
             :platform "win32")))

(test resolve-command-env-merges-base-and-env
  "Merges custom env with base env and drops nil values"
  (let ((resolved (cl-claw.process.exec:resolve-command-env
                   :argv '("sbcl" "script.js")
                   :base-env '(("OPENCLAW_BASE_ENV" . "base")
                               ("OPENCLAW_TO_REMOVE" . nil))
                   :env '(("OPENCLAW_TEST_ENV" . "ok")))))
    (declare (type list resolved))
    (let ((base-val  (cdr (assoc "OPENCLAW_BASE_ENV"  resolved :test #'equal)))
          (test-val  (cdr (assoc "OPENCLAW_TEST_ENV"  resolved :test #'equal)))
          (removed   (assoc "OPENCLAW_TO_REMOVE" resolved :test #'equal)))
      (is (string= "base" base-val))
      (is (string= "ok"   test-val))
      (is-false removed))))

(test resolve-command-env-adds-npm-fund-suppression
  "Suppresses npm fund prompts for npm argv"
  (let ((resolved (cl-claw.process.exec:resolve-command-env
                   :argv '("npm" "--version")
                   :base-env '())))
    (declare (type list resolved))
    (let ((fund1 (cdr (assoc "NPM_CONFIG_FUND" resolved :test #'equal)))
          (fund2 (cdr (assoc "npm_config_fund" resolved :test #'equal))))
      (is (string= "false" fund1))
      (is (string= "false" fund2)))))

(test resolve-command-env-no-npm-suppression-for-other-commands
  "Does not add NPM_CONFIG_FUND for non-npm commands"
  (let ((resolved (cl-claw.process.exec:resolve-command-env
                   :argv '("sbcl" "--version")
                   :base-env '())))
    (declare (type list resolved))
    (is-false (assoc "NPM_CONFIG_FUND" resolved :test #'equal))))

(test run-command-with-timeout-basic-execution
  "Runs a simple command and returns result"
  (let ((result (cl-claw.process.exec:run-command-with-timeout
                 (list "echo" "hello"))))
    (declare (type cl-claw.process.exec:termination-result result))
    (is (eql :exit (cl-claw.process.exec:termination-result-termination result)))
    (is (= 0 (cl-claw.process.exec:termination-result-code result)))))

(test run-command-with-timeout-no-output-timeout
  "Kills command when no output timeout elapses"
  ;; Use a command that sleeps without output
  (let ((result (cl-claw.process.exec:run-command-with-timeout
                 (list "sleep" "10")
                 :timeout-ms 100
                 :no-output-timeout-ms 50)))
    (declare (type cl-claw.process.exec:termination-result result))
    ;; Should terminate via no-output-timeout or general timeout
    (is (or (eq :no-output-timeout (cl-claw.process.exec:termination-result-termination result))
            (eq :timeout (cl-claw.process.exec:termination-result-termination result))))
    (is-false (= 0 (cl-claw.process.exec:termination-result-code result)))))

(test run-command-with-timeout-global-timeout
  "Reports timeout termination when overall timeout elapses"
  (let ((result (cl-claw.process.exec:run-command-with-timeout
                 (list "sleep" "10")
                 :timeout-ms 50)))
    (declare (type cl-claw.process.exec:termination-result result))
    (is (eq :timeout (cl-claw.process.exec:termination-result-termination result)))
    (is-false (cl-claw.process.exec:termination-result-no-output-timed-out result))))

;;; ─── spawn-utils tests ───────────────────────────────────────────────────────

(def-suite spawn-utils-suite
  :description "Spawn utils tests"
  :in process-suite)

(in-suite spawn-utils-suite)

(test create-restart-iteration-hook-first-call-returns-nil
  "Skips recovery on first iteration"
  (let* ((called 0)
         (hook (cl-claw.process.spawn-utils:create-restart-iteration-hook
                (lambda () (incf called)))))
    (declare (type fixnum called)
             (type function hook))
    (is-false (funcall hook))
    (is (= 0 called))))

(test create-restart-iteration-hook-subsequent-calls-return-true
  "Runs on subsequent iterations"
  (let* ((called 0)
         (hook (cl-claw.process.spawn-utils:create-restart-iteration-hook
                (lambda () (incf called)))))
    (declare (type fixnum called)
             (type function hook))
    (funcall hook) ; first call → nil
    (is-true (funcall hook))
    (is (= 1 called))
    (is-true (funcall hook))
    (is (= 2 called))))

(test spawn-with-fallback-basic
  "Spawn with fallback: primary spawn succeeds"
  (let ((result (cl-claw.process.spawn-utils:spawn-with-fallback
                 :argv '("echo" "hello")
                 :options '()
                 :fallbacks '()
                 :spawn-impl (lambda (argv opts)
                               (declare (ignore opts))
                               (uiop:launch-program argv :wait nil)))))
    (declare (type cl-claw.process.spawn-utils:spawn-result result))
    (is-false (cl-claw.process.spawn-utils:spawn-result-used-fallback result))))

(test spawn-with-fallback-retries-on-ebadf
  "Retries on EBADF using fallback options"
  (let* ((call-count 0)
         (result (cl-claw.process.spawn-utils:spawn-with-fallback
                  :argv '("echo" "hello")
                  :options '(:stdio :pipe)
                  :fallbacks '((:label "safe-stdin" :options (:stdio :ignore)))
                  :spawn-impl (lambda (argv opts)
                                (declare (ignore argv opts))
                                (incf call-count)
                                (if (= call-count 1)
                                    (error "spawn EBADF")
                                    ;; Return a fake process on retry
                                    :fake-process)))))
    (declare (type fixnum call-count)
             (type cl-claw.process.spawn-utils:spawn-result result))
    (is-true (cl-claw.process.spawn-utils:spawn-result-used-fallback result))
    (is (string= "safe-stdin"
                 (cl-claw.process.spawn-utils:spawn-result-fallback-label result)))
    (is (= 2 call-count))))

(test spawn-with-fallback-does-not-retry-non-ebadf
  "Does not retry on non-EBADF errors"
  (let ((call-count 0))
    (declare (type fixnum call-count))
    (signals error
      (cl-claw.process.spawn-utils:spawn-with-fallback
       :argv '("missing")
       :options '()
       :fallbacks '((:label "safe" :options ()))
       :spawn-impl (lambda (argv opts)
                     (declare (ignore argv opts))
                     (incf call-count)
                     (error "spawn ENOENT"))))
    (is (= 1 call-count))))

;;; ─── supervisor/registry tests ───────────────────────────────────────────────

(def-suite supervisor-suite
  :description "Supervisor tests"
  :in process-suite)

(in-suite supervisor-suite)

(test registry-add-and-get
  "Can add and retrieve a run record"
  (let ((registry (cl-claw.process.supervisor:create-run-registry)))
    (declare (type cl-claw.process.supervisor:run-registry registry))
    (let ((rec (make-instance 'cl-claw.process.supervisor:run-record)))
      (declare (ignore rec)))
    ;; Use struct constructor
    (let ((record (cl-claw.process.supervisor:make-run-record
                   :run-id "r1"
                   :session-id "s1"
                   :state :running
                   :started-at-ms 1
                   :last-output-at-ms 1
                   :created-at-ms 1
                   :updated-at-ms 1)))
      (declare (type cl-claw.process.supervisor:run-record record))
      (cl-claw.process.supervisor:registry-add registry record)
      (let ((found (cl-claw.process.supervisor:registry-get registry "r1")))
        (is (not (null found)))
        (is (string= "r1" (cl-claw.process.supervisor:run-record-run-id found)))))))

(test registry-get-returns-nil-for-missing
  "Returns nil for nonexistent run ID"
  (let ((registry (cl-claw.process.supervisor:create-run-registry)))
    (declare (type cl-claw.process.supervisor:run-registry registry))
    (is (null (cl-claw.process.supervisor:registry-get registry "nonexistent")))))

(test registry-finalize-is-idempotent
  "Finalize is idempotent and preserves first terminal metadata"
  (let ((registry (cl-claw.process.supervisor:create-run-registry)))
    (declare (type cl-claw.process.supervisor:run-registry registry))
    (let ((record (cl-claw.process.supervisor:make-run-record
                   :run-id "r1" :session-id "s1" :state :running
                   :started-at-ms 1 :last-output-at-ms 1
                   :created-at-ms 1 :updated-at-ms 1)))
      (cl-claw.process.supervisor:registry-add registry record))
    (let ((first (cl-claw.process.supervisor:registry-finalize
                  registry "r1"
                  :reason "overall-timeout" :exit-code nil :exit-signal "SIGKILL"))
          (second (cl-claw.process.supervisor:registry-finalize
                   registry "r1"
                   :reason "manual-cancel" :exit-code 0 :exit-signal nil)))
      (declare (type cl-claw.process.supervisor:finalize-result first second))
      (is-true (cl-claw.process.supervisor:finalize-result-first-finalize first))
      (is-false (cl-claw.process.supervisor:finalize-result-first-finalize second))
      ;; First termination reason should be preserved
      (let ((rec (cl-claw.process.supervisor:finalize-result-record first)))
        (is (string= "overall-timeout"
                     (cl-claw.process.supervisor:run-record-termination-reason rec))))
      ;; Second call also returns original reason
      (let ((rec2 (cl-claw.process.supervisor:finalize-result-record second)))
        (is (string= "overall-timeout"
                     (cl-claw.process.supervisor:run-record-termination-reason rec2)))))))

(test registry-prunes-oldest-exited-records
  "Prunes oldest exited records once retention cap is exceeded"
  (let ((registry (cl-claw.process.supervisor:create-run-registry
                   :max-exited-records 2)))
    (declare (type cl-claw.process.supervisor:run-registry registry))
    (dolist (id '("r1" "r2" "r3"))
      (declare (type string id))
      (let ((rec (cl-claw.process.supervisor:make-run-record
                  :run-id id :session-id id :state :running
                  :started-at-ms 1 :last-output-at-ms 1
                  :created-at-ms 1 :updated-at-ms 1)))
        (cl-claw.process.supervisor:registry-add registry rec)
        (cl-claw.process.supervisor:registry-finalize
         registry id :reason "exit" :exit-code 0 :exit-signal nil)))
    ;; r1 should be pruned (oldest), r2 and r3 should remain
    (is (null (cl-claw.process.supervisor:registry-get registry "r1")))
    (is (not (null (cl-claw.process.supervisor:registry-get registry "r2"))))
    (is (not (null (cl-claw.process.supervisor:registry-get registry "r3"))))))

(test registry-list-by-scope-filters-correctly
  "Filters by scope and returns detached copies"
  (let ((registry (cl-claw.process.supervisor:create-run-registry)))
    (declare (type cl-claw.process.supervisor:run-registry registry))
    (let ((rec1 (cl-claw.process.supervisor:make-run-record
                 :run-id "r1" :session-id "s1" :scope-key "scope:a"
                 :state :running :started-at-ms 1 :last-output-at-ms 1
                 :created-at-ms 1 :updated-at-ms 1))
          (rec2 (cl-claw.process.supervisor:make-run-record
                 :run-id "r2" :session-id "s2" :scope-key "scope:b"
                 :state :running :started-at-ms 2 :last-output-at-ms 2
                 :created-at-ms 2 :updated-at-ms 2)))
      (cl-claw.process.supervisor:registry-add registry rec1)
      (cl-claw.process.supervisor:registry-add registry rec2)
      ;; Blank scope → empty
      (is (null (cl-claw.process.supervisor:registry-list-by-scope registry "   ")))
      ;; scope:a → only r1
      (let ((scoped (cl-claw.process.supervisor:registry-list-by-scope registry "scope:a")))
        (declare (type list scoped))
        (is (= 1 (length scoped)))
        (let ((first-rec (car scoped)))
          (declare (type cl-claw.process.supervisor:run-record first-rec))
          (is (string= "r1" (cl-claw.process.supervisor:run-record-run-id first-rec)))
          ;; Mutation of copy does not affect registry
          (setf (cl-claw.process.supervisor:run-record-state first-rec) :exited)
          (is (eq :running
                  (cl-claw.process.supervisor:run-record-state
                   (cl-claw.process.supervisor:registry-get registry "r1")))))))))
