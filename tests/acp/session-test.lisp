;;;; session-test.lisp — Tests for ACP session store

(in-package :cl-claw.acp.tests)

(in-suite :acp-session)

(test session-create-and-retrieve
  "Create a session and retrieve it by ID"
  (let ((store (cl-claw.acp.session:create-session-store)))
    (let ((entry (cl-claw.acp.session:session-store-create-session
                  store :session-id "test-1"
                        :session-key "acp:test"
                        :cwd "/tmp")))
      (is (string= "test-1" (cl-claw.acp.types:acp-session-entry-session-id entry)))
      (is (string= "acp:test" (cl-claw.acp.types:acp-session-entry-session-key entry)))
      (is (string= "/tmp" (cl-claw.acp.types:acp-session-entry-cwd entry)))
      ;; Retrieve
      (let ((got (cl-claw.acp.session:session-store-get-session store "test-1")))
        (is (not (null got)))
        (is (eq got entry)))
      (is (cl-claw.acp.session:session-store-has-session-p store "test-1"))
      (is (not (cl-claw.acp.session:session-store-has-session-p store "nonexistent"))))))

(test session-active-run-tracking
  "Tracks active runs and clears on cancel"
  (let ((store (cl-claw.acp.session:create-session-store)))
    (let ((session (cl-claw.acp.session:session-store-create-session
                    store :session-id "s1"
                          :session-key "acp:test"
                          :cwd "/tmp")))
      (cl-claw.acp.session:session-store-set-active-run store "s1" "run-1" :fake-controller)
      ;; Lookup by run ID
      (let ((found (cl-claw.acp.session:session-store-get-session-by-run-id store "run-1")))
        (is (not (null found)))
        (is (string= "s1" (cl-claw.acp.types:acp-session-entry-session-id found))))
      ;; Cancel
      (is (cl-claw.acp.session:session-store-cancel-active-run store "s1"))
      (is (null (cl-claw.acp.session:session-store-get-session-by-run-id store "run-1")))
      ;; Cancel again returns nil
      (is (not (cl-claw.acp.session:session-store-cancel-active-run store "s1"))))))

(test session-refresh-existing
  "Refreshes existing session IDs instead of creating duplicates"
  (let* ((now-val 1000)
         (store (cl-claw.acp.session:create-session-store
                 :now (lambda () now-val))))
    (let ((first (cl-claw.acp.session:session-store-create-session
                  store :session-id "existing"
                        :session-key "acp:one"
                        :cwd "/tmp/one")))
      (incf now-val 500)
      (let ((refreshed (cl-claw.acp.session:session-store-create-session
                        store :session-id "existing"
                              :session-key "acp:two"
                              :cwd "/tmp/two")))
        (is (eq refreshed first))
        (is (string= "acp:two" (cl-claw.acp.types:acp-session-entry-session-key refreshed)))
        (is (string= "/tmp/two" (cl-claw.acp.types:acp-session-entry-cwd refreshed)))
        (is (= 1000 (cl-claw.acp.types:acp-session-entry-created-at refreshed)))
        (is (= 1500 (cl-claw.acp.types:acp-session-entry-last-touched-at refreshed)))))))

(test session-idle-reaping
  "Reaps idle sessions before enforcing the max session cap"
  (let* ((now-val 1000)
         (store (cl-claw.acp.session:create-session-store
                 :max-sessions 1
                 :idle-ttl-ms 1000
                 :now (lambda () now-val))))
    (cl-claw.acp.session:session-store-create-session
     store :session-id "old" :session-key "acp:old" :cwd "/tmp")
    (incf now-val 2000)
    (let ((fresh (cl-claw.acp.session:session-store-create-session
                  store :session-id "fresh" :session-key "acp:fresh" :cwd "/tmp")))
      (is (string= "fresh" (cl-claw.acp.types:acp-session-entry-session-id fresh)))
      (is (null (cl-claw.acp.session:session-store-get-session store "old")))
      (is (not (cl-claw.acp.session:session-store-has-session-p store "old"))))))

(test session-soft-eviction
  "Uses soft-cap eviction for the oldest idle session when full"
  (let* ((now-val 1000)
         (store (cl-claw.acp.session:create-session-store
                 :max-sessions 2
                 :idle-ttl-ms (* 24 60 60 1000)
                 :now (lambda () now-val))))
    (cl-claw.acp.session:session-store-create-session
     store :session-id "first" :session-key "acp:first" :cwd "/tmp")
    (incf now-val 100)
    (cl-claw.acp.session:session-store-create-session
     store :session-id "second" :session-key "acp:second" :cwd "/tmp")
    ;; Make second have an active run (non-evictable)
    (cl-claw.acp.session:session-store-set-active-run store "second" "run-2" :controller)
    (incf now-val 100)
    ;; Third should evict first (oldest idle)
    (let ((third (cl-claw.acp.session:session-store-create-session
                  store :session-id "third" :session-key "acp:third" :cwd "/tmp")))
      (is (string= "third" (cl-claw.acp.types:acp-session-entry-session-id third)))
      (is (null (cl-claw.acp.session:session-store-get-session store "first")))
      (is (not (null (cl-claw.acp.session:session-store-get-session store "second")))))))

(test session-rejects-when-full
  "Rejects when full and no session is evictable"
  (let* ((now-val 1000)
         (store (cl-claw.acp.session:create-session-store
                 :max-sessions 1
                 :idle-ttl-ms (* 24 60 60 1000)
                 :now (lambda () now-val))))
    (let ((only (cl-claw.acp.session:session-store-create-session
                 store :session-id "only" :session-key "acp:only" :cwd "/tmp")))
      (cl-claw.acp.session:session-store-set-active-run store "only" "run-only" :controller)
      (signals cl-claw.acp.types:acp-session-full-error
        (cl-claw.acp.session:session-store-create-session
         store :session-id "next" :session-key "acp:next" :cwd "/tmp")))))

(test session-list-and-remove
  "Lists sessions and removes them"
  (let ((store (cl-claw.acp.session:create-session-store)))
    (cl-claw.acp.session:session-store-create-session
     store :session-id "a" :session-key "k:a" :cwd "/")
    (cl-claw.acp.session:session-store-create-session
     store :session-id "b" :session-key "k:b" :cwd "/")
    (is (= 2 (length (cl-claw.acp.session:session-store-list-sessions store))))
    (is (cl-claw.acp.session:session-store-remove-session store "a"))
    (is (= 1 (length (cl-claw.acp.session:session-store-list-sessions store))))
    (is (not (cl-claw.acp.session:session-store-remove-session store "nonexistent")))))

(test session-clear-all
  "Clears all sessions"
  (let ((store (cl-claw.acp.session:create-session-store)))
    (cl-claw.acp.session:session-store-create-session
     store :session-id "a" :session-key "k:a" :cwd "/")
    (cl-claw.acp.session:session-store-create-session
     store :session-id "b" :session-key "k:b" :cwd "/")
    (cl-claw.acp.session:session-store-clear-all store)
    (is (= 0 (length (cl-claw.acp.session:session-store-list-sessions store))))))
