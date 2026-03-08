;;;; FiveAM tests for agents domain helpers

(defpackage :cl-claw.agents.test
  (:use :cl :fiveam))

(in-package :cl-claw.agents.test)

(declaim (optimize (safety 3) (debug 3)))

(def-suite agents-suite
  :description "Tests for agents config, sandbox bind parsing, and patch helpers")

(in-suite agents-suite)

(defun %hash (&rest kv)
  (let ((h (make-hash-table :test 'equal)))
    (loop for (k v) on kv by #'cddr do
      (setf (gethash k h) v))
    h))

(test resolve-openclaw-agent-dir-priority
  (is (string= "/a" (cl-claw.agents:resolve-openclaw-agent-dir :openclaw-agent-dir "/a"
                                                                  :pi-coding-agent-dir "/b"
                                                                  :openclaw-home "/c")))
  (is (string= "/b" (cl-claw.agents:resolve-openclaw-agent-dir :openclaw-agent-dir ""
                                                                  :pi-coding-agent-dir "/b"
                                                                  :openclaw-home "/c")))
  (is (search "/agents/" (cl-claw.agents:resolve-openclaw-agent-dir :openclaw-home "/tmp/openclaw"))))

(test resolve-agent-config-and-model-fields
  (let* ((agent (let ((h (%hash)))
                  (setf (gethash "model" h)
                        (%hash "primary" "anthropic/claude-sonnet-4-6"
                               "fallbacks" (list "openai/gpt-5.3-codex" "google/gemini-3.1-pro-preview")))
                  h))
         (cfg (%hash "agents" (%hash "list" (%hash "main" agent)))))
    (is (hash-table-p (cl-claw.agents:resolve-agent-config cfg "main")))
    (is (string= "anthropic/claude-sonnet-4-6"
                 (cl-claw.agents:resolve-agent-model-primary cfg "main")))
    (is (= 2 (length (cl-claw.agents:resolve-agent-model-fallbacks cfg "main"))))
    (is-true (cl-claw.agents:agent-has-model-fallbacks-p cfg "main"))))

(test split-sandbox-bind-spec
  (let ((parsed (cl-claw.agents.sandbox.bind-spec:split-sandbox-bind-spec "/tmp/host:/workspace:ro")))
    (is (hash-table-p parsed))
    (is (string= "/tmp/host" (gethash "host" parsed)))
    (is (string= "/workspace" (gethash "container" parsed)))
    (is (string= "ro" (gethash "options" parsed))))
  (let ((parsed (cl-claw.agents.sandbox.bind-spec:split-sandbox-bind-spec "C:\\tmp:/workspace")))
    (is (hash-table-p parsed))
    (is (string= "C:\\tmp" (gethash "host" parsed)))))

(defmacro with-temp-dir ((var) &body body)
  `(let* ((base (or (uiop:getenv "TMPDIR") "/tmp"))
          (,var (merge-pathnames
                 (format nil "cl-claw-agents-test-~a/" (gensym "D"))
                 (uiop:ensure-directory-pathname base))))
     (uiop:ensure-all-directories-exist (list ,var))
     (unwind-protect
          (progn ,@body)
       (uiop:delete-directory-tree ,var :validate t :if-does-not-exist :ignore))))

(test apply-patch-add-update-move-delete
  (with-temp-dir (dir)
    (let* ((cwd (namestring dir))
           (ops (list
                 (%hash "type" "add" "path" "notes/a.txt" "content" "v1")
                 (%hash "type" "update" "path" "notes/a.txt" "content" "v2")
                 (%hash "type" "move" "path" "notes/a.txt" "to" "notes/b.txt")
                 (%hash "type" "delete" "path" "notes/b.txt"))))
      (is (= 4 (length (cl-claw.agents.apply-patch:apply-patch ops cwd))))
      (is-false (probe-file (merge-pathnames "notes/b.txt" dir))))))

(test apply-patch-rejects-traversal-when-workspace-only
  (with-temp-dir (dir)
    (let ((ops (list (%hash "type" "add" "path" "../escape.txt" "content" "x"))))
      (signals error
        (cl-claw.agents.apply-patch:apply-patch ops (namestring dir) :workspace-only t)))))

(test apply-patch-allows-outside-when-workspace-only-disabled
  (with-temp-dir (dir)
    (let* ((outside (merge-pathnames "../escape.txt" dir))
           (ops (list (%hash "type" "add" "path" (namestring outside) "content" "x"))))
      (is (= 1 (length (cl-claw.agents.apply-patch:apply-patch ops (namestring dir)
                                                        :workspace-only nil)))))))
