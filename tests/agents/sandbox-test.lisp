;;;; sandbox-test.lisp — Tests for sandbox bind spec parsing and sandbox config

(in-package :cl-claw.agents.tests)

(in-suite :agent-sandbox)

;;; ─── Bind Spec Parsing ──────────────────────────────────────────────────────

(test sandbox-bind-spec-basic
  "Parses basic host:container bind spec"
  (let ((result (cl-claw.agents.sandbox:split-sandbox-bind-spec "/host/path:/container/path")))
    (is (hash-table-p result))
    (is (string= "/host/path" (gethash "host" result)))
    (is (string= "/container/path" (gethash "container" result)))
    (is (string= "" (gethash "options" result)))))

(test sandbox-bind-spec-with-options
  "Parses bind spec with options"
  (let ((result (cl-claw.agents.sandbox:split-sandbox-bind-spec "/host:/cont:ro")))
    (is (hash-table-p result))
    (is (string= "/host" (gethash "host" result)))
    (is (string= "/cont" (gethash "container" result)))
    (is (string= "ro" (gethash "options" result)))))

(test sandbox-bind-spec-windows-drive
  "Handles Windows drive letter prefix"
  (let ((result (cl-claw.agents.sandbox:split-sandbox-bind-spec "C:\\Users\\test:/home/test")))
    (is (hash-table-p result))
    (is (string= "C:\\Users\\test" (gethash "host" result)))
    (is (string= "/home/test" (gethash "container" result)))))

(test sandbox-bind-spec-no-separator
  "Returns NIL for spec without separator"
  (is (null (cl-claw.agents.sandbox:split-sandbox-bind-spec "/just/a/path"))))

;;; ─── Workspace Isolation ────────────────────────────────────────────────────

(test sandbox-resolve-workspace
  "Resolves sandbox workspace path"
  (let ((ws (cl-claw.agents.sandbox:resolve-sandbox-workspace "myagent" "/opt/workspaces")))
    (is (search "sandbox" ws))
    (is (search "myagent" ws))))

;;; ─── Docker Volume Generation ───────────────────────────────────────────────

(test sandbox-generate-volumes
  "Generates Docker volume mount args"
  (let ((vols (cl-claw.agents.sandbox:generate-docker-volumes
               '("/host/a:/cont/a:ro" "/host/b:/cont/b")
               "/workspace")))
    (is (listp vols))
    ;; First should be workspace mount
    (is (search "/workspace" (first vols)))
    ;; Should have workspace + 2 bind specs = 3 total
    (is (= 3 (length vols)))))

;;; ─── Environment Isolation ──────────────────────────────────────────────────

(test sandbox-isolated-env
  "Builds isolated environment"
  (let* ((full (make-test-config "PATH" "/usr/bin" "SECRET" "hidden" "ALLOWED" "yes"))
         (env (cl-claw.agents.sandbox:build-isolated-env
               full '("ALLOWED") :workspace "/sandbox/ws")))
    (is (string= "/sandbox/ws" (gethash "WORKSPACE" env)))
    (is (string= "yes" (gethash "ALLOWED" env)))
    (is (string= "/usr/bin" (gethash "PATH" env)))
    ;; SECRET should not pass through
    (is (null (gethash "SECRET" env)))))
