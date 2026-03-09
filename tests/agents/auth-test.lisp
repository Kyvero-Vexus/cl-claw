;;;; auth-test.lisp — Tests for agent auth profiles

(in-package :cl-claw.agents.tests)

(in-suite :agent-auth)

(test auth-store-create
  "Creates an empty auth profile store"
  (let ((store (cl-claw.agents.auth-profiles:make-auth-profile-store)))
    (is (not (null store)))
    (is (= 0 (length (cl-claw.agents.auth-profiles:store-list-profiles store))))))

(test auth-store-crud
  "Adds, retrieves, removes profiles"
  (let ((store (cl-claw.agents.auth-profiles:make-auth-profile-store))
        (profile (make-test-config "type" "api-key"
                                   "key" "sk-test"
                                   "provider" "openai")))
    (cl-claw.agents.auth-profiles:store-set-profile store "p1" profile)
    (is (hash-table-p (cl-claw.agents.auth-profiles:store-get-profile store "p1")))
    (is (= 1 (length (cl-claw.agents.auth-profiles:store-list-profiles store))))
    (cl-claw.agents.auth-profiles:store-remove-profile store "p1")
    (is (null (cl-claw.agents.auth-profiles:store-get-profile store "p1")))))

(test auth-store-provider-filter
  "Filters profiles by provider"
  (let ((store (cl-claw.agents.auth-profiles:make-auth-profile-store)))
    (cl-claw.agents.auth-profiles:store-set-profile
     store "p1" (make-test-config "provider" "openai" "type" "api-key"))
    (cl-claw.agents.auth-profiles:store-set-profile
     store "p2" (make-test-config "provider" "anthropic" "type" "api-key"))
    (cl-claw.agents.auth-profiles:store-set-profile
     store "p3" (make-test-config "provider" "openai" "type" "oauth"))
    (let ((openai (cl-claw.agents.auth-profiles:store-profiles-for-provider store "openai")))
      (is (= 2 (length openai))))))

(test auth-token-expiry-state
  "Resolves token expiry state"
  (let ((now 1000000))
    ;; Valid (future)
    (is (string= "valid"
                  (cl-claw.agents.auth-profiles:resolve-token-expiry-state
                   (+ now 3600) now)))
    ;; Expired
    (is (string= "expired"
                  (cl-claw.agents.auth-profiles:resolve-token-expiry-state
                   (- now 100) now)))
    ;; Missing
    (is (string= "missing"
                  (cl-claw.agents.auth-profiles:resolve-token-expiry-state nil now)))
    ;; Invalid
    (is (string= "invalid_expires"
                  (cl-claw.agents.auth-profiles:resolve-token-expiry-state 0 now)))))

(test auth-cooldown
  "Sets and checks cooldown"
  (let ((store (cl-claw.agents.auth-profiles:make-auth-profile-store))
        (profile (make-test-config "provider" "openai" "type" "api-key")))
    (cl-claw.agents.auth-profiles:store-set-profile store "p1" profile)
    (cl-claw.agents.auth-profiles:set-profile-cooldown store "p1" 60000)
    (let ((cd (cl-claw.agents.auth-profiles:get-profile-cooldown store "p1")))
      (is (not (null cd))))
    (cl-claw.agents.auth-profiles:clear-profile-cooldown store "p1")
    (is (null (cl-claw.agents.auth-profiles:get-profile-cooldown store "p1")))))

(test auth-model-mode-resolution
  "Resolves model auth mode"
  (let ((store (cl-claw.agents.auth-profiles:make-auth-profile-store))
        (cfg (make-hash-table :test 'equal)))
    (is (stringp (cl-claw.agents.auth-profiles:resolve-model-auth-mode
                  "openai" cfg store)))))
