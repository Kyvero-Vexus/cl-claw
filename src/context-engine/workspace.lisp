;;;; workspace.lisp — Workspace file injection
;;;;
;;;; Loads workspace context files (SOUL.md, AGENTS.md, TOOLS.md, etc.)
;;;; and formats them for injection into the system prompt.

(defpackage :cl-claw.context-engine.workspace
  (:use :cl)
  (:import-from :cl-claw.context-engine.types
                :context-file
                :make-context-file
                :context-file-path
                :context-file-content)
  (:export
   ;; Constants
   :+default-workspace-files+
   :+max-workspace-file-bytes+

   ;; File loading
   :read-workspace-file
   :load-workspace-context-files
   :strip-front-matter

   ;; Prompt formatting
   :format-context-files-section))

(in-package :cl-claw.context-engine.workspace)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Constants — matching OpenClaw workspace file conventions
;;; -----------------------------------------------------------------------

(defparameter +default-workspace-files+
  '("AGENTS.md" "SOUL.md" "TOOLS.md" "IDENTITY.md" "USER.md")
  "Default workspace files to inject, in order.")

(defconstant +max-workspace-file-bytes+ (* 2 1024 1024)
  "Maximum size for a workspace file (2 MB).")

;;; -----------------------------------------------------------------------
;;; Front-matter stripping
;;; -----------------------------------------------------------------------

(declaim (ftype (function (string) string) strip-front-matter))
(defun strip-front-matter (content)
  "Strip YAML front matter (---...\n---) from the beginning of content."
  (declare (type string content))
  (if (not (and (>= (length content) 3)
                (string= "---" (subseq content 0 3))))
      content
      (let ((end-pos (search (format nil "~%---") content :start2 3)))
        (if (null end-pos)
            content
            (let* ((start (+ end-pos 4))
                   (trimmed (subseq content start)))
              (declare (type string trimmed))
              ;; Strip leading whitespace after front matter
              (string-left-trim '(#\Space #\Tab #\Newline #\Return) trimmed))))))

;;; -----------------------------------------------------------------------
;;; File reading
;;; -----------------------------------------------------------------------

(declaim (ftype (function (string string) (or context-file null))
                read-workspace-file))
(defun read-workspace-file (workspace-dir filename)
  "Read a single workspace file. Returns a context-file or nil if not found/too large."
  (declare (type string workspace-dir filename))
  (let ((path (merge-pathnames filename (uiop:ensure-directory-pathname workspace-dir))))
    (handler-case
        (when (uiop:file-exists-p path)
          (let ((size (with-open-file (s path :direction :input)
                        (file-length s))))
            (declare (type (or fixnum null) size))
            (when (and size (<= size +max-workspace-file-bytes+))
              (let ((content (uiop:read-file-string path)))
                (declare (type string content))
                (make-context-file :path filename
                                   :content (strip-front-matter content))))))
      (error () nil))))

(declaim (ftype (function (string &key (:filenames list)) list)
                load-workspace-context-files))
(defun load-workspace-context-files (workspace-dir &key (filenames +default-workspace-files+))
  "Load all workspace context files from WORKSPACE-DIR.
Returns a list of context-file structs for files that exist and are readable."
  (declare (type string workspace-dir)
           (type list filenames))
  (the list
       (loop for filename in filenames
             for cf = (read-workspace-file workspace-dir filename)
             when cf collect cf)))

;;; -----------------------------------------------------------------------
;;; Prompt formatting — format loaded context files into prompt text
;;; -----------------------------------------------------------------------

(declaim (ftype (function (list) string) format-context-files-section))
(defun format-context-files-section (context-files)
  "Format a list of context-file structs into the system prompt section.
Produces the '# Project Context' block matching OpenClaw's format."
  (declare (type list context-files))
  (if (null context-files)
      ""
      (let ((lines '())
            (has-soul-p (some (lambda (cf)
                                (declare (type context-file cf))
                                (string-equal "soul.md"
                                              (string-downcase
                                               (file-namestring
                                                (context-file-path cf)))))
                              context-files)))
        (push "# Project Context" lines)
        (push "" lines)
        (push "The following project context files have been loaded:" lines)
        (when has-soul-p
          (push "If SOUL.md is present, embody its persona and tone. Avoid stiff, generic replies; follow its guidance unless higher-priority instructions override it."
                lines))
        (push "" lines)
        (dolist (cf context-files)
          (push (format nil "## ~A" (context-file-path cf)) lines)
          (push "" lines)
          (push (context-file-content cf) lines)
          (push "" lines))
        (format nil "~{~A~^~%~}" (nreverse lines)))))
