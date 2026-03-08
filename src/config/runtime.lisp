;;;; runtime.lisp — Runtime configuration management
;;;;
;;;; Provides a mutable runtime config overlay that can be applied on top of
;;;; the base config, supporting per-session overrides.

(defpackage :cl-claw.config.runtime
  (:use :cl)
  (:export
   :runtime-config
   :make-runtime-config
   :runtime-config-get
   :runtime-config-set
   :runtime-config-reset
   :runtime-config-snapshot
   :merge-runtime-override))

(in-package :cl-claw.config.runtime)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Runtime config store ────────────────────────────────────────────────────

(defstruct (runtime-config (:constructor %make-runtime-config))
  "A runtime config overlay. Holds overrides on top of a base config."
  (lock     (bt:make-lock "runtime-config-lock") :type t)
  (base     (make-hash-table :test 'equal) :type hash-table)
  (overrides (make-hash-table :test 'equal) :type hash-table))

;;; ─── Nested hash-table helpers ───────────────────────────────────────────────

(declaim (ftype (function (hash-table list) t) nested-ht-get))
(defun nested-ht-get (ht path)
  "Get value at PATH (list of string keys) in HT (hash-table)."
  (declare (type hash-table ht)
           (type list path))
  (if (null path)
      ht
      (let ((child (gethash (car path) ht)))
        (declare (type t child))
        (if (and child (hash-table-p child))
            (nested-ht-get child (cdr path))
            child))))

(declaim (ftype (function (hash-table list t) t) nested-ht-set))
(defun nested-ht-set (ht path value)
  "Set VALUE at PATH in HT, creating intermediate hash-tables as needed."
  (declare (type hash-table ht)
           (type list path)
           (type t value))
  (if (= (length path) 1)
      (setf (gethash (car path) ht) value)
      (let* ((key (car path))
             (child (gethash key ht)))
        (declare (type string key)
                 (type t child))
        (unless (hash-table-p child)
          (setf child (make-hash-table :test 'equal))
          (setf (gethash key ht) child))
        (nested-ht-set child (cdr path) value))))

;;; ─── Public API ──────────────────────────────────────────────────────────────

(declaim (ftype (function (t) runtime-config) make-runtime-config))
(defun make-runtime-config (base-config)
  "Create a runtime config from BASE-CONFIG (hash-table or nil)."
  (declare (type t base-config))
  (let ((base (typecase base-config
                (hash-table base-config)
                (t (make-hash-table :test 'equal)))))
    (declare (type hash-table base))
    (%make-runtime-config :base base)))

(declaim (ftype (function (runtime-config list) t) runtime-config-get))
(defun runtime-config-get (rc path)
  "Get value at PATH from RC, checking overrides first, then base."
  (declare (type runtime-config rc)
           (type list path))
  (bt:with-lock-held ((runtime-config-lock rc))
    (or (nested-ht-get (runtime-config-overrides rc) path)
        (nested-ht-get (runtime-config-base rc) path))))

(declaim (ftype (function (runtime-config list t) t) runtime-config-set))
(defun runtime-config-set (rc path value)
  "Set VALUE at PATH in RC's overrides layer."
  (declare (type runtime-config rc)
           (type list path)
           (type t value))
  (bt:with-lock-held ((runtime-config-lock rc))
    (nested-ht-set (runtime-config-overrides rc) path value)))

(declaim (ftype (function (runtime-config) t) runtime-config-reset))
(defun runtime-config-reset (rc)
  "Clear all overrides from RC."
  (declare (type runtime-config rc))
  (bt:with-lock-held ((runtime-config-lock rc))
    (clrhash (runtime-config-overrides rc))))

(declaim (ftype (function (runtime-config) hash-table) runtime-config-snapshot))
(defun runtime-config-snapshot (rc)
  "Return a merged snapshot of base + overrides."
  (declare (type runtime-config rc))
  (bt:with-lock-held ((runtime-config-lock rc))
    (let ((result (make-hash-table :test 'equal)))
      (declare (type hash-table result))
      (maphash (lambda (k v) (setf (gethash k result) v))
               (runtime-config-base rc))
      (maphash (lambda (k v) (setf (gethash k result) v))
               (runtime-config-overrides rc))
      result)))

(declaim (ftype (function (t t) t) merge-runtime-override))
(defun merge-runtime-override (base override)
  "Merge OVERRIDE onto BASE (both hash-tables). Returns new merged hash-table."
  (declare (type t base override))
  (let ((result (make-hash-table :test 'equal)))
    (declare (type hash-table result))
    (when (hash-table-p base)
      (maphash (lambda (k v) (setf (gethash k result) v)) base))
    (when (hash-table-p override)
      (maphash (lambda (k v)
                 (let ((existing (gethash k result)))
                   (setf (gethash k result)
                         (if (and (hash-table-p existing) (hash-table-p v))
                             (merge-runtime-override existing v)
                             v))))
               override))
    result))
