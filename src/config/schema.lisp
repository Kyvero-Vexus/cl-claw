;;;; schema.lisp — Configuration schema definitions and validation rules
;;;;
;;;; Implements BUILD-CONFIG-SCHEMA, LOOKUP-CONFIG-SCHEMA, and config field metadata.

(defpackage :cl-claw.config.schema
  (:use :cl)
  (:export
   :build-config-schema
   :lookup-config-schema
   :validate-config-value
   :schema-field
   :make-schema-field
   :schema-field-path
   :schema-field-type
   :schema-field-description
   :schema-field-default
   :schema-field-required-p
   :schema-field-sensitive-p
   :schema-field-enum-values
   :config-schema
   :config-schema-fields
   :config-schema-plugins
   :config-schema-channels))

(in-package :cl-claw.config.schema)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Schema field descriptor ─────────────────────────────────────────────────

(defstruct schema-field
  "A descriptor for a single configuration field."
  (path        '()  :type list)    ; list of path segments, e.g. '("gateway" "port")
  (type        :any :type keyword) ; :string :number :boolean :object :array :any
  (description ""   :type string)
  (default     nil  :type t)
  (required-p  nil  :type boolean)
  (sensitive-p nil  :type boolean)
  (enum-values nil  :type list)    ; allowed values if an enum field
  (hint        nil  :type (or string null))) ; UI hint label

;;; ─── Schema registry ─────────────────────────────────────────────────────────

(defparameter *base-config-fields*
  (list
   (make-schema-field
    :path '("gateway" "port") :type :number
    :description "Port the gateway listens on" :default 18788)
   (make-schema-field
    :path '("gateway" "mode") :type :string
    :description "Gateway run mode" :default "local"
    :enum-values '("local" "remote"))
   (make-schema-field
    :path '("gateway" "auth" "mode") :type :string
    :description "Gateway auth mode" :default "none"
    :enum-values '("none" "token" "pairing"))
   (make-schema-field
    :path '("agents" "defaults" "model") :type :string
    :description "Default model for agents" :default nil)
   (make-schema-field
    :path '("sessions" "persistence") :type :string
    :description "Session persistence mode" :default "file"
    :enum-values '("file" "none"))
   (make-schema-field
    :path '("messages" "ackReaction") :type :string
    :description "Reaction emoji for message acks" :default "eyes")
   (make-schema-field
    :path '("channels" "telegram" "dmPolicy") :type :string
    :description "Telegram DM policy" :default "pairing"
    :enum-values '("pairing" "open" "closed"))
   (make-schema-field
    :path '("channels" "telegram" "allowFrom") :type :array
    :description "Allowed Telegram senders" :default nil)
   (make-schema-field
    :path '("channels" "discord" "dmPolicy") :type :string
    :description "Discord DM policy" :default "pairing"
    :enum-values '("pairing" "open" "closed"))
   (make-schema-field
    :path '("channels" "slack" "dmPolicy") :type :string
    :description "Slack DM policy" :default "pairing"
    :enum-values '("pairing" "open" "closed"))
   (make-schema-field
    :path '("logging" "level") :type :string
    :description "Log level" :default "info"
    :enum-values '("debug" "info" "warn" "error" "silent"))
   (make-schema-field
    :path '("logging" "maxFileBytes") :type :number
    :description "Max log file size in bytes" :default (* 10 1024 1024))
   (make-schema-field
    :path '("tools" "alsoAllow") :type :array
    :description "Additional tools to allow" :default nil)
   (make-schema-field
    :path '("commands" "ownerDisplay") :type :string
    :description "Owner display mode" :default "full"
    :enum-values '("full" "hash" "initials" "none")))
  "Base configuration schema fields.")

(defstruct config-schema
  "A complete configuration schema, possibly augmented by plugins/channels."
  (fields '() :type list)
  (plugins '() :type list)
  (channels '() :type list))

(declaim (ftype (function (&key (:plugins list) (:channels list)) config-schema)
                build-config-schema))
(defun build-config-schema (&key plugins channels)
  "Build a config schema from the base fields, optionally extended by PLUGINS and CHANNELS."
  (declare (type list plugins channels))
  (let ((extra-fields '()))
    (declare (type list extra-fields))
    ;; Add plugin config schemas as fields
    (dolist (plugin plugins)
      (let ((plugin-id (getf plugin :id ""))
            (config-schema (getf plugin :config-schema nil))
            (ui-hints (getf plugin :config-ui-hints nil)))
        (declare (type string plugin-id)
                 (type t config-schema ui-hints))
        (declare (ignore config-schema))
        (when ui-hints
          (dolist (hint ui-hints)
            (let ((hint-key (car hint))
                  (hint-props (cdr hint)))
              (declare (type string hint-key)
                       (type list hint-props))
              (push (make-schema-field
                     :path (list "plugins" plugin-id hint-key)
                     :description (getf hint-props :label "")
                     :sensitive-p (getf hint-props :sensitive nil)
                     :hint (getf hint-props :label nil))
                    extra-fields))))))
    ;; Add channel config schemas
    (dolist (channel channels)
      (let ((channel-id (getf channel :id ""))
            (config-schema (getf channel :config-schema nil)))
        (declare (type string channel-id)
                 (type t config-schema))
        (declare (ignore config-schema))
        (push (make-schema-field
               :path (list "channels" channel-id)
               :type :object
               :description (format nil "Config for ~a channel" channel-id))
              extra-fields)))
    (make-config-schema
     :fields (append *base-config-fields* (reverse extra-fields))
     :plugins plugins
     :channels channels)))

(declaim (ftype (function (config-schema list) (or schema-field null))
                lookup-config-schema))
(defun lookup-config-schema (schema path)
  "Look up a SCHEMA-FIELD for PATH (list of strings) in SCHEMA.
Returns NIL if not found."
  (declare (type config-schema schema)
           (type list path))
  (find-if (lambda (field)
             (equal (schema-field-path field) path))
           (config-schema-fields schema)))

(declaim (ftype (function (t schema-field) (values boolean (or string null)))
                validate-config-value))
(defun validate-config-value (value field)
  "Validate VALUE against FIELD's type and enum constraints.
Returns (values valid-p error-message)."
  (declare (type t value)
           (type schema-field field))
  (let ((expected-type (schema-field-type field))
        (enum-values (schema-field-enum-values field)))
    (declare (type keyword expected-type)
             (type list enum-values))
    ;; Check enum constraint
    (when (and enum-values (not (member value enum-values :test #'equal)))
      (return-from validate-config-value
        (values nil
                (format nil "Value ~s is not one of: ~{~s~^, ~}" value enum-values))))
    ;; Check type
    (let ((type-ok
           (case expected-type
             (:string  (stringp value))
             (:number  (numberp value))
             (:boolean (typep value 'boolean))
             (:array   (listp value))
             (:object  (or (listp value) (hash-table-p value)))
             (:any     t)
             (t        t))))
      (declare (type boolean type-ok))
      (if type-ok
          (values t nil)
          (values nil
                  (format nil "Expected ~a, got ~a" expected-type (type-of value)))))))
