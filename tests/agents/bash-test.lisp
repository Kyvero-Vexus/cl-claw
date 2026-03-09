;;;; bash-test.lisp — Tests for agent bash tools

(in-package :cl-claw.agents.tests)

(in-suite :agent-bash)

(test bash-process-registry
  "Creates and manages process sessions in registry"
  (let ((reg (cl-claw.agents.bash-tools:make-process-registry)))
    (is (= 0 (length (cl-claw.agents.bash-tools:registry-list-sessions reg))))
    ;; Add a session
    (let ((session (cl-claw.agents.bash-tools:make-process-session
                    :id "s1" :command "echo hello" :cwd "/tmp")))
      (cl-claw.agents.bash-tools:registry-add-session reg session)
      (is (= 1 (length (cl-claw.agents.bash-tools:registry-list-sessions reg))))
      ;; Get by ID
      (let ((got (cl-claw.agents.bash-tools:registry-get-session reg "s1")))
        (is (not (null got)))
        (is (string= "echo hello"
                      (cl-claw.agents.bash-tools:process-session-command got))))
      ;; Remove
      (cl-claw.agents.bash-tools:registry-remove-session reg "s1")
      (is (= 0 (length (cl-claw.agents.bash-tools:registry-list-sessions reg)))))))

(test bash-registry-reset
  "Resets registry clearing all sessions"
  (let ((reg (cl-claw.agents.bash-tools:make-process-registry)))
    (cl-claw.agents.bash-tools:registry-add-session
     reg (cl-claw.agents.bash-tools:make-process-session
          :id "a" :command "cmd" :cwd "/"))
    (cl-claw.agents.bash-tools:registry-add-session
     reg (cl-claw.agents.bash-tools:make-process-session
          :id "b" :command "cmd" :cwd "/"))
    (cl-claw.agents.bash-tools:registry-reset reg)
    (is (= 0 (length (cl-claw.agents.bash-tools:registry-list-sessions reg))))))

(test bash-docker-exec-args
  "Builds Docker exec arguments"
  (let ((args (cl-claw.agents.bash-tools:build-docker-exec-args
               "my-sandbox" "ls -la"
               :user "agent"
               :workdir "/workspace")))
    (is (listp args))
    (is (find "my-sandbox" args :test #'string=))
    (is (find "docker" args :test #'string=))))
