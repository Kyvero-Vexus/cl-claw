;;;; validation.lisp — Configuration validation rules
;;;;
;;;; Implements VALIDATE-CONFIG which runs all validation rules against a config
;;;; and returns a list of validation errors.

(defpackage :cl-claw.config.validation
  (:use :cl)
  (:export
   :validate-config
   :validation-error
   :validation-error-path
   :validation-error-message
   :validation-error-code))

(in-package :cl-claw.config.validation)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Validation error ────────────────────────────────────────────────────────

(defstruct validation-error
  "A single validation error."
  (path    '() :type list)    ; list of path segments
  (message ""  :type string)
  (code    ""  :type string)) ; machine-readable code

;;; ─── Config access helpers ───────────────────────────────────────────────────

(declaim (ftype (function (t list) t) get-nested))
(defun get-nested (obj path)
  "Get value at PATH in OBJ (hash-table or plist)."
  (declare (type t obj)
           (type list path))
  (if (null path)
      obj
      (typecase obj
        (hash-table
         (get-nested (gethash (car path) obj) (cdr path)))
        (t nil))))

;;; ─── Validation rules ────────────────────────────────────────────────────────

(defun check-dm-policy-allowfrom (config errors)
  "DM policy 'open' requires allowFrom with wildcard."
  (declare (type t config)
           (type list errors))
  (let ((channels (get-nested config '("channels"))))
    (dolist (channel-id '("telegram" "discord" "slack"))
      (declare (type string channel-id))
      (let ((ch (when (hash-table-p channels)
                  (gethash channel-id channels))))
        (when (hash-table-p ch)
          (let ((dm-policy (gethash "dmPolicy" ch))
                (allow-from (gethash "allowFrom" ch)))
            (when (equal dm-policy "open")
              (let ((has-wildcard
                     (and allow-from
                          (typecase allow-from
                            (vector (find "*" (coerce allow-from 'list) :test #'equal))
                            (list   (find "*" allow-from :test #'equal))
                            (t      nil)))))
                (declare (type boolean has-wildcard))
                (unless has-wildcard
                  (push (make-validation-error
                         :path (list "channels" channel-id "allowFrom")
                         :message (format nil "dmPolicy 'open' requires allowFrom to include '*'")
                         :code "ALLOWFROM_REQUIRES_WILDCARD")
                        errors)))))))
    errors)))  ; closes let((channels)), defun

(defun check-logging-max-file-bytes (config errors)
  "maxFileBytes must be at least 1MB."
  (declare (type t config)
           (type list errors))
  (let ((max-bytes (get-nested config '("logging" "maxFileBytes"))))
    (when (and max-bytes (numberp max-bytes) (< max-bytes (* 1024 1024)))
      (push (make-validation-error
             :path '("logging" "maxFileBytes")
             :message (format nil "maxFileBytes must be at least 1048576 (1 MB), got ~a" max-bytes)
             :code "LOG_FILE_TOO_SMALL")
            errors))
    errors))

(defun check-gateway-tailscale-bind (config errors)
  "gateway.bind must be a valid value."
  (declare (type t config)
           (type list errors))
  (let ((bind (get-nested config '("gateway" "bind"))))
    (when (and bind (stringp bind)
               (not (member bind '("loopback" "tailscale" "all") :test #'equal)))
      (push (make-validation-error
             :path '("gateway" "bind")
             :message (format nil "gateway.bind must be one of: loopback, tailscale, all")
             :code "INVALID_GATEWAY_BIND")
            errors))
    errors))

;;; ─── Main validator ──────────────────────────────────────────────────────────

(declaim (ftype (function (t) list) validate-config))
(defun validate-config (config)
  "Validate CONFIG against all rules. Returns a list of VALIDATION-ERROR structs.
Returns an empty list if config is valid."
  (declare (type t config))
  (let ((errors '()))
    (declare (type list errors))
    (setf errors (check-dm-policy-allowfrom config errors))
    (setf errors (check-logging-max-file-bytes config errors))
    (setf errors (check-gateway-tailscale-bind config errors))
    (reverse errors)))
