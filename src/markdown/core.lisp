;;;; core.lisp — minimal markdown IR and platform renderers

(defpackage :cl-claw.markdown
  (:use :cl)
  (:export
   :parse-markdown-to-ir
   :render-ir
   :render-for-whatsapp
   :contains-markdown-table-p
   :normalize-markdown-for-whatsapp))

(in-package :cl-claw.markdown)

(declaim (optimize (safety 3) (debug 3)))

(declaim (ftype (function (string) list) split-lines))
(defun split-lines (text)
  (declare (type string text))
  (uiop:split-string text :separator '(#\Newline)))

(declaim (ftype (function (string) string) trim-line))
(defun trim-line (line)
  (declare (type string line))
  (string-trim '(#\Space #\Tab #\Return) line))

(declaim (ftype (function (string) list) parse-markdown-to-ir))
(defun parse-markdown-to-ir (markdown)
  (declare (type string markdown))
  (let ((nodes nil)
        (in-code nil)
        (code-lines nil))
    (declare (type list nodes code-lines)
             (type boolean in-code))
    (dolist (raw (split-lines markdown))
      (let ((line (trim-line raw)))
        (declare (type string line))
        (cond
          ((string= line "```")
           (if in-code
               (progn
                 (push (list :type :code :text (format nil "~{~a~^~%~}" (nreverse code-lines))) nodes)
                 (setf in-code nil
                       code-lines nil))
               (setf in-code t)))
          (in-code
           (push raw code-lines))
          ((or (string= line "") (string= line "\n"))
           (push (list :type :blank :text "") nodes))
          ((and (> (length line) 1)
                (char= (char line 0) #\#)
                (char= (char line 1) #\Space))
           (push (list :type :heading :level 1 :text (subseq line 2)) nodes))
          ((and (> (length line) 1)
                (char= (char line 0) #\-)
                (char= (char line 1) #\Space))
           (push (list :type :bullet :text (subseq line 2)) nodes))
          (t
           (push (list :type :paragraph :text line) nodes)))))
    (when in-code
      (push (list :type :code :text (format nil "~{~a~^~%~}" (nreverse code-lines))) nodes))
    (nreverse nodes)))

(declaim (ftype (function (list &key (:platform keyword)) string) render-ir))
(defun render-ir (ir &key (platform :generic))
  (declare (type list ir)
           (type keyword platform))
  (with-output-to-string (out)
    (dolist (node ir)
      (let ((type (getf node :type))
            (text (or (getf node :text) "")))
        (declare (type t type)
                 (type string text))
        (ecase type
          (:blank
           (terpri out))
          (:heading
           (write-string (if (eq platform :whatsapp)
                             (format nil "*~a*" text)
                             (format nil "# ~a" text))
                         out)
           (terpri out))
          (:bullet
           (write-string (format nil "- ~a" text) out)
           (terpri out))
          (:paragraph
           (write-string text out)
           (terpri out))
          (:code
           (write-string "```" out)
           (terpri out)
           (write-string text out)
           (terpri out)
           (write-string "```" out)
           (terpri out)))))))

(declaim (ftype (function (string) boolean) contains-markdown-table-p))
(defun contains-markdown-table-p (markdown)
  (declare (type string markdown))
  (loop for line in (split-lines markdown)
        thereis (and (search "|" line)
                     (>= (count #\| line) 2))))

(declaim (ftype (function (string) string) normalize-markdown-for-whatsapp))
(defun normalize-markdown-for-whatsapp (markdown)
  (declare (type string markdown))
  (let ((lines (split-lines markdown)))
    (declare (type list lines))
    (with-output-to-string (out)
      (dolist (line lines)
        (let ((trim (trim-line line)))
          (declare (type string trim))
          (if (and (search "|" trim) (>= (count #\| trim) 2))
              (unless (or (every (lambda (ch) (or (char= ch #\Space)
                                                  (char= ch #\|)
                                                  (char= ch #\-)
                                                  (char= ch #\:)))
                                trim)
                          (string= trim ""))
                (write-string (format nil "- ~a" (substitute #\Space #\| trim)) out)
                (terpri out))
              (progn
                (write-string line out)
                (terpri out))))))))

(declaim (ftype (function (string) string) render-for-whatsapp))
(defun render-for-whatsapp (markdown)
  (declare (type string markdown))
  (let* ((normalized (normalize-markdown-for-whatsapp markdown))
         (ir (parse-markdown-to-ir normalized)))
    (declare (type string normalized)
             (type list ir))
    (render-ir ir :platform :whatsapp)))
