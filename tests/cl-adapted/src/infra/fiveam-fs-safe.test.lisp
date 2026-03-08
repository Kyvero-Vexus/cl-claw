;;;; fiveam-fs-safe.test.lisp - FiveAM tests for fs-safe module

(defpackage :cl-claw.infra.fs-safe.test
  (:use :cl :fiveam))
(in-package :cl-claw.infra.fs-safe.test)

(def-suite fs-safe-suite
  :description "Tests for the fs-safe module")
(in-suite fs-safe-suite)

;;; Helpers

(defun make-temp-dir ()
  "Create and return a temporary directory path."
  (let ((path (uiop:native-namestring
               (merge-pathnames (format nil "cl-claw-fs-safe-test-~a/" (random 999999))
                                (uiop:temporary-directory)))))
    (uiop:ensure-all-directories-exist (list path))
    path))

(defun cleanup-dir (path)
  "Remove temporary test directory."
  (ignore-errors
    (uiop:delete-directory-tree (uiop:ensure-directory-pathname path) :validate t)))

(defmacro with-temp-dir ((var) &body body)
  "Execute BODY with a temporary directory bound to VAR, cleaning up afterward."
  `(let ((,var (make-temp-dir)))
     (unwind-protect (progn ,@body)
       (cleanup-dir ,var))))

;;; expand-home-prefix tests

(test expand-home-prefix-keeps-non-tilde-paths
  "expand-home-prefix returns non-tilde paths unchanged"
  (let ((path "/usr/local/bin/something"))
    (is (string= path (cl-claw.infra.fs-safe:expand-home-prefix path :home "/home/user")))))

(test expand-home-prefix-expands-tilde-slash
  "expand-home-prefix expands ~/path to home/path"
  (let ((result (cl-claw.infra.fs-safe:expand-home-prefix "~/docs/file.txt" :home "/home/user")))
    (is (search "/home/user" result))
    (is (search "docs/file.txt" result))))

(test expand-home-prefix-expands-bare-tilde
  "expand-home-prefix expands bare ~ to home directory"
  (let ((result (cl-claw.infra.fs-safe:expand-home-prefix "~" :home "/home/user")))
    (is (string= "/home/user" result))))

;;; read-local-file-safely tests

(test reads-a-local-file-safely
  "Reads a local file safely"
  (with-temp-dir (root)
    (let ((file-path (merge-pathnames "test.txt" (uiop:ensure-directory-pathname root))))
      (with-open-file (f file-path :direction :output :if-exists :supersede)
        (write-string "hello world" f))
      (let ((content (cl-claw.infra.fs-safe:read-local-file-safely
                      (uiop:native-namestring file-path))))
        (is (string= "hello world" content))))))

(test rejects-directories
  "read-local-file-safely rejects directory paths"
  (with-temp-dir (root)
    (handler-case
        (progn
          (cl-claw.infra.fs-safe:read-local-file-safely root)
          (fail "Should have signaled an error"))
      (cl-claw.infra.fs-safe:safe-open-error (e)
        (is (eq :is-directory (cl-claw.infra.fs-safe:safe-open-error-code e)))))))

(test enforces-max-bytes
  "read-local-file-safely enforces max-bytes limit"
  (with-temp-dir (root)
    (let ((file-path (merge-pathnames "big.txt" (uiop:ensure-directory-pathname root))))
      (with-open-file (f file-path :direction :output :if-exists :supersede)
        (write-string "0123456789" f))
      (handler-case
          (progn
            (cl-claw.infra.fs-safe:read-local-file-safely
             (uiop:native-namestring file-path) :max-bytes 5)
            (fail "Should have signaled an error"))
        (cl-claw.infra.fs-safe:safe-open-error (e)
          (is (eq :max-bytes-exceeded (cl-claw.infra.fs-safe:safe-open-error-code e))))))))

(test returns-not-found-for-missing-files
  "Signals not-found for missing files"
  (handler-case
      (progn
        (cl-claw.infra.fs-safe:read-local-file-safely "/tmp/cl-claw-nonexistent-12345.txt")
        (fail "Should have signaled an error"))
    (cl-claw.infra.fs-safe:safe-open-error (e)
      (is (eq :not-found (cl-claw.infra.fs-safe:safe-open-error-code e))))))

;;; read-file-within-root tests

(test reads-a-file-within-root
  "Reads a file that is within the root directory"
  (with-temp-dir (root)
    (let ((file-path (merge-pathnames "data.txt" (uiop:ensure-directory-pathname root))))
      (with-open-file (f file-path :direction :output :if-exists :supersede)
        (write-string "root content" f))
      (let ((content (cl-claw.infra.fs-safe:read-file-within-root root "data.txt")))
        (is (string= "root content" content))))))

(test blocks-traversal-outside-root
  "Blocks path traversal outside the root directory"
  (with-temp-dir (root)
    (handler-case
        (progn
          (cl-claw.infra.fs-safe:read-file-within-root root "../../etc/passwd")
          (fail "Should have signaled an error"))
      (cl-claw.infra.fs-safe:safe-open-error (e)
        (is (eq :outside-workspace (cl-claw.infra.fs-safe:safe-open-error-code e)))))))

(test rejects-directory-path-within-root
  "Rejects directory path within root (EISDIR case)"
  (with-temp-dir (root)
    (let ((subdir (uiop:native-namestring
                   (merge-pathnames "subdir/" (uiop:ensure-directory-pathname root)))))
      (uiop:ensure-all-directories-exist (list subdir))
      (handler-case
          (progn
            (cl-claw.infra.fs-safe:read-file-within-root root "subdir")
            (fail "Should have signaled an error"))
        (cl-claw.infra.fs-safe:safe-open-error (e)
          (is (member (cl-claw.infra.fs-safe:safe-open-error-code e)
                      '(:is-directory :not-found))))))))

;;; read-path-within-root tests

(test reads-absolute-path-within-root
  "Reads an absolute path that resolves within the root"
  (with-temp-dir (root)
    (let* ((file-path (merge-pathnames "abs-test.txt" (uiop:ensure-directory-pathname root)))
           (abs-path (uiop:native-namestring file-path)))
      (with-open-file (f file-path :direction :output :if-exists :supersede)
        (write-string "absolute" f))
      (let ((content (cl-claw.infra.fs-safe:read-path-within-root root abs-path)))
        (is (string= "absolute" content))))))

;;; create-root-scoped-read-file tests

(test creates-root-scoped-read-callback
  "create-root-scoped-read-file returns a callable that reads within root"
  (with-temp-dir (root)
    (let* ((file-path (merge-pathnames "scope-test.txt" (uiop:ensure-directory-pathname root)))
           (reader (cl-claw.infra.fs-safe:create-root-scoped-read-file root)))
      (with-open-file (f file-path :direction :output :if-exists :supersede)
        (write-string "scoped" f))
      (is (functionp reader))
      (is (string= "scoped" (funcall reader "scope-test.txt"))))))

;;; write-file-within-root tests

(test writes-a-file-within-root-safely
  "Writes a file within the root directory safely"
  (with-temp-dir (root)
    (cl-claw.infra.fs-safe:write-file-within-root root "output.txt" "written content")
    (let ((content (cl-claw.infra.fs-safe:read-file-within-root root "output.txt")))
      (is (string= "written content" content)))))

(test rejects-write-traversal-outside-root
  "Rejects write path traversal outside root"
  (with-temp-dir (root)
    (handler-case
        (progn
          (cl-claw.infra.fs-safe:write-file-within-root root "../../tmp/escape.txt" "x")
          (fail "Should have signaled an error"))
      (cl-claw.infra.fs-safe:safe-open-error (e)
        (is (eq :outside-workspace (cl-claw.infra.fs-safe:safe-open-error-code e)))))))

;;; copy-file-within-root tests

(test copies-a-file-within-root-safely
  "Copies a file within the root directory"
  (with-temp-dir (root)
    (cl-claw.infra.fs-safe:write-file-within-root root "source.txt" "copy me")
    (cl-claw.infra.fs-safe:copy-file-within-root root "source.txt" "dest.txt")
    (let ((content (cl-claw.infra.fs-safe:read-file-within-root root "dest.txt")))
      (is (string= "copy me" content)))))

(test enforces-max-bytes-when-copying-into-root
  "Enforces max-bytes when copying a file"
  (with-temp-dir (root)
    (cl-claw.infra.fs-safe:write-file-within-root root "big.txt" "0123456789")
    (handler-case
        (progn
          (cl-claw.infra.fs-safe:copy-file-within-root root "big.txt" "small.txt" :max-bytes 5)
          (fail "Should have signaled an error"))
      (cl-claw.infra.fs-safe:safe-open-error (e)
        (is (eq :max-bytes-exceeded (cl-claw.infra.fs-safe:safe-open-error-code e)))))))

;;; outside-workspace-error-p tests

(test outside-workspace-error-p-returns-true-for-outside-errors
  "outside-workspace-error-p correctly identifies outside-workspace errors"
  (with-temp-dir (root)
    (handler-case
        (cl-claw.infra.fs-safe:read-file-within-root root "../../escape.txt")
      (cl-claw.infra.fs-safe:safe-open-error (e)
        (is-true (cl-claw.infra.fs-safe:outside-workspace-error-p e))))))

(test outside-workspace-error-p-returns-false-for-other-errors
  "outside-workspace-error-p returns NIL for non-outside errors"
  (let ((err (make-condition 'cl-claw.infra.fs-safe:safe-open-error
                             :code :not-found
                             :path "x"
                             :message "not found")))
    (is-false (cl-claw.infra.fs-safe:outside-workspace-error-p err))))
