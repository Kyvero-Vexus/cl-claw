;;;; file-ops.lisp — Read/Write/Edit tools — file operations
;;;;
;;;; Implements the read, write, and edit tools matching OpenClaw's
;;;; file operation semantics.

(defpackage :cl-claw.tools.file-ops
  (:use :cl)
  (:import-from :cl-claw.tools.types
                :tool-definition
                :make-tool-definition)
  (:import-from :cl-claw.tools.dispatch
                :register-tool)
  (:export
   ;; Tool handlers
   :handle-read-tool
   :handle-write-tool
   :handle-edit-tool

   ;; Registration
   :register-file-tools

   ;; Constants
   :+max-read-lines+
   :+max-read-bytes+))

(in-package :cl-claw.tools.file-ops)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Constants matching OpenClaw defaults
;;; -----------------------------------------------------------------------

(defconstant +max-read-lines+ 2000
  "Maximum number of lines to read in a single read operation.")

(defconstant +max-read-bytes+ (* 50 1024)
  "Maximum bytes to read (50 KB).")

;;; -----------------------------------------------------------------------
;;; Path resolution & safety
;;; -----------------------------------------------------------------------

(defvar *workspace-root* nil
  "Current workspace root directory. Tools resolve relative paths against this.")

(declaim (ftype (function (string) string) resolve-tool-path))
(defun resolve-tool-path (path)
  "Resolve a path for tool operations.
Relative paths are resolved against *workspace-root*."
  (declare (type string path))
  (let ((trimmed (string-trim '(#\Space #\Tab) path)))
    (declare (type string trimmed))
    (when (string= "" trimmed)
      (error "File path cannot be empty"))
    (if (and *workspace-root*
             (not (uiop:absolute-pathname-p trimmed)))
        (namestring (merge-pathnames trimmed
                                     (uiop:ensure-directory-pathname *workspace-root*)))
        trimmed)))

(declaim (ftype (function (string) boolean) path-within-workspace-p))
(defun path-within-workspace-p (path)
  "Check if a path is within the workspace root (basic containment check)."
  (declare (type string path))
  (if (null *workspace-root*)
      t  ; No workspace root = allow everything
      (let* ((resolved (truename-safe path))
             (root (truename-safe *workspace-root*)))
        (declare (type (or string null) resolved root))
        (and resolved root
             (>= (length resolved) (length root))
             (string= root (subseq resolved 0 (length root)))))))

(defun truename-safe (path)
  "Get truename or return nil on error."
  (handler-case
      (namestring (truename path))
    (error () nil)))

;;; -----------------------------------------------------------------------
;;; Read tool
;;; -----------------------------------------------------------------------

(declaim (ftype (function (hash-table) string) handle-read-tool))
(defun handle-read-tool (args)
  "Handle a read tool call.
Arguments:
  file_path/path: path to read
  offset: 1-indexed line number to start from (optional)
  limit: max lines to read (optional)"
  (declare (type hash-table args))
  (let* ((path-arg (or (gethash "file_path" args)
                       (gethash "path" args)
                       (error "read tool requires file_path or path")))
         (path (resolve-tool-path path-arg))
         (offset (or (gethash "offset" args) 1))
         (limit (or (gethash "limit" args) +max-read-lines+)))
    (declare (type string path)
             (type fixnum offset limit))
    (unless (uiop:file-exists-p path)
      (error "File not found: ~A" path-arg))
    (with-open-file (stream path :direction :input
                                 :external-format :utf-8)
      (let ((lines '())
            (line-num 0)
            (bytes-read 0)
            (lines-read 0))
        (declare (type fixnum line-num bytes-read lines-read))
        (loop for line = (read-line stream nil nil)
              while line
              do (incf line-num)
                 (when (>= line-num offset)
                   (let ((line-bytes (+ (length line) 1)))
                     (declare (type fixnum line-bytes))
                     (when (or (>= lines-read limit)
                               (> (+ bytes-read line-bytes) +max-read-bytes+))
                       (push (format nil "~%[~D more lines in file. Use offset=~D to continue.]"
                                     (- (file-length stream) bytes-read)
                                     (+ line-num 1))
                             lines)
                       (return))
                     (push line lines)
                     (incf bytes-read line-bytes)
                     (incf lines-read))))
        (format nil "~{~A~^~%~}" (nreverse lines))))))

;;; -----------------------------------------------------------------------
;;; Write tool
;;; -----------------------------------------------------------------------

(declaim (ftype (function (hash-table) string) handle-write-tool))
(defun handle-write-tool (args)
  "Handle a write tool call.
Arguments:
  file_path/path: path to write
  content: content to write"
  (declare (type hash-table args))
  (let* ((path-arg (or (gethash "file_path" args)
                       (gethash "path" args)
                       (error "write tool requires file_path or path")))
         (content (or (gethash "content" args)
                      (error "write tool requires content")))
         (path (resolve-tool-path path-arg)))
    (declare (type string path content))
    ;; Ensure parent directories exist
    (ensure-directories-exist (pathname path))
    (with-open-file (stream path :direction :output
                                 :if-exists :supersede
                                 :if-does-not-exist :create
                                 :external-format :utf-8)
      (write-string content stream))
    (format nil "Successfully wrote ~D bytes to ~A" (length content) path-arg)))

;;; -----------------------------------------------------------------------
;;; Edit tool
;;; -----------------------------------------------------------------------

(declaim (ftype (function (hash-table) string) handle-edit-tool))
(defun handle-edit-tool (args)
  "Handle an edit tool call (find-and-replace).
Arguments:
  file_path/path: path to edit
  old_string/oldText: exact text to find
  new_string/newText: replacement text"
  (declare (type hash-table args))
  (let* ((path-arg (or (gethash "file_path" args)
                       (gethash "path" args)
                       (error "edit tool requires file_path or path")))
         (old-text (or (gethash "old_string" args)
                       (gethash "oldText" args)
                       (error "edit tool requires old_string or oldText")))
         (new-text (or (gethash "new_string" args)
                       (gethash "newText" args)
                       (error "edit tool requires new_string or newText")))
         (path (resolve-tool-path path-arg)))
    (declare (type string path old-text new-text))
    (unless (uiop:file-exists-p path)
      (error "File not found: ~A" path-arg))
    (let ((content (uiop:read-file-string path)))
      (declare (type string content))
      (let ((pos (search old-text content)))
        (unless pos
          (error "old_string not found in ~A. Make sure it matches exactly (including whitespace)."
                 path-arg))
        ;; Check for multiple occurrences
        (let ((second-pos (search old-text content :start2 (+ pos (length old-text)))))
          (when second-pos
            (error "old_string found multiple times in ~A. Make the search string more specific."
                   path-arg)))
        ;; Perform replacement
        (let ((new-content (concatenate 'string
                                        (subseq content 0 pos)
                                        new-text
                                        (subseq content (+ pos (length old-text))))))
          (declare (type string new-content))
          (with-open-file (stream path :direction :output
                                       :if-exists :supersede
                                       :external-format :utf-8)
            (write-string new-content stream))
          (format nil "Successfully replaced text in ~A." path-arg))))))

;;; -----------------------------------------------------------------------
;;; Tool registration
;;; -----------------------------------------------------------------------

(defun register-file-tools ()
  "Register the read, write, and edit tools in the global registry."
  (register-tool (make-tool-definition
                  :name "read"
                  :description "Read the contents of a file. Supports text files and images. Output is truncated to 2000 lines or 50KB."
                  :handler #'handle-read-tool
                  :category "file"))
  (register-tool (make-tool-definition
                  :name "write"
                  :description "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories."
                  :handler #'handle-write-tool
                  :category "file"))
  (register-tool (make-tool-definition
                  :name "edit"
                  :description "Edit a file by replacing exact text. The oldText must match exactly (including whitespace)."
                  :handler #'handle-edit-tool
                  :category "file"))
  (values))
