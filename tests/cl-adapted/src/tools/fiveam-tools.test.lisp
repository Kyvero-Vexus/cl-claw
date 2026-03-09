;;;; fiveam-tools.test.lisp — Tests for the tool execution framework
;;;;
;;;; Covers: types, dispatch, file-ops, exec, web, browser, approval, core.

(defpackage :cl-claw.tools.test
  (:use :cl :fiveam)
  (:import-from :cl-claw.tools
                ;; Types
                :tool-definition
                :make-tool-definition
                :tool-definition-name
                :tool-definition-description
                :tool-definition-handler
                :tool-definition-requires-approval-p
                :tool-definition-category
                :tool-call
                :make-tool-call
                :tool-call-id
                :tool-call-name
                :tool-call-arguments
                :tool-result
                :make-tool-result
                :tool-result-call-id
                :tool-result-content
                :tool-result-error-p
                :approval-decision
                :make-approval-decision
                :approval-decision-approved-p
                :approval-decision-reason
                :+permission-allow+
                :+permission-deny+
                :+permission-ask+
                ;; Registry
                :register-tool
                :unregister-tool
                :get-tool
                :list-tool-names
                :list-tools
                :clear-tool-registry
                :dispatch-tool-call
                ;; Permissions
                :set-tool-permission
                :get-tool-permission
                :check-tool-permission
                :set-tool-allowlist
                :tool-allowed-p
                ;; Approval
                :set-security-mode
                :set-approval-callback
                :auto-approve
                :allow-tools
                :deny-tools
                :require-approval-for-tools
                :reset-security-policy
                :+security-deny+
                :+security-allowlist+
                :+security-full+
                ;; Init
                :register-all-tools
                :initialize-tool-system
                ;; Handlers
                :handle-read-tool
                :handle-write-tool
                :handle-edit-tool
                :handle-exec-tool
                :handle-browser-tool))

(in-package :cl-claw.tools.test)

(def-suite tools-suite
  :description "Tool execution framework tests")

(in-suite tools-suite)

;;; -----------------------------------------------------------------------
;;; Helpers
;;; -----------------------------------------------------------------------

(defun make-args (&rest pairs)
  "Create a hash-table from alternating key-value pairs."
  (let ((ht (make-hash-table :test 'equal)))
    (loop for (k v) on pairs by #'cddr
          do (setf (gethash k ht) v))
    ht))

(defun echo-handler (args)
  "Simple echo handler for testing."
  (declare (type hash-table args))
  (or (gethash "message" args) "echo"))

(defun error-handler (args)
  "Handler that always errors."
  (declare (ignore args))
  (error "intentional test error"))

(defun make-temp-file (&optional (content "hello world"))
  "Create a temp file and return its path."
  (let ((path (format nil "/tmp/cl-claw-tool-test-~D.txt" (get-universal-time))))
    (with-open-file (s path :direction :output :if-exists :supersede)
      (write-string content s))
    path))

(defun cleanup-file (path)
  (when (probe-file path)
    (delete-file path)))

;;; Setup/teardown — clear registry before each test group
(defmacro with-clean-registry (&body body)
  `(progn
     (clear-tool-registry)
     (reset-security-policy)
     (set-tool-allowlist nil)
     ,@body))

;;; =======================================================================
;;; 1. Tool definition tests
;;; =======================================================================

(test tool-definition-struct
  "tool-definition struct works"
  (let ((td (make-tool-definition :name "test"
                                   :description "A test tool"
                                   :handler #'echo-handler
                                   :category "test")))
    (is (string= "test" (tool-definition-name td)))
    (is (string= "A test tool" (tool-definition-description td)))
    (is (eq #'echo-handler (tool-definition-handler td)))
    (is (string= "test" (tool-definition-category td)))
    (is (not (tool-definition-requires-approval-p td)))))

(test tool-call-struct
  "tool-call struct works"
  (let* ((args (make-args "key" "value"))
         (tc (make-tool-call :id "call-1" :name "test" :arguments args)))
    (is (string= "call-1" (tool-call-id tc)))
    (is (string= "test" (tool-call-name tc)))
    (is (eq args (tool-call-arguments tc)))))

(test tool-result-struct
  "tool-result struct works"
  (let ((tr (make-tool-result :call-id "call-1"
                               :content "success"
                               :error-p nil)))
    (is (string= "call-1" (tool-result-call-id tr)))
    (is (string= "success" (tool-result-content tr)))
    (is (not (tool-result-error-p tr)))))

;;; =======================================================================
;;; 2. Registry tests
;;; =======================================================================

(test register-and-get-tool
  "registering and retrieving tools works"
  (with-clean-registry
    (let ((td (make-tool-definition :name "echo"
                                     :handler #'echo-handler)))
      (register-tool td)
      (is (eq td (get-tool "echo")))
      (is (null (get-tool "nonexistent"))))))

(test list-tool-names-test
  "list-tool-names returns sorted names"
  (with-clean-registry
    (register-tool (make-tool-definition :name "zebra" :handler #'echo-handler))
    (register-tool (make-tool-definition :name "alpha" :handler #'echo-handler))
    (let ((names (list-tool-names)))
      (is (= 2 (length names)))
      (is (string= "alpha" (first names)))
      (is (string= "zebra" (second names))))))

(test unregister-tool-test
  "unregistering removes tool"
  (with-clean-registry
    (register-tool (make-tool-definition :name "temp" :handler #'echo-handler))
    (is (not (null (get-tool "temp"))))
    (unregister-tool "temp")
    (is (null (get-tool "temp")))))

(test clear-registry-test
  "clear-tool-registry removes all tools"
  (with-clean-registry
    (register-tool (make-tool-definition :name "a" :handler #'echo-handler))
    (register-tool (make-tool-definition :name "b" :handler #'echo-handler))
    (clear-tool-registry)
    (is (= 0 (length (list-tool-names))))))

;;; =======================================================================
;;; 3. Dispatch tests
;;; =======================================================================

(test dispatch-basic
  "dispatch-tool-call executes handler"
  (with-clean-registry
    (register-tool (make-tool-definition :name "echo" :handler #'echo-handler))
    (let* ((call (make-tool-call :id "c1" :name "echo"
                                  :arguments (make-args "message" "hello")))
           (result (dispatch-tool-call call)))
      (is (string= "c1" (tool-result-call-id result)))
      (is (string= "hello" (tool-result-content result)))
      (is (not (tool-result-error-p result))))))

(test dispatch-unknown-tool
  "dispatch returns error for unknown tool"
  (with-clean-registry
    (let* ((call (make-tool-call :id "c2" :name "nonexistent"))
           (result (dispatch-tool-call call)))
      (is (tool-result-error-p result))
      (is (search "Unknown tool" (tool-result-content result))))))

(test dispatch-handler-error
  "dispatch catches handler errors"
  (with-clean-registry
    (register-tool (make-tool-definition :name "fail" :handler #'error-handler))
    (let* ((call (make-tool-call :id "c3" :name "fail"))
           (result (dispatch-tool-call call)))
      (is (tool-result-error-p result))
      (is (search "error" (tool-result-content result))))))

(test dispatch-no-handler
  "dispatch returns error for tool with no handler"
  (with-clean-registry
    (register-tool (make-tool-definition :name "empty"))
    (let* ((call (make-tool-call :id "c4" :name "empty"))
           (result (dispatch-tool-call call)))
      (is (tool-result-error-p result))
      (is (search "no handler" (tool-result-content result))))))

;;; =======================================================================
;;; 4. Permission & approval tests
;;; =======================================================================

(test permission-defaults
  "default permission is :allow"
  (with-clean-registry
    (register-tool (make-tool-definition :name "test" :handler #'echo-handler))
    (is (eq +permission-allow+ (check-tool-permission "test")))))

(test permission-deny
  "denied tools are rejected"
  (with-clean-registry
    (register-tool (make-tool-definition :name "dangerous" :handler #'echo-handler))
    (deny-tools "dangerous")
    (is (eq +permission-deny+ (check-tool-permission "dangerous")))
    (let* ((call (make-tool-call :id "c5" :name "dangerous"))
           (result (dispatch-tool-call call)))
      (is (tool-result-error-p result))
      (is (search "denied" (tool-result-content result))))))

(test permission-ask-with-approval
  "tools requiring approval work with approval callback"
  (with-clean-registry
    (register-tool (make-tool-definition :name "sensitive" :handler #'echo-handler))
    (require-approval-for-tools "sensitive")
    ;; Without approval fn — denied
    (let* ((call (make-tool-call :id "c6" :name "sensitive"))
           (result (dispatch-tool-call call)))
      (is (tool-result-error-p result)))
    ;; With auto-approve — allowed
    (let* ((call (make-tool-call :id "c7" :name "sensitive"))
           (result (dispatch-tool-call call :approval-fn #'auto-approve)))
      (is (not (tool-result-error-p result))))))

(test allowlist-enforcement
  "tool allowlist restricts available tools"
  (with-clean-registry
    (register-tool (make-tool-definition :name "allowed" :handler #'echo-handler))
    (register-tool (make-tool-definition :name "blocked" :handler #'echo-handler))
    (set-tool-allowlist '("allowed"))
    (is (tool-allowed-p "allowed"))
    (is (not (tool-allowed-p "blocked")))
    ;; Dispatch to blocked tool fails
    (let* ((call (make-tool-call :id "c8" :name "blocked"))
           (result (dispatch-tool-call call)))
      (is (tool-result-error-p result))
      (is (search "allowlist" (tool-result-content result))))))

;;; =======================================================================
;;; 5. File tool tests
;;; =======================================================================

(test read-tool-basic
  "read tool reads file content"
  (let ((path (make-temp-file "line1
line2
line3")))
    (unwind-protect
         (let ((result (handle-read-tool (make-args "file_path" path))))
           (is (search "line1" result))
           (is (search "line2" result))
           (is (search "line3" result)))
      (cleanup-file path))))

(test read-tool-with-offset
  "read tool respects offset parameter"
  (let ((path (make-temp-file "line1
line2
line3")))
    (unwind-protect
         (let ((result (handle-read-tool (make-args "file_path" path
                                                     "offset" 2))))
           (is (not (search "line1" result)))
           (is (search "line2" result)))
      (cleanup-file path))))

(test read-tool-missing-file
  "read tool errors on missing file"
  (signals error
    (handle-read-tool (make-args "file_path" "/tmp/nonexistent-cl-claw-xyz"))))

(test write-tool-basic
  "write tool creates files"
  (let ((path (format nil "/tmp/cl-claw-write-test-~D.txt" (get-universal-time))))
    (unwind-protect
         (progn
           (let ((result (handle-write-tool (make-args "file_path" path
                                                        "content" "test content"))))
             (is (search "Successfully" result)))
           (is (string= "test content" (uiop:read-file-string path))))
      (cleanup-file path))))

(test write-tool-overwrites
  "write tool overwrites existing files"
  (let ((path (make-temp-file "old content")))
    (unwind-protect
         (progn
           (handle-write-tool (make-args "file_path" path
                                          "content" "new content"))
           (is (string= "new content" (uiop:read-file-string path))))
      (cleanup-file path))))

(test edit-tool-basic
  "edit tool replaces text"
  (let ((path (make-temp-file "hello world foo bar")))
    (unwind-protect
         (progn
           (let ((result (handle-edit-tool (make-args "file_path" path
                                                       "old_string" "world"
                                                       "new_string" "earth"))))
             (is (search "Successfully" result)))
           (is (string= "hello earth foo bar" (uiop:read-file-string path))))
      (cleanup-file path))))

(test edit-tool-not-found
  "edit tool errors when text not found"
  (let ((path (make-temp-file "hello world")))
    (unwind-protect
         (signals error
           (handle-edit-tool (make-args "file_path" path
                                         "old_string" "nonexistent"
                                         "new_string" "replacement")))
      (cleanup-file path))))

(test edit-tool-duplicate
  "edit tool errors on duplicate matches"
  (let ((path (make-temp-file "hello hello hello")))
    (unwind-protect
         (signals error
           (handle-edit-tool (make-args "file_path" path
                                         "old_string" "hello"
                                         "new_string" "bye")))
      (cleanup-file path))))

;;; =======================================================================
;;; 6. Exec tool tests
;;; =======================================================================

(test exec-tool-basic
  "exec tool runs commands"
  (let ((result (handle-exec-tool (make-args "command" "echo 'hello from exec'"))))
    (is (search "hello from exec" result))))

(test exec-tool-exit-code
  "exec tool reports non-zero exit codes"
  (let ((result (handle-exec-tool (make-args "command" "exit 42"))))
    (is (search "42" result))))

(test exec-tool-workdir
  "exec tool respects workdir"
  (let ((result (handle-exec-tool (make-args "command" "pwd"
                                              "workdir" "/tmp"))))
    (is (search "/tmp" result))))

;;; =======================================================================
;;; 7. Browser tool tests
;;; =======================================================================

(test browser-tool-status
  "browser tool handles status action"
  (let ((result (handle-browser-tool (make-args "action" "status"))))
    (is (search "not-connected" result))))

(test browser-tool-unknown-action
  "browser tool rejects unknown actions"
  (signals error
    (handle-browser-tool (make-args "action" "unknown-action"))))

(test browser-tool-navigate
  "browser tool handles navigate with URL"
  (let ((result (handle-browser-tool (make-args "action" "navigate"
                                                 "url" "https://example.com"))))
    (is (search "example.com" result))))

;;; =======================================================================
;;; 8. Initialization tests
;;; =======================================================================

(test initialize-tool-system-test
  "initialize-tool-system registers all builtins"
  (initialize-tool-system)
  (let ((names (list-tool-names)))
    (is (member "read" names :test #'string=))
    (is (member "write" names :test #'string=))
    (is (member "edit" names :test #'string=))
    (is (member "exec" names :test #'string=))
    (is (member "process" names :test #'string=))
    (is (member "web_fetch" names :test #'string=))
    (is (member "web_search" names :test #'string=))
    (is (member "browser" names :test #'string=))))

(test initialize-full-dispatch
  "full dispatch works after initialization"
  (initialize-tool-system)
  (let* ((call (make-tool-call :id "init-test" :name "exec"
                                :arguments (make-args "command" "echo ok")))
         (result (dispatch-tool-call call)))
    (is (not (tool-result-error-p result)))
    (is (search "ok" (tool-result-content result)))))
