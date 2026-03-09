;;;; runtime-cache-test.lisp — Tests for ACP runtime cache

(in-package :cl-claw.acp.tests)

(in-suite :acp-runtime-cache)

(defun %make-test-state (&key (backend "test-be") (agent "test-agent") (mode "persistent"))
  (cl-claw.acp.types:make-cached-runtime-state
   :backend backend :agent agent :mode mode))

(test cache-set-and-get
  "Set and retrieve entries from runtime cache"
  (let ((cache (cl-claw.acp.runtime-cache:make-runtime-cache)))
    (let ((state (%make-test-state)))
      (cl-claw.acp.runtime-cache:runtime-cache-set cache "actor-1" state :now 1000)
      (let ((got (cl-claw.acp.runtime-cache:runtime-cache-get cache "actor-1")))
        (is (not (null got)))
        (is (string= "test-be" (cl-claw.acp.types:cached-runtime-state-backend got))))
      (is (null (cl-claw.acp.runtime-cache:runtime-cache-get cache "nonexistent"))))))

(test cache-touch-on-get
  "Getting an entry updates its last-touched-at"
  (let ((cache (cl-claw.acp.runtime-cache:make-runtime-cache)))
    (let ((state (%make-test-state)))
      (cl-claw.acp.runtime-cache:runtime-cache-set cache "a" state :now 1000)
      (cl-claw.acp.runtime-cache:runtime-cache-get cache "a" :now 2000)
      (is (= 2000 (cl-claw.acp.types:cached-runtime-state-last-touched-at state))))))

(test cache-remove
  "Remove entries from cache"
  (let ((cache (cl-claw.acp.runtime-cache:make-runtime-cache)))
    (cl-claw.acp.runtime-cache:runtime-cache-set cache "a" (%make-test-state) :now 100)
    (is (cl-claw.acp.runtime-cache:runtime-cache-has-p cache "a"))
    (is (cl-claw.acp.runtime-cache:runtime-cache-remove cache "a"))
    (is (not (cl-claw.acp.runtime-cache:runtime-cache-has-p cache "a")))
    (is (not (cl-claw.acp.runtime-cache:runtime-cache-remove cache "a")))))

(test cache-size-and-clear
  "Size tracking and clear"
  (let ((cache (cl-claw.acp.runtime-cache:make-runtime-cache)))
    (is (= 0 (cl-claw.acp.runtime-cache:runtime-cache-size cache)))
    (cl-claw.acp.runtime-cache:runtime-cache-set cache "a" (%make-test-state) :now 100)
    (cl-claw.acp.runtime-cache:runtime-cache-set cache "b" (%make-test-state) :now 100)
    (is (= 2 (cl-claw.acp.runtime-cache:runtime-cache-size cache)))
    (cl-claw.acp.runtime-cache:runtime-cache-clear cache)
    (is (= 0 (cl-claw.acp.runtime-cache:runtime-cache-size cache)))))

(test cache-idle-candidates
  "Collects entries idle beyond threshold"
  (let ((cache (cl-claw.acp.runtime-cache:make-runtime-cache)))
    (cl-claw.acp.runtime-cache:runtime-cache-set cache "old" (%make-test-state) :now 100)
    (cl-claw.acp.runtime-cache:runtime-cache-set cache "new" (%make-test-state) :now 900)
    (let ((candidates (cl-claw.acp.runtime-cache:runtime-cache-collect-idle-candidates
                       cache :max-idle-ms 500 :now 1000)))
      (is (= 1 (length candidates)))
      (is (string= "old" (cl-claw.acp.types:acp-idle-candidate-actor-key (first candidates))))
      (is (= 900 (cl-claw.acp.types:acp-idle-candidate-idle-ms (first candidates)))))))

(test cache-snapshot
  "Creates point-in-time snapshot of all entries"
  (let ((cache (cl-claw.acp.runtime-cache:make-runtime-cache)))
    (cl-claw.acp.runtime-cache:runtime-cache-set
     cache "a" (%make-test-state :backend "be-a" :agent "agent-a") :now 500)
    (cl-claw.acp.runtime-cache:runtime-cache-set
     cache "b" (%make-test-state :backend "be-b" :agent "agent-b") :now 800)
    (let ((snapshot (cl-claw.acp.runtime-cache:runtime-cache-snapshot cache :now 1000)))
      (is (= 2 (length snapshot)))
      ;; Check that idle-ms is computed correctly
      (let ((entry-a (find "a" snapshot :key #'cl-claw.acp.types:acp-snapshot-entry-actor-key
                                        :test #'string=)))
        (is (not (null entry-a)))
        (is (= 500 (cl-claw.acp.types:acp-snapshot-entry-idle-ms entry-a)))))))
