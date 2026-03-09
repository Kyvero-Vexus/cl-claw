;;;; fs-safe.lisp - Safe filesystem operations for cl-claw
;;;;
;;;; Provides path-traversal-safe file operations that enforce containment
;;;; within a root directory. All operations verify paths resolve inside root
;;;; before acting, preventing directory traversal attacks.

(defpackage :cl-claw.infra.fs-safe
  (:use :cl)
  (:export :safe-open-error
           :safe-open-error-code
           :safe-open-error-path
           :read-local-file-safely
           :read-file-within-root
           :read-path-within-root
           :create-root-scoped-read-file
           :write-file-within-root
           :copy-file-within-root
           :write-file-from-path-within-root
           :expand-home-prefix
           :outside-workspace-error-p))
(in-package :cl-claw.infra.fs-safe)

(declaim (optimize (safety 3) (debug 3)))

;;; Conditions

(define-condition safe-open-error (error)
  ((code :initarg :code :reader safe-open-error-code
         :documentation "Error code keyword: :outside-workspace, :not-found, :is-directory, :max-bytes-exceeded")
   (path :initarg :path :reader safe-open-error-path
         :documentation "The path that caused the error")
   (message :initarg :message :reader safe-open-error-message))
  (:report (lambda (c s)
             (format s "Safe-open error ~a for path ~s: ~a"
                     (safe-open-error-code c)
                     (safe-open-error-path c)
                     (slot-value c 'message))))
  (:documentation "Error signaled when a safe filesystem operation fails."))

(declaim (ftype (function (t) boolean) outside-workspace-error-p))
(defun outside-workspace-error-p (condition)
  "Return T if CONDITION is a safe-open-error with :outside-workspace code."
  (and (typep condition 'safe-open-error)
       (eq (safe-open-error-code condition) :outside-workspace)))

;;; Path utilities

(declaim (ftype (function (string &key (:home (or null string))) string) expand-home-prefix))
(defun expand-home-prefix (path &key home)
  "Expand a ~/... path using HOME (defaults to HOME environment variable).
Non-tilde paths are returned unchanged."
  (declare (type string path))
  (let ((home-dir (or home (uiop:getenv "HOME") "~")))
    (cond
      ((string= path "~")
       home-dir)
      ((and (>= (length path) 2)
            (char= (char path 0) #\~)
            (char= (char path 1) #\/))
       (uiop:native-namestring
        (merge-pathnames (subseq path 2)
                         (uiop:ensure-directory-pathname home-dir))))
      (t path))))

(declaim (ftype (function (t) (or null string)) resolve-canonical))
(defun resolve-canonical (path)
  "Resolve PATH to its canonical form, following symlinks.
Returns the resolved path string, or NIL if resolution fails."
  (handler-case
      (uiop:native-namestring (truename path))
    (error () nil)))

(declaim (ftype (function (t t) boolean) path-within-root-p))
(defun path-within-root-p (path root)
  "Return T if PATH (canonical) is within ROOT (canonical)."
  (let* ((root-str (uiop:native-namestring (uiop:ensure-directory-pathname root)))
         (path-str (if (uiop:directory-pathname-p path) path (uiop:native-namestring path))))
    (and (>= (length path-str) (length root-str))
         (string= (subseq path-str 0 (length root-str)) root-str))))

(declaim (ftype (function (t t) string) ensure-within-root))
(defun ensure-within-root (path root)
  "Verify PATH is within ROOT after resolving symlinks.
Signals SAFE-OPEN-ERROR with :outside-workspace if traversal is detected."
  (let* ((path-str (if (pathnamep path) (uiop:native-namestring path) path))
         ;; Try to resolve; if path doesn't exist yet, resolve parent
         (canonical
           (or (resolve-canonical path-str)
               (let* ((pn (pathname path-str))
                      (dir (directory-namestring pn))
                      (name (file-namestring pn))
                      (canon-dir (resolve-canonical dir)))
                 (when canon-dir
                   (uiop:native-namestring
                    (merge-pathnames name (uiop:ensure-directory-pathname canon-dir)))))))
         (canonical-root
           (or (resolve-canonical root)
               (uiop:native-namestring (uiop:ensure-directory-pathname root)))))
    (unless canonical
      (error 'safe-open-error
             :code :not-found
             :path path-str
             :message (format nil "Path does not exist: ~a" path-str)))
    (unless (path-within-root-p canonical canonical-root)
      (error 'safe-open-error
             :code :outside-workspace
             :path path-str
             :message (format nil "Path ~a is outside root ~a" canonical canonical-root)))
    canonical))

;;; File reading

(declaim (ftype (function (string &key (:max-bytes (or null integer))) string) read-local-file-safely))
(defun read-local-file-safely (path &key (max-bytes nil))
  "Read a local file safely with optional MAX-BYTES limit.
Signals SAFE-OPEN-ERROR if path is a directory or exceeds max-bytes.
Returns the file content as a string."
  (declare (type string path))
  (let ((pn (pathname path)))
    ;; Check for directory
    (when (uiop:directory-exists-p pn)
      (error 'safe-open-error
             :code :is-directory
             :path path
             :message (format nil "Path is a directory: ~a" path)))
    ;; Check existence
    (unless (uiop:file-exists-p pn)
      (error 'safe-open-error
             :code :not-found
             :path path
             :message (format nil "File not found: ~a" path)))
    ;; Read content
    (let ((content (uiop:read-file-string pn)))
      ;; Enforce max-bytes
      (when (and max-bytes (> (length content) max-bytes))
        (error 'safe-open-error
               :code :max-bytes-exceeded
               :path path
               :message (format nil "File ~a exceeds max-bytes limit of ~a" path max-bytes)))
      content)))

(declaim (ftype (function (string string &key (:max-bytes (or null integer))) string) read-file-within-root))
(defun read-file-within-root (root relative-path &key (max-bytes nil))
  "Read a file at RELATIVE-PATH within ROOT directory safely.
Prevents directory traversal outside ROOT.
Returns file content as a string."
  (declare (type string root relative-path))
  (let* ((full-path (uiop:native-namestring
                     (merge-pathnames relative-path
                                      (uiop:ensure-directory-pathname root))))
         (canonical (ensure-within-root full-path root)))
    ;; Check for directory
    (when (uiop:directory-exists-p canonical)
      (error 'safe-open-error
             :code :is-directory
             :path relative-path
             :message (format nil "Path is a directory: ~a" relative-path)))
    (read-local-file-safely canonical :max-bytes max-bytes)))

(declaim (ftype (function (string string &key (:max-bytes (or null integer))) string) read-path-within-root))
(defun read-path-within-root (root absolute-path &key (max-bytes nil))
  "Read a file at ABSOLUTE-PATH, verifying it is within ROOT.
Returns file content as a string."
  (declare (type string root absolute-path))
  (let ((canonical (ensure-within-root absolute-path root)))
    (when (uiop:directory-exists-p canonical)
      (error 'safe-open-error
             :code :is-directory
             :path absolute-path
             :message (format nil "Path is a directory: ~a" absolute-path)))
    (read-local-file-safely canonical :max-bytes max-bytes)))

(declaim (ftype (function (string) function) create-root-scoped-read-file))
(defun create-root-scoped-read-file (root)
  "Return a closure that reads files within ROOT safely.
The closure accepts a relative path and optional max-bytes keyword."
  (declare (type string root))
  (lambda (relative-path &key max-bytes)
    (read-file-within-root root relative-path :max-bytes max-bytes)))

;;; File writing

(declaim (ftype (function (string string string &key (:encoding t)) string) write-file-within-root))
(defun write-file-within-root (root relative-path content &key (encoding :utf-8))
  "Write CONTENT to RELATIVE-PATH within ROOT atomically.
Uses a temporary file and rename for atomicity.
Signals SAFE-OPEN-ERROR if path traversal is detected."
  (declare (type string root relative-path content)
           (ignore encoding))
  (let* ((full-path (uiop:native-namestring
                     (merge-pathnames relative-path
                                      (uiop:ensure-directory-pathname root))))
         (canonical-root (or (resolve-canonical root)
                             (uiop:native-namestring (uiop:ensure-directory-pathname root)))))
    ;; Verify parent directory is within root
    (let* ((parent (directory-namestring full-path))
           (canonical-parent
             (or (resolve-canonical parent)
                 (uiop:native-namestring (uiop:ensure-directory-pathname parent)))))
      (when canonical-parent
        (unless (path-within-root-p canonical-parent canonical-root)
          (error 'safe-open-error
                 :code :outside-workspace
                 :path relative-path
                 :message (format nil "Write path ~a is outside root ~a"
                                  relative-path root)))))
    ;; Ensure parent directories exist
    (uiop:ensure-all-directories-exist
     (list (uiop:ensure-directory-pathname (directory-namestring full-path))))
    ;; Write atomically via temp file
    (let ((temp-path (format nil "~a.tmp.~a" full-path (random 999999))))
      (handler-case
          (progn
            (uiop:with-output-file (out temp-path :if-exists :supersede)
              (write-string content out))
            ;; Verify temp file is within root before rename
            (let ((canonical-temp (resolve-canonical temp-path)))
              (when canonical-temp
                (unless (path-within-root-p canonical-temp canonical-root)
                  (delete-file temp-path)
                  (error 'safe-open-error
                         :code :outside-workspace
                         :path relative-path
                         :message "Atomic write target escaped root"))))
            (rename-file temp-path full-path)
            full-path)
        (error (e)
          (ignore-errors (delete-file temp-path))
          (error e))))))

(declaim (ftype (function (string string string &key (:max-bytes (or null integer))) string) copy-file-within-root))
(defun copy-file-within-root (root source-relative dest-relative &key (max-bytes nil))
  "Copy SOURCE-RELATIVE to DEST-RELATIVE within ROOT safely.
Both paths must resolve within ROOT."
  (declare (type string root source-relative dest-relative))
  (let ((content (read-file-within-root root source-relative :max-bytes max-bytes)))
    (write-file-within-root root dest-relative content)))

(declaim (ftype (function (string string string &key (:max-bytes (or null integer))) string) write-file-from-path-within-root))
(defun write-file-from-path-within-root (root relative-dest source-absolute &key (max-bytes nil))
  "Write file from SOURCE-ABSOLUTE to RELATIVE-DEST within ROOT.
SOURCE-ABSOLUTE must be a readable file (not necessarily within root).
RELATIVE-DEST must resolve within ROOT."
  (declare (type string root relative-dest source-absolute))
  (let ((content (read-local-file-safely source-absolute :max-bytes max-bytes)))
    (write-file-within-root root relative-dest content)))

;;; Safe file open (low-level)

(declaim (ftype (function (string string &key (:direction keyword) (:if-does-not-exist keyword)) stream) open-file-within-root))
(defun open-file-within-root (root relative-path &key (direction :input) (if-does-not-exist :error))
  "Open a file at RELATIVE-PATH within ROOT safely.
Returns an open stream. Caller must close it."
  (declare (type string root relative-path))
  (let* ((full-path (uiop:native-namestring
                     (merge-pathnames relative-path
                                      (uiop:ensure-directory-pathname root))))
         (canonical (ensure-within-root full-path root)))
    (open canonical :direction direction :if-does-not-exist if-does-not-exist)))
