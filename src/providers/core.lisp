;;;; core.lisp — Provider registry and fallback orchestration

(defpackage :cl-claw.providers
  (:use :cl)
  (:export
   :provider-request
   :make-provider-request
   :provider-request-prompt
   :provider-request-model
   :provider-request-params
   :provider-response
   :provider-response-ok-p
   :provider-response-text
   :provider-response-provider
   :provider-response-model
   :provider-response-error
   :provider-adapter
   :make-provider-adapter
   :provider-registry
   :create-provider-registry
   :register-provider
   :invoke-with-fallback
   :make-default-provider-registry))

(in-package :cl-claw.providers)

(declaim (optimize (safety 3) (debug 3)))

(defstruct provider-request
  (prompt "" :type string)
  (model "" :type string)
  (params (make-hash-table :test 'equal) :type hash-table))

(defstruct provider-response
  (ok-p nil :type boolean)
  (text "" :type string)
  (provider "" :type string)
  (model "" :type string)
  (error nil :type (or string null))
  (usage (make-hash-table :test 'equal) :type hash-table))

(defstruct provider-adapter
  (name "" :type string)
  (invoke-fn nil :type (or function null))
  (priority 100 :type fixnum)
  (enabled-p t :type boolean))

(defstruct (provider-registry (:constructor %make-provider-registry))
  (lock (bt:make-lock "provider-registry-lock") :type t)
  (providers '() :type list))

(declaim (ftype (function () provider-registry) create-provider-registry))
(defun create-provider-registry ()
  (%make-provider-registry))

(declaim (ftype (function (provider-registry provider-adapter) provider-registry)
                register-provider))
(defun register-provider (registry provider)
  (declare (type provider-registry registry)
           (type provider-adapter provider))
  (bt:with-lock-held ((provider-registry-lock registry))
    (let ((remaining
            (remove-if (lambda (item)
                         (declare (type provider-adapter item))
                         (string= (provider-adapter-name item)
                                  (provider-adapter-name provider)))
                       (provider-registry-providers registry))))
      (declare (type list remaining))
      (setf (provider-registry-providers registry)
            (sort (cons provider remaining) #'< :key #'provider-adapter-priority))))
  registry)

(declaim (ftype (function (string string provider-request) provider-response)
                mock-provider-invoke))
(defun mock-provider-invoke (provider-name provider-prefix request)
  (declare (type string provider-name provider-prefix)
           (type provider-request request))
  (let ((fail-marker (format nil "[fail:~a]" provider-name)))
    (if (search fail-marker (provider-request-prompt request) :test #'char-equal)
        (make-provider-response :ok-p nil
                                :provider provider-name
                                :model (provider-request-model request)
                                :error (format nil "~a rejected request" provider-name)
                                :text "")
        (let ((usage (make-hash-table :test 'equal)))
          (declare (type hash-table usage))
          (setf (gethash "inputTokens" usage) (length (provider-request-prompt request))
                (gethash "outputTokens" usage) 16)
          (make-provider-response :ok-p t
                                  :provider provider-name
                                  :model (provider-request-model request)
                                  :text (format nil "~a ~a" provider-prefix
                                                (provider-request-prompt request))
                                  :usage usage)))))

(declaim (ftype (function () provider-registry) make-default-provider-registry))
(defun make-default-provider-registry ()
  (let ((registry (create-provider-registry)))
    (declare (type provider-registry registry))
    (register-provider registry
                       (make-provider-adapter
                        :name "openai"
                        :priority 10
                        :invoke-fn (lambda (request)
                                     (declare (type provider-request request))
                                     (mock-provider-invoke "openai" "openai:" request))))
    (register-provider registry
                       (make-provider-adapter
                        :name "anthropic"
                        :priority 20
                        :invoke-fn (lambda (request)
                                     (declare (type provider-request request))
                                     (mock-provider-invoke "anthropic" "anthropic:" request))))
    (register-provider registry
                       (make-provider-adapter
                        :name "google"
                        :priority 30
                        :invoke-fn (lambda (request)
                                     (declare (type provider-request request))
                                     (mock-provider-invoke "google" "google:" request))))
    registry))

(declaim (ftype (function (provider-registry (or string null)) list) ordered-providers))
(defun ordered-providers (registry preferred-provider)
  (declare (type provider-registry registry)
           (type (or string null) preferred-provider))
  (bt:with-lock-held ((provider-registry-lock registry))
    (let* ((enabled
             (remove-if-not (lambda (item)
                              (declare (type provider-adapter item))
                              (provider-adapter-enabled-p item))
                            (copy-list (provider-registry-providers registry))))
           (chosen
             (if preferred-provider
                 (stable-sort enabled
                              (lambda (a b)
                                (declare (type provider-adapter a b))
                                (let ((a-pref (string= (provider-adapter-name a) preferred-provider))
                                      (b-pref (string= (provider-adapter-name b) preferred-provider)))
                                  (declare (type boolean a-pref b-pref))
                                  (if (eql a-pref b-pref)
                                      (< (provider-adapter-priority a)
                                         (provider-adapter-priority b))
                                      a-pref))))
                 enabled)))
      (declare (type list enabled chosen))
      chosen)))

(declaim (ftype (function (provider-registry provider-request &key (:preferred-provider (or string null)))
                          provider-response)
                invoke-with-fallback))
(defun invoke-with-fallback (registry request &key preferred-provider)
  (declare (type provider-registry registry)
           (type provider-request request)
           (type (or string null) preferred-provider))
  (let ((last-error "no providers registered"))
    (declare (type string last-error))
    (dolist (provider (ordered-providers registry preferred-provider)
             (make-provider-response :ok-p nil
                                     :provider "none"
                                     :model (provider-request-model request)
                                     :error last-error
                                     :text ""))
      (declare (type provider-adapter provider))
      (let ((fn (provider-adapter-invoke-fn provider)))
        (declare (type (or function null) fn))
        (when fn
          (let ((result (funcall fn request)))
            (declare (type provider-response result))
            (if (provider-response-ok-p result)
                (return result)
                (setf last-error (or (provider-response-error result)
                                     (format nil "~a failed" (provider-adapter-name provider)))))))))))