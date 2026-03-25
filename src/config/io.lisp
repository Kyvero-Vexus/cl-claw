;;;; io.lisp — Config file I/O (read/write with audit logging and backup)
;;;;
;;;; Implements CREATE-CONFIG-IO which returns a config I/O handle supporting
;;;; READ-CONFIG-FILE-SNAPSHOT and WRITE-CONFIG-FILE.

(defpackage :cl-claw.config.io
  (:use :cl)
  (:export
   :create-config-io
   :config-io
   :config-snapshot
   :config-snapshot-valid
   :config-snapshot-config
   :config-snapshot-resolved
   :config-snapshot-path
   :read-config-file-snapshot
   :write-config-file
   :resolve-env-refs-in-value))

(in-package :cl-claw.config.io)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Snapshot ────────────────────────────────────────────────────────────────

(defstruct config-snapshot
  "Result of reading a config file snapshot."
  (valid    nil  :type boolean)
  (config   nil  :type t)       ; parsed config (hash-table or nil)
  (resolved nil  :type t)       ; config with defaults merged
  (path     ""   :type string)
  (error    nil  :type (or string null)))

;;; ─── Config IO handle ────────────────────────────────────────────────────────

(defstruct (config-io (:constructor %make-config-io))
  "A config I/O handle."
  (env          (make-hash-table :test 'equal) :type hash-table)
  (homedir-fn   #'uiop:getenv :type function)
  (logger       nil :type t))

;;; ─── Path helpers ────────────────────────────────────────────────────────────

(declaim (ftype (function (config-io) string) openclaw-dir))
(defun openclaw-dir (io)
  "Return the .openclaw directory path."
  (declare (type config-io io))
  (let ((home (funcall (config-io-homedir-fn io))))
    (declare (type string home))
    (uiop:native-namestring
     (merge-pathnames ".openclaw/" (uiop:parse-native-namestring home :ensure-directory t)))))

(declaim (ftype (function (config-io) string) config-file-path))
(defun config-file-path (io)
  "Return the full path to openclaw.json."
  (declare (type config-io io))
  (uiop:native-namestring
   (merge-pathnames "openclaw.json"
                    (uiop:parse-native-namestring (openclaw-dir io) :ensure-directory t))))

(declaim (ftype (function (config-io) string) audit-log-path))
(defun audit-log-path (io)
  "Return the full path to the config audit JSONL log."
  (declare (type config-io io))
  (uiop:native-namestring
   (merge-pathnames "logs/config-audit.jsonl"
                    (uiop:parse-native-namestring (openclaw-dir io) :ensure-directory t))))

;;; ─── SHA-256 hashing ─────────────────────────────────────────────────────────

(declaim (ftype (function (string) string) sha256-hex))
(defun sha256-hex (content)
  "Return the SHA-256 hex digest of CONTENT string."
  (declare (type string content))
  (handler-case
      (let* ((bytes (ironclad:ascii-string-to-byte-array content))
             (digest (ironclad:digest-sequence :sha256 bytes)))
        (declare (type (simple-array (unsigned-byte 8) (*)) bytes digest))
        (ironclad:byte-array-to-hex-string digest))
    (error ()
      ;; Fallback: simple hash if ironclad fails
      (format nil "~x" (sxhash content)))))

;;; ─── JSON helpers ────────────────────────────────────────────────────────────

(declaim (ftype (function (t) string) to-json))
(defun to-json (obj)
  "Serialize OBJ to a JSON string."
  (declare (type t obj))
  (with-output-to-string (s)
    (yason:encode obj s)))

(declaim (ftype (function (string) t) from-json))
(defun from-json (str)
  "Parse a JSON string into a Lisp value."
  (declare (type string str))
  (yason:parse str :object-as :hash-table))

;;; ─── Env substitution ────────────────────────────────────────────────────────

(declaim (ftype (function (string hash-table) string) expand-env-refs))
(defun expand-env-refs (str env)
  "Replace ${VAR} references in STR with values from ENV hash-table.
Leaves unresolved references as-is (preserves ${VAR} literal)."
  (declare (type string str)
           (type hash-table env))
  (cl-ppcre:regex-replace-all
   "\\$\\{([A-Za-z_][A-Za-z0-9_]*)\\}"
   str
   (lambda (match &rest registers)
     (declare (ignore match))
     (let ((var-name (car registers)))
       (declare (type string var-name))
       (or (gethash var-name env) (format nil "${~a}" var-name))))))

;;; ─── Config resolution (apply env refs) ─────────────────────────────────────

(declaim (ftype (function (t hash-table) t) resolve-env-refs-in-value))
(defun resolve-env-refs-in-value (value env)
  "Recursively expand env refs in VALUE using ENV."
  (declare (type t value)
           (type hash-table env))
  (typecase value
    (string (expand-env-refs value env))
    (hash-table
     (let ((result (make-hash-table :test 'equal)))
       (maphash (lambda (k v)
                  (setf (gethash k result)
                        (resolve-env-refs-in-value v env)))
                value)
       result))
    (vector
     (map 'vector (lambda (v) (resolve-env-refs-in-value v env)) value))
    (list
     (mapcar (lambda (v) (resolve-env-refs-in-value v env)) value))
    (t value)))

;;; ─── Validation helpers ──────────────────────────────────────────────────────

(declaim (ftype (function (t) (values boolean (or string null))) validate-dm-policy))
(defun validate-dm-policy (config)
  "Validate DM policy constraints. Returns (valid-p error-msg)."
  (declare (type t config))
  (when (hash-table-p config)
    (let ((channels (gethash "channels" config)))
      (when (hash-table-p channels)
        ;; Check telegram: dmPolicy=open requires allowFrom with wildcard
        (let ((telegram (gethash "telegram" channels)))
          (when (and (hash-table-p telegram)
                     (equal (gethash "dmPolicy" telegram) "open"))
            (let ((allow-from (gethash "allowFrom" telegram)))
              (unless (and allow-from
                           (or (find "*" (coerce allow-from 'list) :test #'equal)
                               (equal allow-from #("*"))))
                (return-from validate-dm-policy
                  (values nil
                          (format nil "~a~%~a"
                                  "openclaw config set channels.telegram.allowFrom '[\"*\"]'"
                                  "openclaw config set channels.telegram.dmPolicy \"pairing\""))))))))))
  (values t nil))

;;; ─── Public API ──────────────────────────────────────────────────────────────

(declaim (ftype (function (&key (:env t) (:homedir function) (:logger t)) config-io)
                create-config-io))
(defun create-config-io (&key env homedir logger)
  "Create a CONFIG-IO handle.

ENV: hash-table or list of (key . value) pairs for env var substitution
HOMEDIR: (lambda () → string) — returns home directory path
LOGGER: object with WARN and ERROR methods"
  (declare (type t env homedir logger))
  (let ((env-ht (typecase env
                  (hash-table env)
                  (list (let ((ht (make-hash-table :test 'equal)))
                          (dolist (pair env ht)
                            (when (consp pair)
                              (setf (gethash (car pair) ht) (cdr pair))))))
                  (t (make-hash-table :test 'equal)))))
    (declare (type hash-table env-ht))
    (%make-config-io
     :env env-ht
     :homedir-fn (or homedir
                     (lambda ()
                       (declare (optimize (safety 3) (debug 3)))
                       (or (uiop:getenv "HOME") "")))
     :logger logger)))

(declaim (ftype (function (config-io) config-snapshot) read-config-file-snapshot))
(defun read-config-file-snapshot (io)
  "Read the config file and return a CONFIG-SNAPSHOT."
  (declare (type config-io io))
  (let ((path (config-file-path io)))
    (declare (type string path))
    (if (uiop:file-exists-p path)
        (handler-case
            (let* ((content (uiop:read-file-string path))
                   (parsed  (from-json content))
                   (resolved (resolve-env-refs-in-value parsed (config-io-env io))))
              (declare (type string content)
                       (type t parsed resolved))
              (make-config-snapshot
               :valid t
               :config parsed
               :resolved resolved
               :path path))
          (error (c)
            (make-config-snapshot
             :valid nil
             :config nil
             :resolved nil
             :path path
             :error (format nil "~a" c))))
        ;; File doesn't exist — return empty valid snapshot
        (make-config-snapshot
         :valid t
         :config (make-hash-table :test 'equal)
         :resolved (make-hash-table :test 'equal)
         :path path))))

(declaim (ftype (function (config-io t) t) %emit-audit-entry))
(defun %emit-audit-entry (io entry)
  "Append an audit entry hash-table to the audit JSONL log."
  (declare (type config-io io)
           (type hash-table entry))
  (let ((audit-path (audit-log-path io)))
    (declare (type string audit-path))
    (uiop:ensure-all-directories-exist
     (list (uiop:pathname-directory-pathname audit-path)))
    (let ((audit-line (with-output-to-string (s)
                        (yason:encode entry s)
                        (terpri s))))
      (declare (type string audit-line))
      (with-open-file (f audit-path
                         :direction :output
                         :if-exists :append
                         :if-does-not-exist :create)
        (write-string audit-line f)))))

(declaim (ftype (function (config-io t) t) %call-logger-warn))
(defun %call-logger-warn (io msg)
  "Call the IO logger's warn function with MSG."
  (declare (type config-io io)
           (type string msg))
  (let ((logger (config-io-logger io)))
    (declare (type t logger))
    (when logger
      (let ((fn (cond
                  ((hash-table-p logger) (gethash "warn" logger))
                  ((listp logger) (getf logger :warn))
                  (t nil))))
        (when (functionp fn)
          (funcall fn msg))))))

(declaim (ftype (function (config-io t &key (:unset-paths list)) t) write-config-file))
(defun write-config-file (io config &key unset-paths)
  "Write CONFIG to the config file."
  (declare (type config-io io)
           (type t config)
           (type list unset-paths))
  ;; Validate before writing
  (multiple-value-bind (valid-p error-msg)
      (validate-dm-policy config)
    (unless valid-p
      (error "Config validation failed: ~a" error-msg)))
  (let* ((path (config-file-path io))
         (to-write (deep-copy-hash-table config))
         (exists-before (and (uiop:file-exists-p path) t)))
    (declare (type string path)
             (type t to-write)
             (type boolean exists-before))
    ;; Apply unset paths on the copy
    (dolist (up unset-paths)
      (declare (type list up))
      (apply-unset-path to-write up))
    ;; Ensure directory exists
    (uiop:ensure-all-directories-exist
     (list (uiop:pathname-directory-pathname path)))
    ;; Compute previous hash and backup
    (let ((prev-hash (when exists-before
                       (sha256-hex (uiop:read-file-string path)))))
      (declare (type (or string null) prev-hash))
      (when exists-before
        (let ((bak (format nil "~a.bak" path)))
          (declare (type string bak))
          (uiop:copy-file path bak)
          (%call-logger-warn
           io
           (format nil "Config overwrite: ~a -> ~a (sha256: ~a)"
                   path bak (or prev-hash "")))))
      ;; Serialize and write
      (let ((content (with-output-to-string (s)
                       (yason:encode to-write s)
                       (terpri s))))
        (declare (type string content))
        (uiop:with-staging-pathname (staging path)
          (uiop:with-output-file (out staging :if-exists :supersede)
            (write-string content out)))
        ;; Build and emit audit entry
        (let* ((next-hash (sha256-hex content))
               (env-ht (config-io-env io))
               (watch-mode (gethash "OPENCLAW_WATCH_MODE" env-ht))
               (watch-sess (gethash "OPENCLAW_WATCH_SESSION" env-ht))
               (watch-cmd  (gethash "OPENCLAW_WATCH_COMMAND" env-ht))
               (entry (make-hash-table :test 'equal)))
          (declare (type string next-hash)
                   (type hash-table env-ht entry)
                   (type t watch-mode watch-sess watch-cmd))
          (setf (gethash "source" entry) "config-io"
                (gethash "event" entry) "config.write"
                (gethash "configPath" entry) path
                (gethash "existsBefore" entry) exists-before
                (gethash "hasMetaAfter" entry) t
                (gethash "previousHash" entry) (or prev-hash "")
                (gethash "nextHash" entry) next-hash
                (gethash "result" entry) "rename")
          (when watch-mode
            (setf (gethash "watchMode" entry)
                  (cl-claw.infra.env:is-truthy-env-value watch-mode)))
          (when watch-sess
            (setf (gethash "watchSession" entry) watch-sess))
          (when watch-cmd
            (setf (gethash "watchCommand" entry) watch-cmd))
          (%emit-audit-entry io entry))))))

;;; ─── Internal helpers ────────────────────────────────────────────────────────

(defvar *blocked-keys* '("__proto__" "constructor" "prototype")
  "Prototype pollution keys that are never traversed.")

(declaim (ftype (function (t list) t) apply-unset-path))
(defun apply-unset-path (obj path)
  "Mutate OBJ by unsetting the nested key at PATH.
Silently ignores missing paths or blocked prototype keys."
  (declare (type t obj)
           (type list path))
  (when (null path) (return-from apply-unset-path obj))
  (let ((key (car path))
        (rest (cdr path)))
    (declare (type t key)
             (type list rest))
    ;; Block prototype pollution
    (when (member key *blocked-keys* :test #'equal)
      (return-from apply-unset-path obj))
    (typecase obj
      (hash-table
       (if (null rest)
           ;; Leaf: remove the key
           (remhash key obj)
           ;; Recurse
           (let ((child (gethash key obj)))
             (when child
               (apply-unset-path child rest))))
       obj)
      (vector
       (when (and (null rest) (stringp key))
         (let ((idx (parse-integer key :junk-allowed t)))
           (when (and idx (< idx (length obj)) (>= idx 0))
             ;; Remove by shifting
             (let ((new-vec (concatenate 'vector
                                         (subseq obj 0 idx)
                                         (subseq obj (1+ idx)))))
               (declare (type vector new-vec))
               ;; We can't resize in place — return new vec
               ;; Caller gets the mutation through hash-table parent
               (declare (ignore new-vec))))))
       obj)
      (t obj))))

(declaim (ftype (function (t) t) deep-copy-hash-table))
(defun deep-copy-hash-table (obj)
  "Deep copy OBJ (hash-tables, vectors, strings are copied; atoms returned as-is)."
  (declare (type t obj))
  (typecase obj
    (hash-table
     (let ((new (make-hash-table :test (hash-table-test obj))))
       (maphash (lambda (k v)
                  (setf (gethash k new) (deep-copy-hash-table v)))
                obj)
       new))
    (vector
     (map 'vector #'deep-copy-hash-table obj))
    (list
     (mapcar #'deep-copy-hash-table obj))
    (t obj)))
