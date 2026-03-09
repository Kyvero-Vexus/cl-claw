;;;; auth-profiles.lisp — Agent auth profile store, migration, credential eligibility,
;;;;                      OAuth refresh/fallback, cooldown, round-robin
;;;;
;;;; The largest auth surface: manages multiple credential types (API keys, tokens,
;;;; OAuth), provider-specific logic (AWS, GitHub Copilot), cooldown tracking,
;;;; and round-robin profile selection.

(defpackage :cl-claw.agents.auth-profiles
  (:use :cl)
  (:export
   ;; Store
   :make-auth-profile-store
   :auth-profile-store
   :auth-profile-store-version
   :auth-profile-store-profiles
   :store-get-profile
   :store-set-profile
   :store-remove-profile
   :store-list-profiles
   :store-profiles-for-provider
   ;; Credential state
   :resolve-token-expiry-state
   :evaluate-credential-eligibility
   ;; Cooldown
   :set-profile-cooldown
   :get-profile-cooldown
   :clear-profile-cooldown
   :get-soonest-cooldown-expiry
   ;; Auth mode resolution
   :resolve-model-auth-mode
   :resolve-aws-sdk-env-var-name
   :require-api-key
   ;; Round-robin
   :pick-next-eligible-profile))

(in-package :cl-claw.agents.auth-profiles)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Auth Profile Store ─────────────────────────────────────────────────────

(defstruct (auth-profile-store (:conc-name auth-profile-store-))
  "Store for auth profiles, keyed by profile ID."
  (version 1 :type fixnum)
  (profiles (make-hash-table :test 'equal) :type hash-table)
  (cooldowns (make-hash-table :test 'equal) :type hash-table))

;;; ─── Profile CRUD ───────────────────────────────────────────────────────────

(declaim (ftype (function (auth-profile-store string) (or hash-table null))
                store-get-profile))
(defun store-get-profile (store profile-id)
  "Get a profile by its ID."
  (declare (type auth-profile-store store) (type string profile-id))
  (gethash profile-id (auth-profile-store-profiles store)))

(declaim (ftype (function (auth-profile-store string hash-table) null)
                store-set-profile))
(defun store-set-profile (store profile-id profile)
  "Set or update a profile."
  (declare (type auth-profile-store store)
           (type string profile-id)
           (type hash-table profile))
  (setf (gethash profile-id (auth-profile-store-profiles store)) profile)
  nil)

(declaim (ftype (function (auth-profile-store string) boolean) store-remove-profile))
(defun store-remove-profile (store profile-id)
  "Remove a profile. Returns T if it existed."
  (declare (type auth-profile-store store) (type string profile-id))
  (not (null (remhash profile-id (auth-profile-store-profiles store)))))

(declaim (ftype (function (auth-profile-store) list) store-list-profiles))
(defun store-list-profiles (store)
  "List all profile IDs."
  (declare (type auth-profile-store store))
  (let ((ids nil))
    (maphash (lambda (k v) (declare (ignore v)) (push k ids))
             (auth-profile-store-profiles store))
    ids))

(declaim (ftype (function (auth-profile-store string) list) store-profiles-for-provider))
(defun store-profiles-for-provider (store provider)
  "List profile IDs whose provider matches (case-insensitive)."
  (declare (type auth-profile-store store) (type string provider))
  (let ((down (string-downcase provider))
        (result nil))
    (declare (type string down) (type list result))
    (maphash (lambda (id profile)
               (declare (type string id))
               (when (and (hash-table-p profile)
                          (stringp (gethash "provider" profile))
                          (string= (string-downcase (gethash "provider" profile)) down))
                 (push id result)))
             (auth-profile-store-profiles store))
    result))

;;; ─── Credential State ───────────────────────────────────────────────────────

(declaim (ftype (function ((or fixnum null) fixnum) string) resolve-token-expiry-state))
(defun resolve-token-expiry-state (expires-at now)
  "Resolve the expiry state of a token.
   Returns: missing | invalid_expires | expired | valid"
  (declare (type (or fixnum null) expires-at) (type fixnum now))
  (cond
    ((null expires-at) "missing")
    ((<= expires-at 0) "invalid_expires")
    ((< expires-at now) "expired")
    (t "valid")))

(declaim (ftype (function (hash-table fixnum) hash-table) evaluate-credential-eligibility))
(defun evaluate-credential-eligibility (credential now)
  "Evaluate whether a credential is eligible for use.
   Returns a hash-table with 'eligible' (boolean) and 'reasonCode' (string)."
  (declare (type hash-table credential) (type fixnum now))
  (let ((result (make-hash-table :test 'equal))
        (cred-type (or (gethash "type" credential) "")))
    (declare (type hash-table result) (type string cred-type))
    (cond
      ;; API keys are always eligible if they have a ref
      ((string= cred-type "api_key")
       (let ((key-ref (gethash "keyRef" credential)))
         (if (or (hash-table-p key-ref)
                 (and (stringp (gethash "key" credential))
                      (not (string= (gethash "key" credential) ""))))
             (setf (gethash "eligible" result) t
                   (gethash "reasonCode" result) "ok")
             (setf (gethash "eligible" result) nil
                   (gethash "reasonCode" result) "no_key"))))
      ;; Tokens: check expiry
      ((string= cred-type "token")
       (let* ((token-ref (gethash "tokenRef" credential))
              (expires-at (gethash "expiresAt" credential))
              (state (resolve-token-expiry-state expires-at now)))
         (declare (type string state))
         (cond
           ((string= state "expired")
            (setf (gethash "eligible" result) nil
                  (gethash "reasonCode" result) "expired"))
           ((string= state "invalid_expires")
            (setf (gethash "eligible" result) nil
                  (gethash "reasonCode" result) "invalid_expires"))
           (t
            ;; missing expiry or valid
            (if (or (hash-table-p token-ref)
                    (and (stringp (gethash "token" credential))
                         (not (string= (gethash "token" credential) ""))))
                (setf (gethash "eligible" result) t
                      (gethash "reasonCode" result) "ok")
                (setf (gethash "eligible" result) nil
                      (gethash "reasonCode" result) "no_token"))))))
      (t
       (setf (gethash "eligible" result) nil
             (gethash "reasonCode" result) "unknown_type")))
    result))

;;; ─── Cooldown ───────────────────────────────────────────────────────────────

(declaim (ftype (function (auth-profile-store string fixnum) null)
                set-profile-cooldown))
(defun set-profile-cooldown (store profile-id expires-at)
  "Set a cooldown expiry for a profile."
  (declare (type auth-profile-store store)
           (type string profile-id)
           (type fixnum expires-at))
  (setf (gethash profile-id (auth-profile-store-cooldowns store)) expires-at)
  nil)

(declaim (ftype (function (auth-profile-store string) (or fixnum null))
                get-profile-cooldown))
(defun get-profile-cooldown (store profile-id)
  "Get the cooldown expiry for a profile, or NIL."
  (declare (type auth-profile-store store) (type string profile-id))
  (gethash profile-id (auth-profile-store-cooldowns store)))

(declaim (ftype (function (auth-profile-store string) null) clear-profile-cooldown))
(defun clear-profile-cooldown (store profile-id)
  "Clear cooldown for a profile."
  (declare (type auth-profile-store store) (type string profile-id))
  (remhash profile-id (auth-profile-store-cooldowns store))
  nil)

(declaim (ftype (function (auth-profile-store fixnum) (or fixnum null))
                get-soonest-cooldown-expiry))
(defun get-soonest-cooldown-expiry (store now)
  "Get the soonest cooldown expiry time that is still in the future, or NIL."
  (declare (type auth-profile-store store) (type fixnum now))
  (let ((soonest nil))
    (declare (type (or fixnum null) soonest))
    (maphash (lambda (k expires)
               (declare (ignore k) (type fixnum expires))
               (when (and (> expires now)
                          (or (null soonest) (< expires soonest)))
                 (setf soonest expires)))
             (auth-profile-store-cooldowns store))
    soonest))

;;; ─── Auth Mode Resolution ───────────────────────────────────────────────────

(declaim (ftype (function (hash-table) (or string null)) resolve-aws-sdk-env-var-name))
(defun resolve-aws-sdk-env-var-name (env)
  "Determine which AWS auth env var is available.
   Preference: bearer token > access keys > profile."
  (declare (type hash-table env))
  (cond
    ((and (stringp (gethash "AWS_BEARER_TOKEN_BEDROCK" env))
          (not (string= (gethash "AWS_BEARER_TOKEN_BEDROCK" env) "")))
     "AWS_BEARER_TOKEN_BEDROCK")
    ((and (stringp (gethash "AWS_ACCESS_KEY_ID" env))
          (not (string= (gethash "AWS_ACCESS_KEY_ID" env) "")))
     "AWS_ACCESS_KEY_ID")
    ((and (stringp (gethash "AWS_PROFILE" env))
          (not (string= (gethash "AWS_PROFILE" env) "")))
     "AWS_PROFILE")
    (t nil)))

(declaim (ftype (function (string) boolean) %bedrock-provider-p))
(defun %bedrock-provider-p (provider)
  "Check if provider is an AWS Bedrock variant."
  (declare (type string provider))
  (let ((down (string-downcase provider)))
    (or (string= down "amazon-bedrock")
        (string= down "aws-bedrock")
        (string= down "bedrock"))))

(declaim (ftype (function (string (or hash-table null) auth-profile-store) string)
                resolve-model-auth-mode))
(defun resolve-model-auth-mode (provider cfg store)
  "Resolve the auth mode for a given provider.
   Returns: api_key | token | mixed | aws-sdk | none"
  (declare (type string provider)
           (type (or hash-table null) cfg)
           (type auth-profile-store store))
  ;; Check for explicit auth override in config
  (when cfg
    (let* ((models (gethash "models" cfg))
           (providers (and (hash-table-p models) (gethash "providers" models)))
           (provider-cfg (and (hash-table-p providers) (gethash provider providers)))
           (auth (and (hash-table-p provider-cfg) (gethash "auth" provider-cfg))))
      (when (stringp auth)
        (return-from resolve-model-auth-mode auth))))
  ;; Bedrock alias detection
  (when (%bedrock-provider-p provider)
    (return-from resolve-model-auth-mode "aws-sdk"))
  ;; Check profile store for mixed/single mode
  (let ((profiles (store-profiles-for-provider store provider))
        (has-token nil)
        (has-api-key nil))
    (dolist (pid profiles)
      (let ((profile (store-get-profile store pid)))
        (when (hash-table-p profile)
          (let ((ptype (gethash "type" profile)))
            (cond
              ((and (stringp ptype) (string= ptype "token")) (setf has-token t))
              ((and (stringp ptype) (string= ptype "api_key")) (setf has-api-key t)))))))
    (cond
      ((and has-token has-api-key) "mixed")
      (has-token "token")
      (has-api-key "api_key")
      (t "none"))))

(declaim (ftype (function (string auth-profile-store (or hash-table null)) string)
                require-api-key))
(defun require-api-key (provider store env)
  "Require and return an API key for the provider.
   Signals an error if none is available."
  (declare (type string provider)
           (type auth-profile-store store)
           (type (or hash-table null) env))
  (let ((profiles (store-profiles-for-provider store provider)))
    (dolist (pid profiles)
      (let ((profile (store-get-profile store pid)))
        (when (hash-table-p profile)
          (let ((ptype (gethash "type" profile))
                (key (gethash "key" profile)))
            (when (and (stringp ptype) (string= ptype "api_key") (stringp key))
              (return-from require-api-key key))))))
    ;; Check env fallback
    (let ((env-key-name (format nil "~A_API_KEY" (string-upcase provider))))
      (when env
        (let ((env-val (gethash env-key-name env)))
          (when (and (stringp env-val) (not (string= env-val "")))
            (return-from require-api-key env-val)))))
    (error "No API key available for provider ~A" provider)))

;;; ─── Round-Robin Selection ──────────────────────────────────────────────────

(declaim (ftype (function (auth-profile-store string fixnum) (or string null))
                pick-next-eligible-profile))
(defun pick-next-eligible-profile (store provider now)
  "Pick the next eligible profile for a provider via round-robin.
   Skips profiles that are on cooldown or ineligible."
  (declare (type auth-profile-store store)
           (type string provider)
           (type fixnum now))
  (let ((candidates (store-profiles-for-provider store provider)))
    (dolist (pid candidates)
      (let ((cooldown (get-profile-cooldown store pid)))
        ;; Skip if on cooldown
        (unless (and cooldown (> cooldown now))
          ;; Check eligibility
          (let ((profile (store-get-profile store pid)))
            (when (hash-table-p profile)
              (let ((result (evaluate-credential-eligibility profile now)))
                (when (gethash "eligible" result)
                  (return-from pick-next-eligible-profile pid))))))))
    nil))
