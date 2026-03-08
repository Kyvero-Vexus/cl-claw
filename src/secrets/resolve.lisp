;;;; resolve.lisp — Secret reference resolution
;;;;
;;;; Resolves ${secret:name} and secret ref objects from config files,
;;;; supporting "file" and "exec" provider types.

(defpackage :cl-claw.secrets.resolve
  (:use :cl)
  (:export
   :resolve-secret-ref-string
   :resolve-secret-ref-value
   :secret-result
   :secret-result-value
   :secret-result-error
   :secret-result-source))

(in-package :cl-claw.secrets.resolve)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Secret result ───────────────────────────────────────────────────────────

(defstruct secret-result
  "Result of resolving a secret reference."
  (value  nil :type (or string null))
  (error  nil :type (or string null))
  (source ""  :type string)) ; "file" "exec" "env" etc.

;;; ─── File provider ───────────────────────────────────────────────────────────

(declaim (ftype (function (string &key (:mode string)
                                       (:key (or string null))
                                       (:timeout-ms (or fixnum null)))
                          secret-result)
                resolve-file-secret))
(defun resolve-file-secret (path &key (mode "singleValue") key timeout-ms)
  "Resolve a secret from a file at PATH.

MODE:
  'singleValue' — read entire file content as the secret
  'json'        — parse as JSON, return value at KEY"
  (declare (type string path mode)
           (type (or string null) key)
           (type (or fixnum null) timeout-ms))
  (declare (ignore timeout-ms))
  (handler-case
      (let ((content (string-trim '(#\Space #\Tab #\Newline #\Return)
                                  (uiop:read-file-string path))))
        (declare (type string content))
        (cond
          ((string= mode "singleValue")
           (make-secret-result :value content :source "file"))
          ((string= mode "json")
           (let ((parsed (yason:parse content :object-as :hash-table)))
             (declare (type t parsed))
             (if (and key (hash-table-p parsed))
                 (let ((val (gethash key parsed)))
                   (if val
                       (make-secret-result
                        :value (format nil "~a" val)
                        :source "file")
                       (make-secret-result
                        :error (format nil "Key '~a' not found in JSON secret file" key)
                        :source "file")))
                 (make-secret-result
                  :value (with-output-to-string (s) (yason:encode parsed s))
                  :source "file"))))
          (t
           (make-secret-result
            :error (format nil "Unknown file secret mode: ~a" mode)
            :source "file"))))
    (error (c)
      (make-secret-result
       :error (format nil "Failed to read secret file ~a: ~a" path c)
       :source "file"))))

;;; ─── Exec provider ───────────────────────────────────────────────────────────

(declaim (ftype (function (string &key (:args list)
                                       (:pass-env list)
                                       (:json-only boolean)
                                       (:timeout-ms (or fixnum null)))
                          secret-result)
                resolve-exec-secret))
(defun resolve-exec-secret (command &key args pass-env json-only timeout-ms)
  "Resolve a secret by executing COMMAND.

ARGS: additional args to pass to the command
PASS-ENV: list of env var names to pass through
JSON-ONLY: if T, expect JSON output with 'id' and 'secret' fields
TIMEOUT-MS: execution timeout in milliseconds"
  (declare (type string command)
           (type list args pass-env)
           (type boolean json-only)
           (type (or fixnum null) timeout-ms))
  (declare (ignore pass-env))
  (let ((argv (cons command (or args '())))
        (timeout (or timeout-ms 30000)))
    (declare (type list argv)
             (type fixnum timeout))
    (handler-case
        (let* ((result (cl-claw.process.exec:run-command-with-timeout
                        argv :timeout-ms timeout))
               (code (cl-claw.process.exec:termination-result-code result))
               (stdout (string-trim '(#\Space #\Tab #\Newline #\Return)
                                    (cl-claw.process.exec:termination-result-stdout result))))
          (declare (type (or integer null) code)
                   (type string stdout))
          (if (and code (= code 0))
              (if json-only
                  ;; Parse JSON response: expects {"id": ..., "secret": "value"}
                  (handler-case
                      (let ((parsed (yason:parse stdout :object-as :hash-table)))
                        (declare (type t parsed))
                        (if (hash-table-p parsed)
                            (let ((secret (gethash "secret" parsed)))
                              (if secret
                                  (make-secret-result
                                   :value (format nil "~a" secret)
                                   :source "exec")
                                  (make-secret-result
                                   :error "Exec secret JSON response missing 'secret' field"
                                   :source "exec")))
                            (make-secret-result
                             :error "Exec secret JSON response is not an object"
                             :source "exec")))
                    (error (e)
                      (make-secret-result
                       :error (format nil "Failed to parse exec secret JSON: ~a" e)
                       :source "exec")))
                  ;; Plain text response
                  (make-secret-result :value stdout :source "exec"))
              (make-secret-result
               :error (format nil "Exec secret command exited with code ~a: ~a"
                              code (cl-claw.process.exec:termination-result-stderr result))
               :source "exec")))
      (error (c)
        (make-secret-result
         :error (format nil "Failed to execute secret command '~a': ~a" command c)
         :source "exec")))))

;;; ─── Secret ref parsing ──────────────────────────────────────────────────────

(declaim (ftype (function (string) boolean) secret-ref-string-p))
(defun secret-ref-string-p (str)
  "Return T if STR is a secret reference like ${secret:name}."
  (declare (type string str))
  (cl-ppcre:scan "^\\$\\{secret:[^}]+\\}$" str))

(declaim (ftype (function (string) (or string null)) parse-secret-ref-name))
(defun parse-secret-ref-name (str)
  "Extract the secret name from ${secret:NAME} syntax."
  (declare (type string str))
  (multiple-value-bind (start end regs-start regs-end)
      (cl-ppcre:scan "^\\$\\{secret:([^}]+)\\}$" str)
    (declare (ignore start end))
    (when (and regs-start (> (length regs-start) 0))
      (subseq str (aref regs-start 0) (aref regs-end 0)))))

;;; ─── Public resolution API ───────────────────────────────────────────────────

(declaim (ftype (function (string t) secret-result) resolve-secret-ref-string))
(defun resolve-secret-ref-string (ref-string config)
  "Resolve a secret ref string like ${secret:name} using CONFIG.

CONFIG is expected to be a hash-table with a 'secrets' key that maps
secret names to provider configurations."
  (declare (type string ref-string)
           (type t config))
  (let ((name (parse-secret-ref-name ref-string)))
    (declare (type (or string null) name))
    (unless name
      (return-from resolve-secret-ref-string
        (make-secret-result
         :error (format nil "Invalid secret ref: ~a" ref-string)
         :source "parse")))
    (resolve-secret-by-name name config)))

(declaim (ftype (function (string t) secret-result) resolve-secret-by-name))
(defun resolve-secret-by-name (name config)
  "Resolve a secret by NAME using the secrets section of CONFIG."
  (declare (type string name)
           (type t config))
  (let* ((secrets (when (hash-table-p config) (gethash "secrets" config)))
         (secret-config (when (hash-table-p secrets) (gethash name secrets))))
    (declare (type t secrets secret-config))
    (unless secret-config
      (return-from resolve-secret-by-name
        (make-secret-result
         :error (format nil "Secret '~a' not defined in config" name)
         :source "config")))
    (let ((source (when (hash-table-p secret-config)
                    (gethash "source" secret-config))))
      (declare (type t source))
      (cond
        ((equal source "file")
         (let ((path   (gethash "path" secret-config))
               (mode   (or (gethash "mode" secret-config) "singleValue"))
               (key    (gethash "key" secret-config)))
           (declare (type t path mode key))
           (resolve-file-secret
            (format nil "~a" path)
            :mode (format nil "~a" mode)
            :key (when key (format nil "~a" key)))))
        ((equal source "exec")
         (let ((command (gethash "command" secret-config))
               (args    (gethash "args" secret-config))
               (pass-env (gethash "passEnv" secret-config))
               (json-only (gethash "jsonOnly" secret-config)))
           (declare (type t command args pass-env json-only))
           (resolve-exec-secret
            (format nil "~a" command)
            :args (when (listp args) args)
            :pass-env (when (listp pass-env) pass-env)
            :json-only (and json-only t))))
        (t
         (make-secret-result
          :error (format nil "Unknown secret source: ~a" source)
          :source "unknown"))))))

(declaim (ftype (function (t t) t) resolve-secret-ref-value))
(defun resolve-secret-ref-value (value config)
  "Recursively resolve secret refs in VALUE (may be string, hash-table, vector, etc.)."
  (declare (type t value)
           (type t config))
  (typecase value
    (string
     (if (secret-ref-string-p value)
         (let ((result (resolve-secret-ref-string value config)))
           (declare (type secret-result result))
           (or (secret-result-value result) value))
         value))
    (hash-table
     (let ((new (make-hash-table :test 'equal)))
       (maphash (lambda (k v)
                  (setf (gethash k new)
                        (resolve-secret-ref-value v config)))
                value)
       new))
    (vector
     (map 'vector (lambda (v) (resolve-secret-ref-value v config)) value))
    (list
     (mapcar (lambda (v) (resolve-secret-ref-value v config)) value))
    (t value)))
