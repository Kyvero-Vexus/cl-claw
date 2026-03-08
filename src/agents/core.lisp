;;;; core.lisp — Agent configuration and workspace helpers

(defpackage :cl-claw.agents
  (:use :cl)
  (:export
   :normalize-agent-id
   :resolve-openclaw-agent-dir
   :resolve-agent-workspace-dir
   :resolve-agent-config
   :resolve-agent-model-primary
   :resolve-agent-model-fallbacks
   :agent-has-model-fallbacks-p))

(in-package :cl-claw.agents)

(declaim (optimize (safety 3) (debug 3)))

(declaim (ftype (function (string) string) %trim-string))
(defun %trim-string (value)
  (declare (type string value))
  (string-trim '(#\Space #\Tab #\Newline #\Return) value))

(declaim (ftype (function ((or string null)) boolean) %blank-string-p))
(defun %blank-string-p (value)
  (declare (type (or string null) value))
  (or (null value)
      (string= "" (%trim-string value))))

(declaim (ftype (function (string) string) normalize-agent-id))
(defun normalize-agent-id (agent-id)
  (declare (type string agent-id))
  (let ((trimmed (string-downcase (%trim-string agent-id))))
    (declare (type string trimmed))
    (if (string= "" trimmed)
        "main"
        (with-output-to-string (out)
          (loop for ch across trimmed do
            (cond
              ((or (alphanumericp ch) (char= ch #\-) (char= ch #\_))
               (write-char ch out))
              (t
               (write-char #\- out))))))))

(declaim (ftype (function (&key (:openclaw-agent-dir (or string null))
                                 (:pi-coding-agent-dir (or string null))
                                 (:openclaw-home (or string null))
                                 (:home (or string null)))
                          string)
                resolve-openclaw-agent-dir))
(defun resolve-openclaw-agent-dir (&key openclaw-agent-dir
                                        pi-coding-agent-dir
                                        openclaw-home
                                        home)
  (declare (type (or string null) openclaw-agent-dir pi-coding-agent-dir openclaw-home home))
  (cond
    ((not (%blank-string-p openclaw-agent-dir)) (%trim-string (the string openclaw-agent-dir)))
    ((not (%blank-string-p pi-coding-agent-dir)) (%trim-string (the string pi-coding-agent-dir)))
    ((not (%blank-string-p openclaw-home))
     (namestring
      (merge-pathnames "agents/" (uiop:ensure-directory-pathname (the string openclaw-home)))))
    (t
     (let ((home-dir (or (and (not (%blank-string-p home)) (%trim-string (the string home)))
                         (uiop:getenv "HOME")
                         "~")))
       (declare (type string home-dir))
       (namestring
        (merge-pathnames ".openclaw/agents/" (uiop:ensure-directory-pathname home-dir)))))))

(declaim (ftype (function (string string) string) resolve-agent-workspace-dir))
(defun resolve-agent-workspace-dir (agent-dir agent-id)
  (declare (type string agent-dir agent-id))
  (let ((normalized (normalize-agent-id agent-id)))
    (declare (type string normalized))
    (namestring
     (merge-pathnames (format nil "~a/" normalized)
                      (uiop:ensure-directory-pathname agent-dir)))))

(declaim (ftype (function (hash-table string) (or hash-table null)) resolve-agent-config))
(defun resolve-agent-config (config agent-id)
  (declare (type hash-table config)
           (type string agent-id))
  (let* ((agents (gethash "agents" config))
         (list (and (hash-table-p agents) (gethash "list" agents)))
         (normalized (normalize-agent-id agent-id)))
    (declare (type (or hash-table null) agents list)
             (type string normalized))
    (and (hash-table-p list)
         (let ((entry (gethash normalized list)))
           (declare (type t entry))
           (and (hash-table-p entry) entry)))))

(declaim (ftype (function (hash-table string) (or string null)) resolve-agent-model-primary))
(defun resolve-agent-model-primary (config agent-id)
  (declare (type hash-table config)
           (type string agent-id))
  (let* ((agent (resolve-agent-config config agent-id))
         (model (and agent (gethash "model" agent))))
    (declare (type (or hash-table null) agent)
             (type t model))
    (cond
      ((stringp model) (let ((trim (%trim-string model)))
                         (declare (type string trim))
                         (unless (string= trim "") trim)))
      ((and (hash-table-p model) (stringp (gethash "primary" model)))
       (let ((trim (%trim-string (gethash "primary" model))))
         (declare (type string trim))
         (unless (string= trim "") trim)))
      (t nil))))

(declaim (ftype (function (hash-table string) list) resolve-agent-model-fallbacks))
(defun resolve-agent-model-fallbacks (config agent-id)
  (declare (type hash-table config)
           (type string agent-id))
  (let* ((agent (resolve-agent-config config agent-id))
         (model (and agent (gethash "model" agent)))
         (raw (and (hash-table-p model) (gethash "fallbacks" model))))
    (declare (type (or hash-table null) agent)
             (type t model raw))
    (if (listp raw)
        (loop for item in raw
              if (and (stringp item)
                      (not (string= "" (%trim-string item))))
                collect (%trim-string item))
        nil)))

(declaim (ftype (function (hash-table string) boolean) agent-has-model-fallbacks-p))
(defun agent-has-model-fallbacks-p (config agent-id)
  (declare (type hash-table config)
           (type string agent-id))
  (not (null (resolve-agent-model-fallbacks config agent-id))))
